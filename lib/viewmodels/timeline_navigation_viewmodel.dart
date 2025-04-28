import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/playback_service.dart';
import 'package:flipedit/services/timeline_navigation_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// ViewModel responsible for managing timeline navigation state (zoom, scroll, playhead)
/// and playback control. It delegates the core logic to the respective services.
class TimelineNavigationViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineNavigationViewModel';

  // --- Injected Services ---
  late final TimelineNavigationService _navigationService;
  late final PlaybackService _playbackService;

  // --- Constructor ---
  TimelineNavigationViewModel({
    required List<ClipModel> Function() getClips, // Function to get current clips
  }) {
    logger.logInfo('Initializing TimelineNavigationViewModel', _logTag);

    // Instantiate services and wire dependencies
    _navigationService = TimelineNavigationService(
      getClips: getClips,
      getIsPlaying: () => isPlaying, // Provide function using local getter
    );

    _playbackService = PlaybackService(
      getCurrentFrame: _navigationService.getCurrentFrameValue,
      setCurrentFrame: _navigationService.setCurrentFrameValue,
      getTotalFrames: _navigationService.getTotalFramesValue,
      getDefaultEmptyDurationFrames: _navigationService.getDefaultEmptyDurationFramesValue,
    );

    // Listen to changes in the underlying services and notify listeners of this ViewModel
    _navigationService.zoomNotifier.addListener(notifyListeners);
    _navigationService.currentFrameNotifier.addListener(notifyListeners);
    _navigationService.totalFramesNotifier.addListener(notifyListeners);
    _navigationService.timelineEndNotifier.addListener(notifyListeners);
    _navigationService.isPlayheadLockedNotifier.addListener(notifyListeners);
    _playbackService.isPlayingNotifier.addListener(notifyListeners);
  }

  // --- Delegated State Notifiers (Exposed for View Binding) ---
  ValueNotifier<double> get zoomNotifier => _navigationService.zoomNotifier;
  ValueNotifier<int> get currentFrameNotifier => _navigationService.currentFrameNotifier;
  ValueNotifier<int> get totalFramesNotifier => _navigationService.totalFramesNotifier;
  ValueNotifier<int> get timelineEndNotifier => _navigationService.timelineEndNotifier;
  ValueNotifier<bool> get isPlayingNotifier => _playbackService.isPlayingNotifier;
  ValueNotifier<bool> get isPlayheadLockedNotifier => _navigationService.isPlayheadLockedNotifier;

  // --- Delegated Getters/Setters (Direct access to service properties) ---
  double get zoom => _navigationService.zoom;
  set zoom(double value) {
    if (_navigationService.zoom != value) {
      _navigationService.zoom = value;
      // Listener on zoomNotifier will call notifyListeners
    }
  }

  int get currentFrame => _navigationService.currentFrame;
  set currentFrame(int value) {
    if (_navigationService.currentFrame != value) {
      _navigationService.currentFrame = value;
      // Listener on currentFrameNotifier will call notifyListeners
    }
  }

  int get totalFrames => _navigationService.totalFrames;
  int get timelineEnd => _navigationService.timelineEnd;
  bool get isPlaying => _playbackService.isPlaying;
  bool get isPlayheadLocked => _navigationService.isPlayheadLocked;

  // --- Playback Control Methods ---

  /// Starts playback from the current frame position.
  Future<void> startPlayback() async {
    if (isPlaying) return; // Already playing
    await _playbackService.startPlayback();
    _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
    // Listener on isPlayingNotifier will call notifyListeners
  }

  /// Stops playback.
  void stopPlayback() {
    if (!isPlaying) return; // Not playing
    _playbackService.stopPlayback();
    _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
     // Listener on isPlayingNotifier will call notifyListeners
  }

  /// Toggles the playback state.
  void togglePlayPause() {
    _playbackService.togglePlayPause();
    _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
     // Listener on isPlayingNotifier will call notifyListeners
  }

  /// Toggles the playhead lock state.
  void togglePlayheadLock() {
    _navigationService.togglePlayheadLock();
    // Listener on isPlayheadLockedNotifier will call notifyListeners
  }

   /// Forces recalculation of total frames in the navigation service.
   /// Typically called when clips change significantly.
   void recalculateTotalFrames() {
      _navigationService.recalculateAndUpdateTotalFrames();
   }

  // --- Expose Navigation Service ---
  // Expose navigation service for direct access if needed by Commands or specialized View logic
  // Use cautiously, prefer methods on this ViewModel.
  TimelineNavigationService get navigationService => _navigationService;

  // --- Dispose ---
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

    // Dispose owned services
    _navigationService.dispose();
    _playbackService.dispose();
    super.dispose();
  }
}