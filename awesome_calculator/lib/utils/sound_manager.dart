import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// Manages sound effects for the application, optimized for low-latency and concurrent playback.
class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  factory SoundManager() => _instance;
  SoundManager._internal();

  bool _enabled = true;

  /// Enable or disable sound effects
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Check if sound is enabled
  bool get isEnabled => _enabled;

  /// Play a sound effect from assets by creating a new player instance for each call.
  /// This is a robust way to handle overlapping "fire and forget" sounds like key clicks.
  /// The player will dispose of itself automatically after playback is complete.
  Future<void> playSound(String assetPath) async {
    if (!_enabled) return;

    try {
      final player = AudioPlayer();
      // Set the release mode to release the player resources after playing.
      // This is crucial for "fire and forget" sounds to avoid memory leaks.
      player.setReleaseMode(ReleaseMode.release);
      await player.play(AssetSource(assetPath), mode: PlayerMode.lowLatency);
    } catch (e) {
      // print('Error playing sound $assetPath: $e');
    }
  }

  /// Play a sound effect with specific volume (0.0 to 1.0)
  Future<void> playSoundWithVolume(String assetPath, double volume) async {
    if (!_enabled) return;

    try {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.release);
      await player.setVolume(volume.clamp(0.0, 1.0));
      await player.play(AssetSource(assetPath), mode: PlayerMode.lowLatency);
    } catch (e) {
      // print('Error playing sound $assetPath: $e');
    }
  }

  /// Stop is no longer necessary for individual sounds in this model,
  /// but we can keep it as a no-op or for future global control.
  Future<void> stop() async {
    // This method is less relevant now as players are short-lived.
  }

  /// Dispose is no longer necessary as players are self-releasing.
  void dispose() {
    // No-op: Players are managed automatically with ReleaseMode.release.
  }
}
