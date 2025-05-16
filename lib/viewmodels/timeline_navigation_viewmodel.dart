import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/optimized_playback_service.dart';
import 'package:flipedit/services/timeline_navigation_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class TimelineNavigationViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineNavigationViewModel';

  final ValueNotifier<List<ClipModel>> _clipsNotifier;
  late final TimelineNavigationService _navigationService;
  late final OptimizedPlaybackService _playbackService;

  VoidCallback? _clipsListener;

  TimelineNavigationViewModel({
    required List<ClipModel> Function() getClips,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
  }) : _clipsNotifier = clipsNotifier {
    // Store the injected notifier
    logger.logInfo('Initializing TimelineNavigationViewModel', _logTag);

    // Instantiate services and wire dependencies
    _navigationService = TimelineNavigationService(
      getClips: getClips,
      getIsPlaying: () => isPlaying,
    );

    _playbackService = OptimizedPlaybackService(
      getCurrentFrame: _navigationService.getCurrentFrameValue,
      setCurrentFrame: _navigationService.setCurrentFrameValue,
      getTotalFrames: _navigationService.getTotalFramesValue,
      getDefaultEmptyDurationFrames:
          _navigationService.getDefaultEmptyDurationFramesValue,
    );

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
    if (_navigationService.currentFrame != value) {
      _navigationService.currentFrame = value;
    }
  }

  int get totalFrames => _navigationService.totalFrames;
  int get timelineEnd => _navigationService.timelineEnd;
  bool get isPlaying => _playbackService.isPlaying;
  bool get isPlayheadLocked => _navigationService.isPlayheadLocked;

  // --- Playback Control Methods ---

  /// Starts playback from the current frame position.
  Future<void> startPlayback() async {
    if (isPlaying) return;
    await _playbackService.startPlayback();
    _navigationService.recalculateAndUpdateTotalFrames();
  }

  /// Stops playback.
  void stopPlayback() {
    if (!isPlaying) return;
    _playbackService.stopPlayback();
    _navigationService.recalculateAndUpdateTotalFrames();
  }

  /// Toggles the playback state.
  void togglePlayPause() {
    _playbackService.togglePlayPause();
    _navigationService.recalculateAndUpdateTotalFrames();
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
