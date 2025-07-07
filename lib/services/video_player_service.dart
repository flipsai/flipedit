import 'package:flutter/widgets.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:async';
import 'dart:math';

class VideoPlayerService extends ChangeNotifier {
  String? _currentVideoPath;
  String? _errorMessage;
  dynamic _activePlayer; // Can be VideoPlayer or GesTimelinePlayer
  Timer? _positionPollingTimer;
  StreamSubscription<(double, BigInt)>? _positionStreamSubscription;
  
  final String _logTag = 'VideoPlayerService';

  // ValueNotifier for reactive UI updates - this is used for state coordination
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  
  // Position tracking - Rust is the source of truth
  final ValueNotifier<double> positionSecondsNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  
  // Batch update system to reduce widget rebuilds
  Timer? _batchUpdateTimer;
  bool _hasPendingUpdates = false;
  
  // Track when a video player is active for reactive UI updates
  final ValueNotifier<bool> hasActiveVideoNotifier = ValueNotifier<bool>(false);

  // Getters
  bool get isPlaying => isPlayingNotifier.value;
  String? get currentVideoPath => _currentVideoPath;
  String? get errorMessage => _errorMessage;
  dynamic get activePlayer => _activePlayer;
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
    _activePlayer = videoPlayer;
    hasActiveVideoNotifier.value = true;
    logDebug("Active video player registered", _logTag);
    
    // Set up position stream for real-time updates
    _setupPositionStream();
  }

  // Register an active timeline player instance for seeking
  void registerTimelinePlayer(GesTimelinePlayer timelinePlayer) {
    _activePlayer = timelinePlayer;
    hasActiveVideoNotifier.value = true;
    logDebug("Active timeline player registered", _logTag);
    
    // Set up position stream for real-time updates
    _setupPositionStream();
  }

  // Unregister the active video player
  void unregisterVideoPlayer() {
    _unregisterPlayer();
  }

  // Unregister the active timeline player
  void unregisterTimelinePlayer() {
    _unregisterPlayer();
  }

  void _unregisterPlayer() {
    // Stop position updates FIRST to prevent race conditions
    _stopPositionUpdates();
    
    _activePlayer = null;
    
    // Defer ValueNotifier update to prevent widget tree lock during disposal
    WidgetsBinding.instance.addPostFrameCallback((_) {
      hasActiveVideoNotifier.value = false;
    });
    
    logDebug("Active player unregistered", _logTag);
  }

  // Set up position stream for real-time updates from GStreamer timer
  void _setupPositionStream() {
    _stopPositionUpdates(); // Stop any existing stream
    
    if (_activePlayer == null) {
      logDebug("No active player for position stream setup", _logTag);
      return;
    }
    
    logDebug("Setting up real-time position stream", _logTag);
    
    try {
      if (_activePlayer is GesTimelinePlayer) {
        // For GES timeline players, we need to manually update position and poll
        logDebug("Setting up position polling for GES timeline player", _logTag);
        _positionPollingTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) { // Reduced frequency to 60fps
          if (_activePlayer == null) {
            timer.cancel();
            return;
          }
          
          try {
            // Always call update_position to sync with GStreamer pipeline (needed for pause state too)
            _activePlayer!.updatePosition();
            
            // Get the updated position
            final positionMs = _activePlayer!.getPositionMs();
            final positionSeconds = positionMs / 1000.0;
            final frameNumber = (positionSeconds * 30).round(); // Assuming 30 FPS
            
            // Update position notifiers with batch system to reduce rebuilds
            _scheduleBatchUpdate(() {
              positionSecondsNotifier.value = positionSeconds;
              currentFrameNotifier.value = frameNumber;
            });
          } catch (e) {
            logError(_logTag, "Position polling error: $e");
          }
        });
      } else {
        // For regular video players, use the stream-based approach
        final positionStream = _activePlayer!.setupPositionStream();
        _positionStreamSubscription = positionStream.listen(
          (positionData) {
            final (positionSeconds, frameNumber) = positionData;
            
            // Update position notifiers with batch system to reduce rebuilds
            _scheduleBatchUpdate(() {
              positionSecondsNotifier.value = positionSeconds;
              currentFrameNotifier.value = frameNumber.toInt();
            });
          },
          onError: (error) {
            logError(_logTag, "Position stream error: $error");
          },
          onDone: () {
            logDebug("Position stream completed", _logTag);
          },
        );
      }
      
      logDebug("Position stream setup completed", _logTag);
    } catch (e) {
      logError(_logTag, "Failed to setup position stream: $e");
    }
  }

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

  // Seek to frame position
  Future<void> seekToFrame(int frameNumber) async {
    if (_activePlayer == null) {
      logDebug("No active player for seeking", _logTag);
      return;
    }

    try {
      logDebug("Seeking to frame: $frameNumber", _logTag);
      
      if (_activePlayer is VideoPlayer) {
        await _activePlayer!.seekToFrame(frameNumber: BigInt.from(frameNumber));
      } else if (_activePlayer is GesTimelinePlayer) {
        // Convert frame to milliseconds (assuming 30fps)
        final positionMs = (frameNumber * 1000 / 30).round();
        await _activePlayer!.seekToPosition(positionMs: positionMs);
      }
      
      logDebug("Seek completed to frame: $frameNumber", _logTag);
    } catch (e) {
      logError(_logTag, "Error seeking to frame $frameNumber: $e");
    }
  }

  // Seek to time position with pause/resume control
  Future<void> seekToTime(double seconds, {bool wasPlayingBefore = false}) async {
    if (_activePlayer == null) {
      logDebug("No active player for seeking", _logTag);
      return;
    }

    try {
      logDebug("Seeking to time: ${seconds}s (wasPlayingBefore: $wasPlayingBefore)", _logTag);
      
      if (_activePlayer is VideoPlayer) {
        final actualPosition = await _activePlayer!.seekAndPauseControl(
          seconds: seconds,
          wasPlayingBefore: wasPlayingBefore,
        );
        logDebug("Seek completed to actual position: ${actualPosition}s", _logTag);
      } else if (_activePlayer is GesTimelinePlayer) {
        final positionMs = (seconds * 1000).round();
        await _activePlayer!.seekToPosition(positionMs: positionMs);
        logDebug("Seek completed to position: ${seconds}s", _logTag);
      }
    } catch (e) {
      logError(_logTag, "Error seeking to time $seconds: $e");
    }
  }

  // Extract frame at position for preview
  Future<void> previewFrameAtTime(double seconds) async {
    if (_activePlayer == null || _activePlayer is! VideoPlayer) {
      logDebug("No active video player for frame preview", _logTag);
      return;
    }

    try {
      await _activePlayer!.extractFrameAtPosition(seconds: seconds);
    } catch (e) {
      logError(_logTag, "Error extracting frame at $seconds: $e");
    }
  }

  // Get video information
  double getFrameRate() {
    if (_activePlayer == null) return 30.0; // Default frame rate
    try {
      if (_activePlayer is VideoPlayer) {
        return _activePlayer!.getFrameRate();
      }
      return 30.0; // Default for timeline player
    } catch (e) {
      logError(_logTag, "Error getting frame rate: $e");
      return 30.0;
    }
  }

  int getTotalFrames() {
    if (_activePlayer == null) return 0;
    try {
      if (_activePlayer is VideoPlayer) {
        return _activePlayer!.getTotalFrames().toInt();
      } else if (_activePlayer is GesTimelinePlayer) {
        final durationMs = _activePlayer!.getDurationMs();
        logInfo(_logTag, "GES Timeline Player duration: ${durationMs}ms");
        if (durationMs != null && durationMs > 0) {
          // Convert duration to frames (assuming 30 FPS)
          final totalFrames = (durationMs / 1000.0 * 30.0).round();
          logInfo(_logTag, "Converted to frames: $totalFrames frames (${totalFrames / 30.0} seconds)");
          return totalFrames;
        }
        // Fallback: if no duration available, try to get it from project timeline
        logInfo(_logTag, "No duration from GES player, falling back to timeline calculation");
        return _calculateTimelineFrames();
      }
      return 0;
    } catch (e) {
      logError(_logTag, "Error getting total frames: $e");
      return 0;
    }
  }

  int _calculateTimelineFrames() {
    try {
      // Try to get timeline duration from dependency injection
      final projectDatabaseService = di<ProjectDatabaseService>();
      final tracks = projectDatabaseService.tracksNotifier.value;
      
      // Simple estimation: find maximum clip end time across all tracks
      // This is not perfect but provides a reasonable estimate
      int maxEndTimeMs = 0;
      for (final track in tracks) {
        // We can't easily access async clip data here, so use a heuristic
        // If there are tracks, assume at least 10 seconds of content per track
                 if (track.name.isNotEmpty) {
           maxEndTimeMs = max(maxEndTimeMs + 10000, 30000); // At least 30 seconds if tracks exist
         }
      }
      
      if (maxEndTimeMs > 0) {
        // Convert to frames (30 FPS)
        return (maxEndTimeMs / 1000.0 * 30.0).round();
      }
      
      // Default fallback: 30 seconds
      return 900; // 30 seconds at 30 FPS
    } catch (e) {
      logError(_logTag, "Error calculating timeline frames: $e");
      return 900; // Default fallback
    }
  }

  double getDuration() {
    if (_activePlayer == null) return 0.0;
    try {
      if (_activePlayer is VideoPlayer) {
        return _activePlayer!.getDurationSeconds();
      } else if (_activePlayer is GesTimelinePlayer) {
        final durationMs = _activePlayer!.getDurationMs();
        return durationMs != null ? durationMs / 1000.0 : 0.0;
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
    _activePlayer = null;
    _stopPositionUpdates();
    isPlayingNotifier.value = false;
    positionSecondsNotifier.value = 0.0;
    currentFrameNotifier.value = 0;
    logDebug("Service state cleared", _logTag);
    notifyListeners();
  }

  // Batch update system to reduce widget rebuild frequency
  void _scheduleBatchUpdate(VoidCallback update) {
    if (!_hasPendingUpdates) {
      _hasPendingUpdates = true;
      // Faster updates when playing for smooth video, slower when paused
      final isCurrentlyPlaying = _activePlayer?.isPlaying() ?? false;
      final delay = isCurrentlyPlaying 
          ? const Duration(milliseconds: 8)  // ~120fps max when playing for smooth video
          : const Duration(milliseconds: 32); // ~30fps when paused
          
      _batchUpdateTimer = Timer(delay, () {
        if (_hasPendingUpdates) {
          update();
          _hasPendingUpdates = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _stopPositionUpdates();
    _batchUpdateTimer?.cancel();
    isPlayingNotifier.dispose();
    positionSecondsNotifier.dispose();
    currentFrameNotifier.dispose();
    hasActiveVideoNotifier.dispose();
    super.dispose();
  }
} 