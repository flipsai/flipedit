import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/optimized_playback_service.dart';
import 'package:flipedit/services/timeline_navigation_service.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

class TimelineNavigationViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineNavigationViewModel';

  final ValueNotifier<List<ClipModel>> _clipsNotifier;
  late final TimelineNavigationService _navigationService;
  late final OptimizedPlaybackService _playbackService;
  late final VideoPlayerService _videoPlayerService;

  VoidCallback? _clipsListener;
  VoidCallback? _videoPositionListener;
  VoidCallback? _videoPlayingListener;

  TimelineNavigationViewModel({
    required List<ClipModel> Function() getClips,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
  }) : _clipsNotifier = clipsNotifier {
    // Store the injected notifier
    logger.logInfo('Initializing TimelineNavigationViewModel', _logTag);

    // Get the VideoPlayerService from dependency injection
    _videoPlayerService = di<VideoPlayerService>();

    // Instantiate services and wire dependencies
    _navigationService = TimelineNavigationService(
      getClips: getClips,
      getIsPlaying: () => isPlaying,
    );

    _playbackService = OptimizedPlaybackService(
      getCurrentFrame: () => _videoPlayerService.currentFrame, // Get from Rust instead
      setCurrentFrame: (frame) {
        // Don't set directly - Rust is source of truth
        // Only set if we're manually seeking
      },
      getTotalFrames: () => _videoPlayerService.getTotalFrames(),
      getDefaultEmptyDurationFrames: _navigationService.getDefaultEmptyDurationFramesValue,
    );

    // Set up listeners for video player service updates
    _videoPositionListener = () {
      // Update navigation service when Rust reports position changes
      final rustFrame = _videoPlayerService.currentFrame;
      if (rustFrame != _navigationService.currentFrame) {
        _navigationService.setCurrentFrameValue(rustFrame);
      }
    };
    
    _videoPlayingListener = () {
      // Sync playing state from Rust
      final rustIsPlaying = _videoPlayerService.isPlaying;
      if (rustIsPlaying != _playbackService.isPlaying) {
        _playbackService.isPlayingNotifier.value = rustIsPlaying;
      }
    };

    _videoPlayerService.currentFrameNotifier.addListener(_videoPositionListener!);
    _videoPlayerService.isPlayingNotifier.addListener(_videoPlayingListener!);

    _navigationService.zoomNotifier.addListener(notifyListeners);
    _navigationService.currentFrameNotifier.addListener(notifyListeners);
    _navigationService.totalFramesNotifier.addListener(notifyListeners);
    _navigationService.timelineEndNotifier.addListener(notifyListeners);
    _navigationService.isPlayheadLockedNotifier.addListener(notifyListeners);
    _playbackService.isPlayingNotifier.addListener(notifyListeners);

    _clipsListener = () {
      recalculateTotalFrames();
    };
    _clipsNotifier.addListener(_clipsListener!);
  }

  ValueNotifier<double> get zoomNotifier => _navigationService.zoomNotifier;
  ValueNotifier<int> get currentFrameNotifier =>
      _navigationService.currentFrameNotifier;
  ValueNotifier<int> get totalFramesNotifier =>
      _navigationService.totalFramesNotifier;
  ValueNotifier<int> get timelineEndNotifier =>
      _navigationService.timelineEndNotifier;
  ValueNotifier<bool> get isPlayingNotifier =>
      _playbackService.isPlayingNotifier;
  ValueNotifier<bool> get isPlayheadLockedNotifier =>
      _navigationService.isPlayheadLockedNotifier;

  double get zoom => _navigationService.zoom;
  set zoom(double value) {
    if (_navigationService.zoom != value) {
      _navigationService.zoom = value;
    }
  }

  int get currentFrame => _navigationService.currentFrame;
  set currentFrame(int value) {
    // When setting frame manually (e.g., from timeline interaction),
    // seek through the video player service which will update Rust
    if (_navigationService.currentFrame != value) {
      _navigationService.currentFrame = value;
      // Trigger seek in Rust
      _videoPlayerService.seekToFrame(value);
    }
  }

  int get totalFrames => _videoPlayerService.getTotalFrames();
  int get timelineEnd => _navigationService.timelineEnd;
  bool get isPlaying => _videoPlayerService.isPlaying;
  bool get isPlayheadLocked => _navigationService.isPlayheadLocked;

  // --- Playback Control Methods ---

  /// Starts playback from the current frame position.
  Future<void> startPlayback() async {
    if (isPlaying) return;
    
    // Start playback through the video player instead of internal service
    if (_videoPlayerService.activeVideoPlayer != null) {
      try {
        await _videoPlayerService.activeVideoPlayer!.play();
        logger.logDebug("Started playback through Rust video player", _logTag);
      } catch (e) {
        logger.logError(_logTag, "Error starting playback: $e");
      }
    }
    
    // Update internal state
    await _playbackService.startPlayback();
    _navigationService.recalculateAndUpdateTotalFrames();
  }

  /// Stops playback.
  void stopPlayback() {
    if (!isPlaying) return;
    
    // Stop playback through the video player
    if (_videoPlayerService.activeVideoPlayer != null) {
      try {
        _videoPlayerService.activeVideoPlayer!.pause();
        logger.logDebug("Stopped playback through Rust video player", _logTag);
      } catch (e) {
        logger.logError(_logTag, "Error stopping playback: $e");
      }
    }
    
    // Update internal state
    _playbackService.stopPlayback();
    _navigationService.recalculateAndUpdateTotalFrames();
  }

  /// Toggles the playback state.
  void togglePlayPause() {
    if (isPlaying) {
      stopPlayback();
    } else {
      startPlayback();
    }
  }

  /// Toggles the playhead lock state.
  void togglePlayheadLock() {
    _navigationService.togglePlayheadLock();
  }

  void recalculateTotalFrames() {
    _navigationService.recalculateAndUpdateTotalFrames();
  }

  // --- Expose Navigation Service ---
  TimelineNavigationService get navigationService => _navigationService;

  // --- Expose Playback Service for Player Integration ---
  OptimizedPlaybackService get playbackService => _playbackService;

  @override
  void dispose() {
    logger.logInfo('Disposing TimelineNavigationViewModel', _logTag);
    
    // Remove video player service listeners
    if (_videoPositionListener != null) {
      _videoPlayerService.currentFrameNotifier.removeListener(_videoPositionListener!);
    }
    if (_videoPlayingListener != null) {
      _videoPlayerService.isPlayingNotifier.removeListener(_videoPlayingListener!);
    }
    
    // Remove listeners added in constructor
    _navigationService.zoomNotifier.removeListener(notifyListeners);
    _navigationService.currentFrameNotifier.removeListener(notifyListeners);
    _navigationService.totalFramesNotifier.removeListener(notifyListeners);
    _navigationService.timelineEndNotifier.removeListener(notifyListeners);
    _navigationService.isPlayheadLockedNotifier.removeListener(notifyListeners);
    _playbackService.isPlayingNotifier.removeListener(notifyListeners);

    // Remove the listener added for clipsNotifier
    if (_clipsListener != null) {
      _clipsNotifier.removeListener(_clipsListener!);
    }

    // Dispose owned services
    _navigationService.dispose();
    _playbackService.dispose();
    super.dispose();
  }
}
