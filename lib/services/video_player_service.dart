import 'package:flutter/widgets.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/src/rust/v2/flutter_bridge/api.dart';
import 'dart:async';

class VideoPlayerService extends ChangeNotifier {
  String? _currentVideoPath;
  String? _errorMessage;
  VideoEditorV2? _activeVideoEditor; // Reference to the active video editor
  Timer? _positionPollingTimer;
  StreamSubscription<(double, BigInt)>? _positionStreamSubscription;
  
  final String _logTag = 'VideoPlayerService';

  // ValueNotifier for reactive UI updates - this is used for state coordination
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  
  // Position tracking - Rust is the source of truth
  final ValueNotifier<double> positionSecondsNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  
  
  // Track when a video player is active for reactive UI updates
  final ValueNotifier<bool> hasActiveVideoNotifier = ValueNotifier<bool>(false);

  // Getters
  bool get isPlaying => isPlayingNotifier.value;
  String? get currentVideoPath => _currentVideoPath;
  String? get errorMessage => _errorMessage;
  VideoEditorV2? get activeVideoEditor => _activeVideoEditor;
  double get positionSeconds => positionSecondsNotifier.value;
  int get currentFrame => currentFrameNotifier.value;

  // Set the current video path (for coordination)
  void setCurrentVideoPath(String videoPath) {
    if (_currentVideoPath != videoPath) {
      _currentVideoPath = videoPath;
      logDebug("Current video path set to: $videoPath", _logTag);
      notifyListeners();
    }
  }

  // Register an active video editor instance
  void registerVideoEditor(VideoEditorV2 videoEditor) {
    _activeVideoEditor = videoEditor;
    hasActiveVideoNotifier.value = true;
    logDebug("Active video editor registered", _logTag);
  }

  // Unregister the active video editor
  void unregisterVideoEditor() {
    _activeVideoEditor = null;
    
    // Defer ValueNotifier update to prevent widget tree lock during disposal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hasActiveVideoNotifier.value = false;
    });
    
    logDebug("Active video editor unregistered", _logTag);
  }

  // Note: VideoEditorV2 does not have position streams like the old VideoPlayer
  // Position tracking would need to be implemented differently if needed

  // Stop position updates
  void _stopPositionUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _positionPollingTimer?.cancel();
    _positionPollingTimer = null;
    logDebug("Stopped position updates", _logTag);
  }

  // Set playing state (called by video widgets to coordinate state)
  void setPlayingState(bool playing) {
    if (isPlayingNotifier.value != playing) {
      isPlayingNotifier.value = playing;
      logDebug("Playing state set to: $playing", _logTag);
      notifyListeners();
    }
  }

  // Note: VideoEditorV2 does not have seekToFrame method
  // Seeking would need to be implemented through timeline state management

  // Note: VideoEditorV2 does not have seek methods
  // Time seeking would need to be implemented through timeline state management

  // Note: VideoEditorV2 does not have frame extraction methods
  // Frame preview would need to be implemented differently

  // Get video information from VideoEditorV2
  double getFrameRate() {
    if (_activeVideoEditor == null) return 30.0; // Default frame rate
    try {
      final videoInfo = getVideoInfoV2(editor: _activeVideoEditor!);
      return videoInfo?.fps ?? 30.0;
    } catch (e) {
      logError(_logTag, "Error getting frame rate: $e");
      return 30.0;
    }
  }

  int getTotalFrames() {
    if (_activeVideoEditor == null) return 0;
    try {
      final videoInfo = getVideoInfoV2(editor: _activeVideoEditor!);
      if (videoInfo != null) {
        // Duration is in nanoseconds, convert to seconds, then multiply by fps
        final durationSeconds = videoInfo.duration.toDouble() / 1000000000;
        return (durationSeconds * videoInfo.fps).toInt();
      }
      return 0;
    } catch (e) {
      logError(_logTag, "Error getting total frames: $e");
      return 0;
    }
  }

  double getDuration() {
    if (_activeVideoEditor == null) return 0.0;
    try {
      final videoInfo = getVideoInfoV2(editor: _activeVideoEditor!);
      if (videoInfo != null) {
        // Duration is in nanoseconds, convert to seconds
        return videoInfo.duration.toDouble() / 1000000000;
      }
      return 0.0;
    } catch (e) {
      logError(_logTag, "Error getting duration: $e");
      return 0.0;
    }
  }

  // Set error message
  void setError(String? error) {
    if (_errorMessage != error) {
      _errorMessage = error;
      logDebug("Error state set to: $error", _logTag);
      notifyListeners();
    }
  }

  // Clear all state
  void clearState() {
    _currentVideoPath = null;
    _errorMessage = null;
    _activeVideoEditor = null;
    _stopPositionUpdates();
    isPlayingNotifier.value = false;
    positionSecondsNotifier.value = 0.0;
    currentFrameNotifier.value = 0;
    hasActiveVideoNotifier.value = false;
    logDebug("Service state cleared", _logTag);
    notifyListeners();
  }


  @override
  void dispose() {
    _stopPositionUpdates();
    isPlayingNotifier.dispose();
    positionSecondsNotifier.dispose();
    currentFrameNotifier.dispose();
    hasActiveVideoNotifier.dispose();
    super.dispose();
  }
} 