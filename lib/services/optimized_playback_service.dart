import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flipedit/utils/logger.dart' as logger;

typedef GetCurrentFrame = int Function();
typedef SetCurrentFrame = void Function(int frame);
typedef GetTotalFrames = int Function();
typedef GetDefaultEmptyDurationFrames = int Function();

class OptimizedPlaybackService extends ChangeNotifier {
  final String _logTag = 'PlaybackService';

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  Timer? _playbackTimer;
  final int _fps = 30;

  DateTime? _lastFrameUpdateTime;

  // Dependencies (will be injected)
  final GetCurrentFrame _getCurrentFrame;
  final SetCurrentFrame _setCurrentFrame;
  final GetTotalFrames _getTotalFrames;
  final GetDefaultEmptyDurationFrames _getDefaultEmptyDurationFrames;

  OptimizedPlaybackService({
    required GetCurrentFrame getCurrentFrame,
    required SetCurrentFrame setCurrentFrame,
    required GetTotalFrames getTotalFrames,
    required GetDefaultEmptyDurationFrames getDefaultEmptyDurationFrames,
  }) : _getCurrentFrame = getCurrentFrame,
       _setCurrentFrame = setCurrentFrame,
       _getTotalFrames = getTotalFrames,
       _getDefaultEmptyDurationFrames = getDefaultEmptyDurationFrames;

  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    final currentFrame = _getCurrentFrame();
    isPlayingNotifier.value = true;
    logger.logInfo('▶️ Starting playback from frame $currentFrame', _logTag);

    // Initialize the frame update timestamp
    _lastFrameUpdateTime = DateTime.now();

    // Start a timer that advances the frame at the specified FPS
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (timer) {
        final now = DateTime.now();

        // Calculate ideal frame based on elapsed time since playback started
        // This helps avoid frame drift due to timer inaccuracies
        if (_lastFrameUpdateTime != null) {
          final elapsedMs =
              now.difference(_lastFrameUpdateTime!).inMilliseconds;
          final idealFramesToAdvance = (elapsedMs * _fps / 1000).floor();

          // Only update if at least one frame should have elapsed
          if (idealFramesToAdvance > 0) {
            // Advance to next frame
            final frameNow = _getCurrentFrame();
            final nextFrame = frameNow + idealFramesToAdvance;
            final totalFrames = _getTotalFrames();
            // Use full duration including empty canvas buffer
            final int maxAllowedFrame =
                totalFrames > 0
                    ? totalFrames - 1
                    : _getDefaultEmptyDurationFrames();

            if (nextFrame > maxAllowedFrame) {
              // Stop at the safe end of the timeline
              stopPlayback();
              // Ensure frame is exactly at the end
              if (frameNow != maxAllowedFrame) {
                _setCurrentFrame(maxAllowedFrame);
              }
            } else {
              // Update current frame
              _setCurrentFrame(nextFrame);
              // Update the timestamp
              _lastFrameUpdateTime = now;
            }
          }
        } else {
          // If timestamp is null, initialize it
          _lastFrameUpdateTime = now;
        }
      },
    );
    notifyListeners();
  }

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    final currentFrame = _getCurrentFrame();
    // Cancel the playback timer
    _playbackTimer?.cancel();
    _playbackTimer = null;

    // Reset the timestamp
    _lastFrameUpdateTime = null;

    isPlayingNotifier.value = false;
    logger.logInfo('⏹️ Stopping playback at frame $currentFrame', _logTag);
    notifyListeners();
  }

  /// Toggles the playback state
  void togglePlayPause() {
    if (isPlayingNotifier.value) {
      stopPlayback();
    } else {
      startPlayback();
    }
  }

  @override
  void dispose() {
    logger.logInfo('Disposing PlaybackService', _logTag);
    _playbackTimer?.cancel();
    isPlayingNotifier.dispose();
    super.dispose();
  }
}
