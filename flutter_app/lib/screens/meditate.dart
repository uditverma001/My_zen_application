import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wake.dart';

import '../sound.dart';
import '../store.dart';
import '../theme.dart';

const durations = [1, 3, 5, 10, 15, 20, 30];

String formatTime(double seconds) {
  final s = math.max(0, seconds.ceil());
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class MeditateScreen extends StatefulWidget {
  const MeditateScreen({super.key, required this.store});

  final ZenStore store;

  @override
  State<MeditateScreen> createState() => _MeditateScreenState();
}

class _MeditateScreenState extends State<MeditateScreen> with WidgetsBindingObserver {
  late int _minutes;
  late bool _ambient;
  late bool _interval;
  bool _running = false;
  bool _paused = false;
  DateTime _endAt = DateTime.now();
  late double _remaining;
  int _lastBellMinute = 0;
  Timer? _tick;

  int get _total => _minutes * 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final store = widget.store;
    final saved = store.setting<int>('minutes', 5);
    _minutes = durations.contains(saved) ? saved : 5;
    _ambient = store.setting<bool>('ambient', false);
    _interval = store.setting<bool>('interval', false);
    _remaining = _total.toDouble();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    Sound.stopAmbient();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catch up on time passed while the app was in the background.
    if (state == AppLifecycleState.resumed && _running && !_paused) _onTick();
  }

  void _onTick() {
    final remaining = _endAt.difference(DateTime.now()).inMilliseconds / 1000;
    if (remaining <= 0) {
      _finish(completed: true);
      return;
    }
    setState(() => _remaining = remaining);
    final elapsedMinutes = (_total - remaining) ~/ 60;
    if (_interval && elapsedMinutes > _lastBellMinute) {
      _lastBellMinute = elapsedMinutes;
      Sound.bell(volume: 0.4);
    }
  }

  void _startTicking() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    keepAwake(true);
    if (_ambient) Sound.startAmbient();
  }

  void _stopTicking() {
    _tick?.cancel();
    keepAwake(false);
    Sound.stopAmbient();
  }

  void _start() {
    setState(() {
      _running = true;
      _paused = false;
      _remaining = _total.toDouble();
      _endAt = DateTime.now().add(Duration(seconds: _total));
      _lastBellMinute = 0;
    });
    Sound.bell();
    _startTicking();
  }

  void _pause() {
    _stopTicking();
    setState(() {
      _paused = true;
      _remaining = _endAt.difference(DateTime.now()).inMilliseconds / 1000;
    });
  }

  void _resume() {
    setState(() {
      _paused = false;
      _endAt = DateTime.now().add(Duration(milliseconds: (_remaining * 1000).round()));
    });
    _startTicking();
  }

  void _finish({required bool completed}) {
    final remaining = _paused ? _remaining : _endAt.difference(DateTime.now()).inMilliseconds / 1000;
    final elapsed = completed ? _total : (_total - math.max(0, remaining)).round();
    _stopTicking();
    setState(() {
      _running = false;
      _paused = false;
      _remaining = completed ? 0 : _total.toDouble();
    });

    if (completed) {
      Sound.bell();
      Future.delayed(const Duration(milliseconds: 2500), () => Sound.bell(volume: 0.7));
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_minutes minute${_minutes == 1 ? '' : 's'} of stillness. Well done.')));
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_running) setState(() => _remaining = _total.toDouble());
      });
    }
    if (elapsed >= 60) widget.store.addSession('meditate', elapsed);
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final ringSize = (MediaQuery.sizeOf(context).width * 0.72).clamp(0, 280).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const ScreenHeader(eyebrow: 'Meditate', title: 'Sit quietly'),
        ChoiceChips<int>(
          options: {for (final m in durations) m: '$m min'},
          selected: _minutes,
          enabled: !_running,
          onSelected: (m) {
            setState(() {
              _minutes = m;
              _remaining = _total.toDouble();
            });
            widget.store.setSetting('minutes', m);
          },
        ),
        const SizedBox(height: 28),
        Center(
          child: SizedBox.square(
            dimension: ringSize,
            child: CustomPaint(
              painter: RingPainter(progress: _remaining / _total, track: c.line, color: c.accent),
              child: Center(
                child: Text(
                  formatTime(_remaining),
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
        ),
        const SizedBox(height: 12),
        ZenToggle(
          label: 'Soft background sound',
          value: _ambient,
          onChanged: (v) {
            setState(() => _ambient = v);
            widget.store.setSetting('ambient', v);
            if (_running && !_paused) v ? Sound.startAmbient() : Sound.stopAmbient();
          },
        ),
        ZenToggle(
          label: 'Gentle bell every minute',
          value: _interval,
          onChanged: (v) {
            setState(() => _interval = v);
            widget.store.setSetting('interval', v);
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            FilledButton(
              onPressed: !_running ? _start : (_paused ? _resume : _pause),
              child: Text(!_running ? 'Begin' : (_paused ? 'Resume' : 'Pause')),
            ),
            if (_running) OutlinedButton(onPressed: () => _finish(completed: false), child: const Text('End')),
          ],
        ),
      ],
    );
  }
}
