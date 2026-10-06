import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus_lock.dart';
import '../sound.dart';
import '../store.dart';
import '../theme.dart';
import 'meditate.dart' show formatTime;

const focusDurations = [15, 25, 45, 60, 90, 120];

/// Set up a focus session: how long, and how strictly to keep the phone out of reach.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.store});

  final ZenStore store;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> with WidgetsBindingObserver {
  late int _minutes;
  late bool _lock;
  late bool _silence;
  bool _awaitingDndAccess = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final store = widget.store;
    final saved = store.setting<int>('focusMinutes', 25);
    _minutes = focusDurations.contains(saved) ? saved : 25;
    _lock = store.setting<bool>('focusLock', true);
    _silence = store.setting<bool>('focusSilence', false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Do Not Disturb access screen: switch the option on if access was given.
    if (state == AppLifecycleState.resumed && _awaitingDndAccess) {
      _awaitingDndAccess = false;
      FocusLock.hasDndAccess().then((granted) {
        if (granted && mounted) _setSilence(true);
      });
    }
  }

  void _setSilence(bool on) {
    setState(() => _silence = on);
    widget.store.setSetting('focusSilence', on);
  }

  Future<void> _toggleSilence(bool on) async {
    if (!on || await FocusLock.hasDndAccess()) {
      _setSilence(on);
      return;
    }
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Allow Do Not Disturb'),
        content: const Text(
          'Android asks you to allow this once. On the next screen, find Zen and switch it on, then come back.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open settings')),
        ],
      ),
    );
    if (open == true) {
      _awaitingDndAccess = true;
      await FocusLock.openDndSettings();
    }
  }

  Future<void> _start() async {
    // There is no way to end a session early, so make starting one a clear decision.
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Focus for $_minutes minutes?'),
        content: const Text('There is no stop button. The session ends only when the timer runs out.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FocusSessionPage(store: widget.store, minutes: _minutes, lock: _lock, silence: _silence),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const ScreenHeader(eyebrow: 'Focus', title: 'Put the phone down'),
        Text(
          'Zen stays on screen and other apps stay out of reach until the timer ends. '
          'There is no stop button, so pick a length you mean.',
          style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
        ),
        const SizedBox(height: 20),
        ChoiceChips<int>(
          options: {
            for (final m in focusDurations) m: m < 60 ? '$m min' : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}',
          },
          selected: _minutes,
          onSelected: (m) {
            setState(() => _minutes = m);
            widget.store.setSetting('focusMinutes', m);
          },
        ),
        const SizedBox(height: 20),
        ZenToggle(
          label: 'Lock phone to Zen (app pinning)',
          value: _lock,
          onChanged: (v) {
            setState(() => _lock = v);
            widget.store.setSetting('focusLock', v);
          },
        ),
        ZenToggle(label: 'Silence notifications (Do Not Disturb)', value: _silence, onChanged: _toggleSilence),
        const SizedBox(height: 20),
        Center(
          child: FilledButton(onPressed: _start, child: const Text('Start focus')),
        ),
        const SizedBox(height: 28),
        ZenCard(
          child: Text(
            'How the lock works: Android asks you to confirm pinning, then Home, Recents and notifications '
            'are blocked. Android itself always keeps one emergency way out (hold Back and Recents together), '
            'which no app can remove. To make that harder, turn on "Ask for PIN before unpinning" in your '
            'phone\'s App pinning settings.',
            style: TextStyle(fontSize: 13, height: 1.5, color: c.muted),
          ),
        ),
      ],
    );
  }
}

/// The running focus session. Full screen, and it only closes once the timer has finished.
class FocusSessionPage extends StatefulWidget {
  const FocusSessionPage({
    super.key,
    required this.store,
    required this.minutes,
    required this.lock,
    required this.silence,
  });

  final ZenStore store;
  final int minutes;
  final bool lock;
  final bool silence;

  @override
  State<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends State<FocusSessionPage> with WidgetsBindingObserver {
  late final DateTime _startedAt;
  late final DateTime _endAt;
  late double _remaining;
  Timer? _timer;
  bool _locked = false;
  bool _everLocked = false;
  bool _unpinned = false;
  bool? _dndOn;
  bool _released = false;
  bool _done = false;

  int get _total => widget.minutes * 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = clock.now();
    _endAt = _startedAt.add(Duration(seconds: _total));
    _remaining = _total.toDouble();
    if (widget.lock) FocusLock.startLock();
    if (widget.silence) {
      FocusLock.setDnd(true).then((ok) {
        // Remembered so a crash mid-session can't leave Do Not Disturb on forever.
        if (ok) widget.store.setSetting('dndActive', true);
        if (mounted) setState(() => _dndOn = ok);
      });
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_done) _tick();
  }

  Future<void> _tick() async {
    final remaining = _endAt.difference(clock.now()).inMilliseconds / 1000;
    if (remaining <= 0) {
      _complete();
      return;
    }
    var locked = _locked;
    if (widget.lock) locked = await FocusLock.isLocked();
    if (!mounted || _done) return;
    setState(() {
      _remaining = remaining;
      _locked = locked;
      if (locked) _everLocked = true;
      if (_everLocked && !locked) _unpinned = true;
    });
  }

  /// Undo everything the session changed on the phone. Safe to call twice.
  void _release() {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    if (widget.lock) FocusLock.stopLock();
    if (widget.silence) {
      FocusLock.setDnd(false);
      widget.store.setSetting('dndActive', false);
    }
  }

  void _complete() {
    if (_done) return;
    _release();
    Sound.bell();
    HapticFeedback.heavyImpact();
    widget.store.addSession('focus', _total);
    setState(() {
      _done = true;
      _remaining = 0;
    });
  }

  String get _lockStatus {
    if (!widget.lock) return 'Lock is off for this session';
    if (_locked) return 'Phone is locked to Zen';
    if (_unpinned) return 'Zen was unpinned. The timer keeps going.';
    return 'Tap "Pin" on the Android prompt to lock';
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final ringSize = (MediaQuery.sizeOf(context).width * 0.72).clamp(0, 280).toDouble();

    return PopScope(
      canPop: _done,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ScreenHeader(
                    eyebrow: 'Focus · ${widget.minutes} min',
                    title: _done ? 'Focus complete' : 'Stay with it',
                  ),
                ),
                const Spacer(),
                SizedBox.square(
                  dimension: ringSize,
                  child: CustomPaint(
                    painter: RingPainter(progress: _remaining / _total, track: c.line, color: c.accent),
                    child: Center(
                      child: Text(
                        _done ? '✓' : formatTime(_remaining),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w300,
                          color: c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _done ? 'Well done. ${widget.minutes} minutes, undistracted.' : 'The phone can wait. You are here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'serif', fontSize: 20, height: 1.4, color: c.ink),
                ),
                const SizedBox(height: 16),
                if (!_done) ...[
                  _Status(text: _lockStatus, ok: !widget.lock || _locked),
                  if (widget.lock && !_locked && clock.now().difference(_startedAt).inSeconds >= 5)
                    TextButton(onPressed: FocusLock.startLock, child: const Text('Lock again')),
                  if (widget.silence && _dndOn != null)
                    _Status(text: _dndOn! ? 'Notifications silenced' : 'Couldn\'t turn on Do Not Disturb', ok: _dndOn!),
                ],
                const Spacer(),
                if (_done)
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))
                else
                  Text('Ends by itself when the timer runs out', style: TextStyle(fontSize: 13, color: c.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.lock_outline : Icons.lock_open, size: 16, color: ok ? c.accent : c.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 14, color: c.muted)),
          ),
        ],
      ),
    );
  }
}
