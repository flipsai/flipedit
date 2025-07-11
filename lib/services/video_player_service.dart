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
  StreamSubscription<int>? _seekCompletionStreamSubscription;
  // Timer to drive smooth UI updates between Rust position callbacks
  Timer? _displayTimer;

  // Store last position received from Rust to allow interpolation
  double _lastRustPositionSeconds = 0.0;
  DateTime _lastRustPositionTimestamp = DateTime.now();
  
  // Track whether a seek operation is currently in progress to pause position polling
  bool _isSeeking = false;
  
  final String _logTag = 'VideoPlayerService';

  // ValueNotifier for reactive UI updates - this is used for state coordination
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  
  // Position tracking - Rust is the source of truth
  final ValueNotifier<double> positionSecondsNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> positionMsNotifier = ValueNotifier<double>(0.0);
  
  double _frameRate = 30.0; // Default fallback
  
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
  double get positionMs => positionMsNotifier.value;

  // Set frame rate for accurate frame calculations
  void setFrameRate(double frameRate) {
    _frameRate = frameRate;
    logDebug("Frame rate set to: $_frameRate fps", _logTag);
  }

  // Set the current video path (for coordination)
  void setCurrentVideoPath(String videoPath) {
    if (_currentVideoPath != videoPath) {
      _currentVideoPath = videoPath;
      logDebug("Current video path set to: $videoPath", _logTag);
      notifyListeners();
    }
  }

  // Register an active timeline player instance for seeking
  void registerTimelinePlayer(GesTimelinePlayer timelinePlayer) {
    _activePlayer = timelinePlayer;
    hasActiveVideoNotifier.value = true;
    logDebug("Active timeline player registered", _logTag);
    
    // Set up position stream for real-time updates
    _setupPositionStream();
    
    // Set up seek completion stream for proper playhead handling
    _setupSeekCompletionStream();
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
        // For GES timeline players, use timer-based polling according to GES guide
        // GES guide recommends 40-100ms intervals, we'll use 50ms (20fps) for smooth playhead updates
        logDebug("Setting up position polling for GES timeline player (50ms intervals per GES guide)", _logTag);
        _positionPollingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
          if (_isSeeking) return;
          if (_activePlayer == null) {
            timer.cancel();
            return;
          }

          try {
            final gesPlayer = _activePlayer as GesTimelinePlayer;
            
            // Only update position if actively playing (optimization from GES guide)
            if (!gesPlayer.isActivelyPlaying()) {
              // If not actively playing, still update occasionally to catch state changes
              return;
            }
            
            // Call updatePosition() as recommended by GES guide
            gesPlayer.updatePosition();
            
            // Use the new getCurrentPositionMs() method for better accuracy
            final positionMsBigInt = gesPlayer.getCurrentPositionMs();
            final positionMs = positionMsBigInt.toDouble();
            final positionSeconds = positionMs / 1000.0;
            // Get frame number directly from Rust instead of calculating
            final frameNumber = gesPlayer.getCurrentFrameNumber().toInt();

            // Save as base for interpolation
            _lastRustPositionSeconds = positionSeconds;
            _lastRustPositionTimestamp = DateTime.now();

            _ensureDisplayTimerRunning();

            _scheduleBatchUpdate(() {
              positionSecondsNotifier.value = positionSeconds;
              currentFrameNotifier.value = frameNumber;
              positionMsNotifier.value = positionMs;
            });
            
            // Debug log position updates occasionally
            if (positionMs % 1000 < 50) { // Log roughly every second
              logDebug("📍 GES Position: ${positionSeconds.toStringAsFixed(2)}s", _logTag);
            }
          } catch (e) {
            logError(_logTag, "Position polling error: $e");
          }
        });
      }
      
      logDebug("Position stream setup completed", _logTag);

      // Start smooth display timer whenever a position stream is active
      _startDisplayTimer();
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
    _displayTimer?.cancel();
    _displayTimer = null;
    _isSeeking = false;
    _seekCompletionStreamSubscription?.cancel();
    _seekCompletionStreamSubscription = null;
    logDebug("Stopped position updates", _logTag);
  }

  // Set up seek completion stream for proper playhead handling
  void _setupSeekCompletionStream() {
    if (_activePlayer == null || _activePlayer is! GesTimelinePlayer) {
      return;
    }
    
    try {
      final seekCompletionStream = _activePlayer!.setupSeekCompletionStream();
      _seekCompletionStreamSubscription = seekCompletionStream.listen(
        (positionMs) {
          logDebug("Seek completion: ${positionMs}ms", _logTag);

          // Seek is finished – resume position polling
          _isSeeking = false;
          // Force position update when seek completes
          final positionSeconds = positionMs / 1000.0;
          // Get frame number directly from Rust instead of calculating
          final frameNumber = (_activePlayer as GesTimelinePlayer).getCurrentFrameNumber().toInt();
          
          _scheduleBatchUpdate(() {
            positionSecondsNotifier.value = positionSeconds;
            currentFrameNotifier.value = frameNumber;
            positionMsNotifier.value = positionMs.toDouble();
            // Notify UI components that seek is complete
            seekCompletionNotifier.value = frameNumber;
          });
        },
        onError: (error) {
          logError(_logTag, "Seek completion stream error: $error");
        },
      );
      
      logDebug("Seek completion stream setup completed", _logTag);
    } catch (e) {
      logError(_logTag, "Failed to setup seek completion stream: $e");
    }
  }

  // Set playing state (called by video widgets to coordinate state)
  void setPlayingState(bool playing) {
    if (isPlayingNotifier.value != playing) {
      isPlayingNotifier.value = playing;
      logDebug("Playing state set to: $playing", _logTag);
      // Manage display timer
      if (playing) {
        _startDisplayTimer();
      } else {
        _displayTimer?.cancel();
      }
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

      // Pause position polling until seek completes
      _isSeeking = true;
      
        final positionMs = (frameNumber * 1000 / 30).round();
        await _activePlayer!.seekToPosition(positionMs: positionMs);
      
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

      // Pause position polling until seek completes
      _isSeeking = true;
      
      
        final positionMs = (seconds * 1000).round();
        await _activePlayer!.seekToPosition(positionMs: positionMs);
        logDebug("Seek completed to position: ${seconds}s", _logTag);
      
    } catch (e) {
      logError(_logTag, "Error seeking to time $seconds: $e");
    }
  }

  // Extract frame at position for preview
  Future<void> previewFrameAtTime(double seconds) async {
    if (_activePlayer == null) {
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
      return 30.0; // Default for timeline player
    } catch (e) {
      logError(_logTag, "Error getting frame rate: $e");
      return 30.0;
    }
  }

  int getTotalFrames() {
    if (_activePlayer == null) return 0;
    try {
        final durationMs = _activePlayer!.getDurationMs();
        logInfo(_logTag, "GES Timeline Player duration: ${durationMs}ms");
        if (durationMs != null && durationMs > 0) {
          // Convert duration to frames using actual frame rate
          final totalFrames = (durationMs / 1000.0 * _frameRate).round();
          logInfo(_logTag, "Converted to frames: $totalFrames frames (${totalFrames / _frameRate} seconds)");
          return totalFrames;
        }
        // Fallback: if no duration available, try to get it from project timeline
        logInfo(_logTag, "No duration from GES player, falling back to timeline calculation");
        return _calculateTimelineFrames();
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
        // Convert to frames using actual frame rate
        return (maxEndTimeMs / 1000.0 * _frameRate).round();
      }
      
      // Default fallback: 30 seconds
      return (30.0 * _frameRate).round();
    } catch (e) {
      logError(_logTag, "Error calculating timeline frames: $e");
      return (30.0 * _frameRate).round(); // Default fallback
    }
  }

  double getDuration() {
    if (_activePlayer == null) return 0.0;
    try {
      final durationMs = _activePlayer!.getDurationMs();
      return durationMs != null ? durationMs / 1000.0 : 0.0;
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
    _isSeeking = false;
    _stopPositionUpdates();
    isPlayingNotifier.value = false;
    positionSecondsNotifier.value = 0.0;
    currentFrameNotifier.value = 0;
    logDebug("Service state cleared", _logTag);
    notifyListeners();
  }

  // Seek completion notifier for UI components
  final ValueNotifier<int> seekCompletionNotifier = ValueNotifier<int>(-1);
  
  // Batch update system to reduce widget rebuild frequency
  void _scheduleBatchUpdate(VoidCallback update) {
    if (!_hasPendingUpdates) {
      _hasPendingUpdates = true;
      // Faster updates when playing for smooth video, slower when paused
      final isCurrentlyPlaying = _activePlayer?.isPlaying() ?? false;
      final delay = isCurrentlyPlaying 
          ? const Duration(milliseconds: 16)  // 60 fps when playing for smooth video
          : const Duration(milliseconds: 32); // 30 fps when paused
          
      _batchUpdateTimer = Timer(delay, () {
        if (_hasPendingUpdates) {
          update();
          _hasPendingUpdates = false;
        }
      });
    }
  }

  // Smooth UI timer
  void _startDisplayTimer() {
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isPlayingNotifier.value || _isSeeking) return;

      final elapsed = DateTime.now().difference(_lastRustPositionTimestamp).inMicroseconds / 1e6;
      if (elapsed <= 0) return;

      final predicted = _lastRustPositionSeconds + elapsed;
      final predictedFrame = (predicted * 30).round();

      _scheduleBatchUpdate(() {
        positionSecondsNotifier.value = predicted;
        currentFrameNotifier.value = predictedFrame;
      });
    });
  }

  void _ensureDisplayTimerRunning() {
    if (_displayTimer == null && isPlayingNotifier.value && !_isSeeking) {
      _startDisplayTimer();
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
    seekCompletionNotifier.dispose();
    super.dispose();
  }
} 