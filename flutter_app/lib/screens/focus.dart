import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus_config.dart';
import '../focus_lock.dart';
import '../sound.dart';
import '../store.dart';
import '../theme.dart';
import 'meditate.dart' show formatTime;

const focusDurations = [15, 25, 45, 60, 90, 120];

/// How a session keeps you off the phone: the app blocker (allowed apps work), or app pinning.
enum FocusMode { blocker, pin }

/// True while a session page is on screen, so it is never opened twice.
final focusSessionOpen = ValueNotifier<bool>(false);

Future<void> openFocusSession(
  BuildContext context,
  ZenStore store, {
  required FocusMode mode,
  required DateTime since,
  required DateTime until,
  bool silence = false,
}) async {
  if (focusSessionOpen.value) return;
  focusSessionOpen.value = true;
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FocusSessionPage(store: store, mode: mode, since: since, until: until, silence: silence),
      ),
    );
  } finally {
    focusSessionOpen.value = false;
  }
}

/// Set up focus: start a session now, choose allowed apps, and manage schedules.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.store});

  final ZenStore store;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> with WidgetsBindingObserver {
  late int _minutes;
  late bool _silence;
  late FocusConfig _config;
  bool _guard = false;
  Map<String, AppInfo> _apps = {};
  bool _awaitingDndAccess = false;

  ZenStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final saved = _store.setting<int>('focusMinutes', 25);
    _minutes = focusDurations.contains(saved) ? saved : 25;
    _silence = _store.setting<bool>('focusSilence', false);
    _config = FocusConfig.load(_store);
    _refreshGuard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _refreshGuard();
    // Back from the Do Not Disturb access screen: switch the option on if access was given.
    if (_awaitingDndAccess) {
      _awaitingDndAccess = false;
      FocusLock.hasDndAccess().then((granted) {
        if (granted && mounted) _setSilence(true);
      });
    }
  }

  Future<void> _refreshGuard() async {
    final guard = await FocusLock.guardEnabled();
    if (!mounted) return;
    setState(() => _guard = guard);
    if (guard && _apps.isEmpty) await _loadApps();
  }

  Future<void> _loadApps() async {
    final apps = await FocusLock.apps();
    if (!mounted || apps.isEmpty) return;
    setState(() => _apps = {for (final a in apps) a.package: a});
    // First time only: pre-select WhatsApp and Google Pay if they're installed.
    if (!FocusConfig.hasAllowedApps(_store)) {
      await _saveConfig(
        FocusConfig(
          allowed: [
            for (final p in suggestedApps)
              if (_apps.containsKey(p)) p,
          ],
          schedules: _config.schedules,
        ),
      );
    }
  }

  Future<bool> _saveConfig(FocusConfig next) async {
    final ok = await next.save(_store);
    if (!mounted) return ok;
    if (ok) {
      setState(() => _config = next);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Focus settings can\'t change during a focus session')));
    }
    return ok;
  }

  void _setSilence(bool on) {
    setState(() => _silence = on);
    _store.setSetting('focusSilence', on);
  }

  Future<void> _toggleSilence(bool on) async {
    if (!on || await FocusLock.hasDndAccess()) {
      _setSilence(on);
      return;
    }
    if (!mounted) return;
    final open = await _ask(
      title: 'Allow Do Not Disturb',
      body: 'Android asks you to allow this once. On the next screen, find Zen and switch it on, then come back.',
      yes: 'Open settings',
      no: 'Not now',
    );
    if (open) {
      _awaitingDndAccess = true;
      await FocusLock.openDndSettings();
    }
  }

  Future<bool> _ask({required String title, required String body, required String yes, String no = 'Cancel'}) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(no)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(yes)),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _start() async {
    // There is no way to end a session early, so make starting one a clear decision.
    final go = await _ask(
      title: 'Focus for $_minutes minutes?',
      body: 'There is no stop button. The session ends only when the timer runs out.',
      yes: 'Start',
    );
    if (!go || !mounted) return;
    final now = clock.now();
    final until = now.add(Duration(minutes: _minutes));
    if (_guard && !await FocusLock.startManual(until)) return;
    if (!mounted) return;
    await openFocusSession(
      context,
      _store,
      mode: _guard ? FocusMode.blocker : FocusMode.pin,
      since: now,
      until: until,
      silence: _silence,
    );
  }

  Future<void> _addApp() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AppPicker(apps: _apps.values.where((a) => !_config.allowed.contains(a.package)).toList()),
    );
    if (picked == null) return;
    await _saveConfig(FocusConfig(allowed: [..._config.allowed, picked], schedules: _config.schedules));
  }

  Future<void> _removeApp(String package) =>
      _saveConfig(FocusConfig(allowed: [..._config.allowed]..remove(package), schedules: _config.schedules));

  Future<void> _addSchedule() async {
    final schedule = await showModalBottomSheet<FocusSchedule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ScheduleEditor(),
    );
    if (schedule == null || !mounted) return;
    if (schedule.isActiveAt(clock.now())) {
      final go = await _ask(
        title: 'This starts right now',
        body: 'It is ${schedule.timeLabel} today, so focus begins as soon as you save, with no stop button.',
        yes: 'Save and start',
      );
      if (!go) return;
    }
    await _saveConfig(FocusConfig(allowed: _config.allowed, schedules: [..._config.schedules, schedule]));
  }

  Future<void> _updateSchedule(int index, FocusSchedule? replacement) {
    final schedules = [..._config.schedules];
    if (replacement == null) {
      schedules.removeAt(index);
    } else {
      schedules[index] = replacement;
    }
    return _saveConfig(FocusConfig(allowed: _config.allowed, schedules: schedules));
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final muted = TextStyle(fontSize: 14, height: 1.5, color: c.muted);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const ScreenHeader(eyebrow: 'Focus', title: 'Put the phone down'),
        if (_guard)
          const _Status(text: 'App blocker is on', ok: true)
        else
          _GuardSetup(onTurnOn: FocusLock.openGuardSettings, onAppInfo: FocusLock.openAppInfo),
        const SizedBox(height: 24),
        const _SectionTitle('Start now'),
        ChoiceChips<int>(
          options: {
            for (final m in focusDurations) m: m < 60 ? '$m min' : '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}',
          },
          selected: _minutes,
          onSelected: (m) {
            setState(() => _minutes = m);
            _store.setSetting('focusMinutes', m);
          },
        ),
        const SizedBox(height: 8),
        ZenToggle(label: 'Silence notifications (Do Not Disturb)', value: _silence, onChanged: _toggleSilence),
        const SizedBox(height: 8),
        Center(
          child: FilledButton(onPressed: _start, child: const Text('Start focus')),
        ),
        const SizedBox(height: 8),
        Text(
          _guard
              ? 'There is no stop button. Only Phone and your allowed apps open until the timer ends.'
              : 'There is no stop button. Without the app blocker, Zen pins itself to the screen instead, '
                    'and allowed apps and schedules are off.',
          textAlign: TextAlign.center,
          style: muted.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 28),
        _SectionTitle('Allowed during focus', trailing: '${_config.allowed.length} of $maxAllowedApps'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: Icon(Icons.call, size: 18, color: c.accent),
              label: const Text('Phone (always)'),
              backgroundColor: c.surface,
              side: BorderSide(color: c.line),
            ),
            for (final p in _config.allowed)
              InputChip(
                avatar: _AppIcon(app: _apps[p]),
                label: Text(_apps[p]?.label ?? p),
                onDeleted: () => _removeApp(p),
                backgroundColor: c.surface,
                side: BorderSide(color: c.line),
              ),
            if (_config.allowed.length < maxAllowedApps)
              ActionChip(
                avatar: Icon(Icons.add, size: 18, color: c.accent),
                label: const Text('Add app'),
                onPressed: _guard && _apps.isNotEmpty ? _addApp : null,
                backgroundColor: c.surface,
                side: BorderSide(color: c.line),
              ),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Schedules'),
        if (_config.schedules.isEmpty)
          Text('Focus starts by itself at the times you set, even when Zen is closed.', style: muted),
        for (final (i, s) in _config.schedules.indexed) ...[
          ZenCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.timeLabel, style: TextStyle(fontSize: 16, color: c.ink)),
                      Text(s.daysLabel, style: TextStyle(fontSize: 13, color: c.muted)),
                    ],
                  ),
                ),
                Switch(
                  value: s.enabled,
                  activeTrackColor: c.accent,
                  onChanged: (v) => _updateSchedule(i, s.copyWith(enabled: v)),
                ),
                IconButton(
                  tooltip: 'Delete schedule',
                  icon: Icon(Icons.delete_outline, color: c.muted),
                  onPressed: () => _updateSchedule(i, null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: _guard ? _addSchedule : null,
            icon: const Icon(Icons.schedule),
            label: const Text('Add schedule'),
          ),
        ),
        if (!_guard) ...[
          const SizedBox(height: 8),
          Text(
            'Allowed apps and schedules need the app blocker.',
            textAlign: TextAlign.center,
            style: muted.copyWith(fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: 'serif', fontSize: 20, color: c.ink),
            ),
          ),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 13, color: c.muted)),
        ],
      ),
    );
  }
}

class _GuardSetup extends StatelessWidget {
  const _GuardSetup({required this.onTurnOn, required this.onAppInfo});

  final VoidCallback onTurnOn;
  final VoidCallback onAppInfo;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final small = TextStyle(fontSize: 13, height: 1.5, color: c.muted);
    return ZenCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Turn on the app blocker', style: TextStyle(fontSize: 17, color: c.ink)),
          const SizedBox(height: 6),
          Text(
            'It lets your allowed apps work during focus, blocks everything else, and runs your schedules. '
            'On the next screen, open Installed apps → Zen focus blocker and switch it on. '
            'Zen only checks which app is open, never what is on screen.',
            style: small,
          ),
          const SizedBox(height: 8),
          Text(
            'If the switch is greyed out ("restricted setting"): open App info, tap ⋮ in the corner, '
            'choose "Allow restricted settings", then try again.',
            style: small,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: onTurnOn, child: const Text('Turn on')),
              OutlinedButton(onPressed: onAppInfo, child: const Text('App info')),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, this.size = 20});

  final AppInfo? app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = app?.icon;
    if (icon == null) return Icon(Icons.apps, size: size, color: ZenColors.of(context).muted);
    return Image.memory(icon, width: size, height: size, gaplessPlayback: true);
  }
}

/// Bottom sheet listing installed apps, with search.
class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.apps});

  final List<AppInfo> apps;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final q = _query.toLowerCase();
    final apps = widget.apps.where((a) => a.label.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search apps',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, i) => ListTile(
                leading: _AppIcon(app: apps[i], size: 36),
                title: Text(apps[i].label),
                onTap: () => Navigator.pop(context, apps[i].package),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for creating a schedule.
class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor();

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 11, minute: 0);
  final Set<int> _days = {1, 2, 3, 4, 5};

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final schedule = FocusSchedule(days: {..._days}, start: _minutes(_start), end: _minutes(_end));
    final valid = _days.isNotEmpty && schedule.start != schedule.end;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New schedule',
            style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _TimeButton(label: 'Starts', time: formatMinutes(schedule.start), onTap: () => _pick(true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeButton(label: 'Ends', time: formatMinutes(schedule.end), onTap: () => _pick(false)),
              ),
            ],
          ),
          if (schedule.overnight) ...[
            const SizedBox(height: 8),
            Text('Ends the next morning.', style: TextStyle(fontSize: 13, color: c.muted)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(weekdayShort[d - 1]),
                  selected: _days.contains(d),
                  showCheckmark: false,
                  selectedColor: c.accentSoft,
                  backgroundColor: c.surface,
                  side: BorderSide(color: _days.contains(d) ? c.accent : c.line),
                  onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(context, schedule) : null,
            child: const Text('Save schedule'),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.time, required this.onTap});

  final String label;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ZenCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 2),
            Text(time, style: TextStyle(fontSize: 20, color: c.ink)),
          ],
        ),
      ),
    );
  }
}

/// The running focus session. Full screen, and it only closes once the session has finished.
class FocusSessionPage extends StatefulWidget {
  const FocusSessionPage({
    super.key,
    required this.store,
    required this.mode,
    required this.since,
    required this.until,
    this.silence = false,
  });

  final ZenStore store;
  final FocusMode mode;
  final DateTime since;
  final DateTime until;
  final bool silence;

  @override
  State<FocusSessionPage> createState() => _FocusSessionPageState();
}

class _FocusSessionPageState extends State<FocusSessionPage> with WidgetsBindingObserver {
  late DateTime _since = widget.since;
  late DateTime _until = widget.until;
  late double _remaining = _until.difference(clock.now()).inMilliseconds / 1000;
  late final DateTime _openedAt = clock.now();
  Timer? _timer;
  bool _locked = false;
  bool _everLocked = false;
  bool _unpinned = false;
  bool? _dndOn;
  bool _released = false;
  bool _done = false;
  List<AppInfo> _allowed = const [];

  bool get _pin => widget.mode == FocusMode.pin;

  double get _total => _until.difference(_since).inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_pin) FocusLock.startLock();
    if (widget.silence) {
      FocusLock.setDnd(true).then((ok) {
        // Remembered so a crash mid-session can't leave Do Not Disturb on forever.
        if (ok) widget.store.setSetting('dndActive', true);
        if (mounted) setState(() => _dndOn = ok);
      });
    }
    if (!_pin) _loadAllowed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _loadAllowed() async {
    final allowed = FocusConfig.load(widget.store).allowed;
    final apps = {for (final a in await FocusLock.apps()) a.package: a};
    if (!mounted) return;
    setState(() => _allowed = [for (final p in allowed) apps[p] ?? AppInfo(package: p, label: p)]);
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
    if (_done) return;
    if (_pin) {
      final remaining = _until.difference(clock.now()).inMilliseconds / 1000;
      if (remaining <= 0) return _complete();
      final locked = await FocusLock.isLocked();
      if (!mounted || _done) return;
      setState(() {
        _remaining = remaining;
        _locked = locked;
        if (locked) _everLocked = true;
        if (_everLocked && !locked) _unpinned = true;
      });
    } else {
      // The blocker on the Android side is the source of truth; it may also extend the session.
      final state = await FocusLock.state();
      if (!mounted || _done) return;
      if (!state.active) return _complete();
      setState(() {
        _since = state.since ?? _since;
        _until = state.until ?? _until;
        _remaining = _until.difference(clock.now()).inMilliseconds / 1000;
      });
    }
  }

  /// Undo everything the session changed on the phone. Safe to call twice.
  void _release() {
    if (_released) return;
    _released = true;
    _timer?.cancel();
    if (_pin) FocusLock.stopLock();
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
    widget.store.addSession('focus', _total.round());
    setState(() {
      _done = true;
      _remaining = 0;
    });
  }

  String get _statusText {
    if (!_pin) return 'Other apps are blocked until ${formatMinutes(_until.hour * 60 + _until.minute)}';
    if (_locked) return 'Phone is locked to Zen';
    if (_unpinned) return 'Zen was unpinned. The timer keeps going.';
    return 'Tap "Pin" on the Android prompt to lock';
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final ringSize = (MediaQuery.sizeOf(context).width * 0.66).clamp(0, 260).toDouble();
    final minutes = (_total / 60).round();

    return PopScope(
      canPop: _done,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ScreenHeader(
                    eyebrow: 'Focus · $minutes min',
                    title: _done ? 'Focus complete' : 'Stay with it',
                  ),
                ),
                const Spacer(),
                SizedBox.square(
                  dimension: ringSize,
                  child: CustomPaint(
                    painter: RingPainter(
                      progress: _total <= 0 ? 0 : _remaining / _total,
                      track: c.line,
                      color: c.accent,
                    ),
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
                  _done ? 'Well done. $minutes minutes, undistracted.' : 'The phone can wait. You are here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'serif', fontSize: 20, height: 1.4, color: c.ink),
                ),
                const SizedBox(height: 16),
                if (!_done) ...[
                  _Status(text: _statusText, ok: !_pin || _locked),
                  if (_pin && !_locked && clock.now().difference(_openedAt).inSeconds >= 5)
                    TextButton(onPressed: FocusLock.startLock, child: const Text('Lock again')),
                  if (widget.silence && _dndOn != null)
                    _Status(text: _dndOn! ? 'Notifications silenced' : 'Couldn\'t turn on Do Not Disturb', ok: _dndOn!),
                ],
                const Spacer(),
                if (_done)
                  FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))
                else if (!_pin) ...[
                  Text('Allowed now', style: TextStyle(fontSize: 13, color: c.muted)),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _LaunchButton(
                        icon: Icon(Icons.call, color: c.accent, size: 28),
                        label: 'Phone',
                        onTap: FocusLock.openDialer,
                      ),
                      for (final app in _allowed)
                        _LaunchButton(
                          icon: _AppIcon(app: app, size: 32),
                          label: app.label,
                          onTap: () => FocusLock.launchApp(app.package),
                        ),
                    ],
                  ),
                ] else
                  Text('Ends by itself when the timer runs out', style: TextStyle(fontSize: 13, color: c.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  const _LaunchButton({required this.icon, required this.label, required this.onTap});

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: icon,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ],
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
