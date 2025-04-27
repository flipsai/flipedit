import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart'; // For msToFrames
import 'package:flipedit/utils/logger.dart' as logger;

// Placeholder for TimelineNavigationService - will be properly typed later
typedef GetCurrentFrame = int Function();
typedef SetCurrentFrame = void Function(int frame);
typedef GetTotalFrames = int Function();
typedef GetDefaultEmptyDurationFrames = int Function();

class PlaybackService extends ChangeNotifier {
  final String _logTag = 'PlaybackService';

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  Timer? _playbackTimer;
  // TODO: Get FPS from project settings/config
  final int _fps = 30;

  // Dependencies (will be injected)
  final GetCurrentFrame _getCurrentFrame;
  final SetCurrentFrame _setCurrentFrame;
  final GetTotalFrames _getTotalFrames;
  final GetDefaultEmptyDurationFrames _getDefaultEmptyDurationFrames;

  PlaybackService({
    required GetCurrentFrame getCurrentFrame,
    required SetCurrentFrame setCurrentFrame,
    required GetTotalFrames getTotalFrames,
    required GetDefaultEmptyDurationFrames getDefaultEmptyDurationFrames,
  })  : _getCurrentFrame = getCurrentFrame,
        _setCurrentFrame = setCurrentFrame,
        _getTotalFrames = getTotalFrames,
        _getDefaultEmptyDurationFrames = getDefaultEmptyDurationFrames;


  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    final currentFrame = _getCurrentFrame();
    isPlayingNotifier.value = true;
    logger.logInfo('▶️ Starting playback from frame $currentFrame', _logTag);

    // Start a timer that advances the frame at the specified FPS
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(Duration(milliseconds: (1000 / _fps).round()), (timer) {
      // Advance to next frame
      final frameNow = _getCurrentFrame();
      final nextFrame = frameNow + 1;
      final totalFrames = _getTotalFrames();
      // Use full duration including empty canvas buffer
      final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : _getDefaultEmptyDurationFrames();

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
      }
    });
    notifyListeners(); // Notify that state changed
  }

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    final currentFrame = _getCurrentFrame();
    // Cancel the playback timer
    _playbackTimer?.cancel();
    _playbackTimer = null;

    isPlayingNotifier.value = false;
    logger.logInfo('⏹️ Stopping playback at frame $currentFrame', _logTag);
    notifyListeners(); // Notify that state changed
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