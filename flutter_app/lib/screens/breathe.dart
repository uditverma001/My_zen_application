import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wake.dart';

import '../store.dart';
import '../theme.dart';

class BreathStep {
  const BreathStep(this.label, this.seconds, this.scale);

  final String label;
  final int seconds;
  final double scale;
}

class BreathPattern {
  const BreathPattern(this.label, this.description, this.steps);

  final String label;
  final String description;
  final List<BreathStep> steps;
}

const _inhale = 1.0, _exhale = 0.45;

const patterns = {
  'calm': BreathPattern('Calm', 'In for 4, out for 6. A longer exhale settles the nervous system.', [
    BreathStep('Breathe in', 4, _inhale),
    BreathStep('Breathe out', 6, _exhale),
  ]),
  'box': BreathPattern('Box', 'In 4, hold 4, out 4, hold 4. Steady and focusing.', [
    BreathStep('Breathe in', 4, _inhale),
    BreathStep('Hold', 4, _inhale),
    BreathStep('Breathe out', 4, _exhale),
    BreathStep('Hold', 4, _exhale),
  ]),
  'relax': BreathPattern('4-7-8', 'In 4, hold 7, out 8. Helpful before sleep.', [
    BreathStep('Breathe in', 4, _inhale),
    BreathStep('Hold', 7, _inhale),
    BreathStep('Breathe out', 8, _exhale),
  ]),
  'even': BreathPattern('Balance', 'In 5, out 5. Simple, even breathing.', [
    BreathStep('Breathe in', 5, _inhale),
    BreathStep('Breathe out', 5, _exhale),
  ]),
};

class BreatheScreen extends StatefulWidget {
  const BreatheScreen({super.key, required this.store});

  final ZenStore store;

  @override
  State<BreatheScreen> createState() => _BreatheScreenState();
}

class _BreatheScreenState extends State<BreatheScreen> {
  late String _pattern;
  bool _running = false;
  int _step = 0;
  int _left = 0;
  int _cycles = 0;
  double _scale = _exhale;
  Duration _scaleDuration = Duration.zero;
  DateTime? _startedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final saved = widget.store.setting<String>('breath', 'calm');
    _pattern = patterns.containsKey(saved) ? saved : 'calm';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _runStep(int index) {
    final step = patterns[_pattern]!.steps[index];
    HapticFeedback.lightImpact();
    setState(() {
      if (index == 0 && _startedAt != null && _step != 0) _cycles++;
      _step = index;
      _left = step.seconds;
      _scale = step.scale;
      _scaleDuration = Duration(seconds: step.seconds);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left > 1) {
        setState(() => _left--);
      } else {
        t.cancel();
        if (_running) _runStep((index + 1) % patterns[_pattern]!.steps.length);
      }
    });
  }

  void _start() {
    setState(() {
      _running = true;
      _cycles = 0;
      _step = 0;
      _startedAt = DateTime.now();
    });
    keepAwake(true);
    _runStep(0);
  }

  void _stop() {
    _timer?.cancel();
    final seconds = DateTime.now().difference(_startedAt!).inSeconds;
    keepAwake(false);
    setState(() {
      _running = false;
      _scale = _exhale;
      _scaleDuration = const Duration(milliseconds: 1500);
    });
    if (seconds >= 30) {
      widget.store.addSession('breathe', seconds);
      final minutes = seconds ~/ 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nicely done: ${minutes == 0 ? 'under a minute' : '$minutes min'} of breathing')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ZenColors.of(context);
    final pattern = patterns[_pattern]!;
    final size = MediaQuery.sizeOf(context).width.clamp(0, 520) * 0.72;
    final circleSize = size.clamp(0, 300).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const ScreenHeader(eyebrow: 'Breathe', title: 'Follow the circle'),
        ChoiceChips<String>(
          options: {for (final e in patterns.entries) e.key: e.value.label},
          selected: _pattern,
          enabled: !_running,
          onSelected: (key) {
            setState(() => _pattern = key);
            widget.store.setSetting('breath', key);
          },
        ),
        const SizedBox(height: 12),
        Text(pattern.description, style: TextStyle(fontSize: 14, height: 1.5, color: c.muted)),
        const SizedBox(height: 28),
        Center(
          child: SizedBox.square(
            dimension: circleSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line),
                  ),
                ),
                AnimatedScale(
                  scale: _scale,
                  duration: _scaleDuration,
                  curve: Curves.easeInOut,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.4),
                        colors: [Color.lerp(c.accent, Colors.white, 0.3)!, c.accent],
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _running ? pattern.steps[_step].label : 'Ready',
                      style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.accentInk),
                    ),
                    const SizedBox(height: 4),
                    Text(_running ? '$_left' : '', style: TextStyle(fontSize: 16, color: c.accentInk)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _running && _cycles > 0 ? '$_cycles ${_cycles == 1 ? 'cycle' : 'cycles'}' : '',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: _running ? _stop : _start, child: Text(_running ? 'Finish' : 'Begin')),
        ),
      ],
    );
  }
}
