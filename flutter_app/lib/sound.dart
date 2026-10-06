import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Bell and ambient sound, played from audio files bundled in the app.
class Sound {
  Sound._();

  static AudioPlayer? _ambient;
  static Timer? _fade;

  static Future<void> init() async {
    // Let the bell ring over the ambient sound instead of stopping it.
    await AudioPlayer.global.setAudioContext(AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
  }

  static Future<void> bell({double volume = 1.0}) async {
    final player = AudioPlayer();
    player.onPlayerComplete.first.then((_) => player.dispose());
    await player.setVolume(volume);
    await player.play(AssetSource('sounds/bell.wav'));
  }

  static Future<void> startAmbient() async {
    if (_ambient != null) return;
    final player = _ambient = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(0);
    await player.play(AssetSource('sounds/ambient.wav'));
    _fadeTo(player, 0.6, const Duration(seconds: 3));
  }

  static void stopAmbient() {
    final player = _ambient;
    if (player == null) return;
    _ambient = null;
    _fadeTo(player, 0, const Duration(milliseconds: 1500), then: player.dispose);
  }

  static void _fadeTo(AudioPlayer player, double target, Duration over, {Future<void> Function()? then}) {
    _fade?.cancel();
    const steps = 30;
    final start = player.volume;
    var i = 0;
    _fade = Timer.periodic(over ~/ steps, (t) {
      i++;
      player.setVolume(start + (target - start) * i / steps);
      if (i >= steps) {
        t.cancel();
        then?.call();
      }
    });
  }
}
