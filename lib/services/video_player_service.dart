import 'package:flutter/foundation.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'dart:async';

class VideoPlayerService extends ChangeNotifier {
  String? _currentVideoPath;
  String? _errorMessage;
  VideoPlayer? _activeVideoPlayer; // Reference to the active video player
  Timer? _positionPollingTimer;
  
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
  VideoPlayer? get activeVideoPlayer => _activeVideoPlayer;
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

  // Register an active video player instance for seeking
  void registerVideoPlayer(VideoPlayer videoPlayer) {
    _activeVideoPlayer = videoPlayer;
    hasActiveVideoNotifier.value = true;
    logDebug("Active video player registered", _logTag);
    
    // Start position polling when player is registered
    _startPositionPolling();
  }

  // Unregister the active video player
  void unregisterVideoPlayer() {
    // _activeVideoPlayer = null;
    // hasActiveVideoNotifier.value = false;
    
    // Stop position polling when player is unregistered
    // _stopPositionPolling();
    
    logDebug("Active video player unregistered", _logTag);
  }

  // Start polling Rust for position updates
  void _startPositionPolling() {
    // _stopPositionPolling(); // Stop any existing timer
    
    // Start with adaptive polling - faster when playing, slower when paused
    // _scheduleNextPoll();
    
    logDebug("Started adaptive position polling from Rust", _logTag);
  }

  void _scheduleNextPoll() {
    if (_activeVideoPlayer == null) return;
    
    // Adaptive polling rate based on playing state
    final isCurrentlyPlaying = _activeVideoPlayer!.isPlaying();
    final pollInterval = isCurrentlyPlaying 
        ? const Duration(milliseconds: 50)  // 20fps when playing
        : const Duration(milliseconds: 100); // 10fps when paused
    
    _positionPollingTimer = Timer(pollInterval, () {
      if (_activeVideoPlayer == null) return;
      
      try {
        // Get position from Rust - this is the source of truth
        final positionData = _activeVideoPlayer!.getCurrentPositionAndFrame();
        final positionSeconds = positionData.$1;
        final frameNumber = positionData.$2;
        
        // Only update if values actually changed (reduce unnecessary rebuilds)
        bool hasChanges = false;
        
        if ((positionSecondsNotifier.value - positionSeconds).abs() > 0.01) {
          positionSecondsNotifier.value = positionSeconds;
          hasChanges = true;
        }
        
        final frameInt = frameNumber.toInt();
        if (currentFrameNotifier.value != frameInt) {
          currentFrameNotifier.value = frameInt;
          hasChanges = true;
        }
        
        // Update playing state from Rust as well
        final rustIsPlaying = _activeVideoPlayer!.isPlaying();
        if (isPlayingNotifier.value != rustIsPlaying) {
          isPlayingNotifier.value = rustIsPlaying;
          hasChanges = true;
        }
        
        // Schedule next poll
        _scheduleNextPoll();
        
      } catch (e) {
        logError(_logTag, "Error polling position from Rust: $e");
        // Retry after a longer delay on error
        Timer(const Duration(milliseconds: 200), _scheduleNextPoll);
      }
    });
  }

  // Stop position polling
  void _stopPositionPolling() {
    _positionPollingTimer?.cancel();
    _positionPollingTimer = null;
    logDebug("Stopped position polling", _logTag);
  }

  // Set playing state (called by video widgets to coordinate state)
  void setPlayingState(bool playing) {
    if (isPlayingNotifier.value != playing) {
      isPlayingNotifier.value = playing;
      logDebug("Playing state set to: $playing", _logTag);
      notifyListeners();
    }
  }

  // Seek to frame position
  Future<void> seekToFrame(int frameNumber) async {
    if (_activeVideoPlayer == null) {
      logDebug("No active video player for seeking", _logTag);
      return;
    }

    try {
      logDebug("Seeking to frame: $frameNumber", _logTag);
      await _activeVideoPlayer!.seekToFrame(frameNumber: BigInt.from(frameNumber));
      logDebug("Seek completed to frame: $frameNumber", _logTag);
    } catch (e) {
      logError(_logTag, "Error seeking to frame $frameNumber: $e");
    }
  }

  // Seek to time position with pause/resume control
  Future<void> seekToTime(double seconds, {bool wasPlayingBefore = false}) async {
    if (_activeVideoPlayer == null) {
      logDebug("No active video player for seeking", _logTag);
      return;
    }

    try {
      logDebug("Seeking to time: ${seconds}s (wasPlayingBefore: $wasPlayingBefore)", _logTag);
      final actualPosition = await _activeVideoPlayer!.seekAndPauseControl(
        seconds: seconds,
        wasPlayingBefore: wasPlayingBefore,
      );
      logDebug("Seek completed to actual position: ${actualPosition}s", _logTag);
    } catch (e) {
      logError(_logTag, "Error seeking to time $seconds: $e");
    }
  }

  // Extract frame at position for preview
  Future<void> previewFrameAtTime(double seconds) async {
    if (_activeVideoPlayer == null) {
      logDebug("No active video player for frame preview", _logTag);
      return;
    }

    try {
      await _activeVideoPlayer!.extractFrameAtPosition(seconds: seconds);
    } catch (e) {
      logError(_logTag, "Error extracting frame at $seconds: $e");
    }
  }

  // Get video information
  double getFrameRate() {
    if (_activeVideoPlayer == null) return 30.0; // Default frame rate
    try {
      return _activeVideoPlayer!.getFrameRate();
    } catch (e) {
      logError(_logTag, "Error getting frame rate: $e");
      return 30.0;
    }
  }

  int getTotalFrames() {
    if (_activeVideoPlayer == null) return 0;
    try {
      return _activeVideoPlayer!.getTotalFrames().toInt();
    } catch (e) {
      logError(_logTag, "Error getting total frames: $e");
      return 0;
    }
  }

  double getDuration() {
    if (_activeVideoPlayer == null) return 0.0;
    try {
      return _activeVideoPlayer!.getDurationSeconds();
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
    _activeVideoPlayer = null;
    _stopPositionPolling();
    isPlayingNotifier.value = false;
    positionSecondsNotifier.value = 0.0;
    currentFrameNotifier.value = 0;
    logDebug("Service state cleared", _logTag);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPositionPolling();
    isPlayingNotifier.dispose();
    positionSecondsNotifier.dispose();
    currentFrameNotifier.dispose();
    super.dispose();
  }
} 