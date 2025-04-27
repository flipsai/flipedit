import 'dart:async';

import 'package:flipedit/models/clip.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For listEquals

// Function types for dependencies
typedef GetClips = List<ClipModel> Function();
typedef GetIsPlaying = bool Function();

class TimelineNavigationService extends ChangeNotifier {
  final String _logTag = 'TimelineNavigationService';

  // --- Dependencies ---
  final GetClips _getClips;
  final GetIsPlaying _getIsPlaying; // To check if playback service is active

  // --- State Notifiers ---
  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    final clampedValue = value.clamp(0.1, 5.0); // Ensure within bounds
    if (zoomNotifier.value == clampedValue) return;
    zoomNotifier.value = clampedValue;
    logger.logDebug('Zoom updated to: $clampedValue', _logTag);
    // ValueNotifier notifies its own listeners
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFramesValue = totalFramesNotifier.value; // Use cached total frames
    // Clamp to content duration or default empty duration
    final int maxAllowedFrame = totalFramesValue > 0 ? totalFramesValue - 1 : defaultEmptyDurationFrames;
    final clampedValue = value.clamp(0, maxAllowedFrame);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
    // logger.logVerbose('Current frame set to: $clampedValue', _logTag); // Can be verbose
    // ValueNotifier notifies its own listeners
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);
  int get totalFrames => totalFramesNotifier.value;

  // Represents the visual end of the timeline (max frame + 1 or default)
  final ValueNotifier<int> timelineEndNotifier = ValueNotifier<int>(0);
  int get timelineEnd => timelineEndNotifier.value;

  final ValueNotifier<bool> isPlayheadLockedNotifier = ValueNotifier<bool>(false);
  bool get isPlayheadLocked => isPlayheadLockedNotifier.value;

  /// Notifier that the View listens to for scroll requests.
  /// The value is the frame to scroll to. Set back to null after consumption?
  /// Or rely on view comparing old/new value. Let's rely on view.
  final ValueNotifier<int?> scrollToFrameRequestNotifier = ValueNotifier<int?>(null);

  // --- Constants ---
  static const int DEFAULT_EMPTY_DURATION_MS = 600000; // 10 minutes
  // Calculate default frames once
  // TODO: Ensure ClipModel uses the correct project FPS
  final int defaultEmptyDurationFrames = ClipModel.msToFrames(DEFAULT_EMPTY_DURATION_MS);


  // --- Removed Scroll Command Handler ---
  // Removed: void Function(int frame)? _scrollToFrameHandler;
  // Removed: void registerScrollToFrameHandler(void Function(int frame)? handler) { ... }

  // --- Internal Listeners ---
  // We need to store the listener functions to remove them later.
  late final VoidCallback _scrollListener;
  bool _isDisposed = false;

  TimelineNavigationService({
    required GetClips getClips,
    required GetIsPlaying getIsPlaying,
  }) : _getClips = getClips,
       _getIsPlaying = getIsPlaying {
    logger.logInfo('Initializing TimelineNavigationService', _logTag);
    _setupInternalListeners();
    // Initial calculation
    recalculateAndUpdateTotalFrames();
  }

  void _setupInternalListeners() {
     // Define the listener function once
    _scrollListener = _checkAndTriggerScroll;

    // Add listeners
    isPlayheadLockedNotifier.addListener(_scrollListener);
    currentFrameNotifier.addListener(_scrollListener);
    // We also need to react if the playback state changes *while* locked
    // This requires the PlaybackService to notify us, or we poll it.
    // Let's assume the ViewModel will call recalculate when playback starts/stops.
  }

  /// Recalculates the total duration/frames based on the current clips.
  int _calculateTotalFrames() {
    final clips = _getClips();
    if (clips.isEmpty) {
      return 0; // No clips, duration is 0 (timelineEnd will use default)
    }
    // Find the maximum end time among all clips
    final maxEndTimeMs = clips.fold<int>(0, (max, clip) {
        final endTime = clip.endTimeOnTrackMs;
        return endTime > max ? endTime : max;
    });

    // Convert max end time to frames
    // TODO: Ensure ClipModel uses the correct project FPS
    return ClipModel.msToFrames(maxEndTimeMs);
  }

  /// Public method to trigger recalculation, typically called when clips change.
  void recalculateAndUpdateTotalFrames() {
    if (_isDisposed) return;

    final newTotalFrames = _calculateTotalFrames();
    bool changed = false;

    if (totalFramesNotifier.value != newTotalFrames) {
      totalFramesNotifier.value = newTotalFrames;
      logger.logInfo('Total frames updated to: $newTotalFrames', _logTag);
      changed = true;
    }

    final newTimelineEnd = newTotalFrames > 0 ? newTotalFrames : defaultEmptyDurationFrames;
    if (timelineEndNotifier.value != newTimelineEnd) {
        timelineEndNotifier.value = newTimelineEnd;
        logger.logInfo('Timeline end updated to: $newTimelineEnd frames', _logTag);
        changed = true;
    }

     // Ensure current frame is still valid after totalFrames might have changed
    final current = currentFrame; // Use getter
    final maxAllowedFrame = newTotalFrames > 0 ? newTotalFrames - 1 : defaultEmptyDurationFrames;
    if (current > maxAllowedFrame) {
       currentFrame = maxAllowedFrame; // Use setter for clamping
       logger.logDebug('Clamped current frame to ${this.currentFrame} after total frames update', _logTag);
       // Setter already notifies if value changed
    }

    // if (changed) {
    //   notifyListeners(); // Notify if totalFrames or timelineEnd changed
    // }
  }

  /// Checks conditions and triggers scroll notification if necessary.
  void _checkAndTriggerScroll() {
    // if (_isDisposed || _scrollToFrameHandler == null) return; // Check notifier instead
    if (_isDisposed) return;

    final bool isPlaying = _getIsPlaying();
    final bool isLocked = isPlayheadLockedNotifier.value;
    final int frame = currentFrameNotifier.value;

    // Trigger scroll notification if playing, locked, and on a suitable interval
    if (isPlaying && isLocked && frame % 20 == 0) {
      // logger.logDebug('NavigationService requesting scroll to frame: $frame', _logTag);
      // _scrollToFrameHandler!(frame); // Old way
      scrollToFrameRequestNotifier.value = frame; // Update notifier
    }
  }

  /// Toggles the playhead lock state
  void togglePlayheadLock() {
    isPlayheadLockedNotifier.value = !isPlayheadLockedNotifier.value;
    logger.logInfo('🔒 Playhead Lock toggled: ${isPlayheadLockedNotifier.value}', _logTag);
    // ValueNotifier notifies its own listeners
     _checkAndTriggerScroll(); // Check immediately if scroll needed now
  }

  // --- Methods needed by PlaybackService ---
  // Provide direct accessors for PlaybackService dependencies
  int getCurrentFrameValue() => currentFrameNotifier.value;
  void setCurrentFrameValue(int frame) => currentFrame = frame; // Use setter
  int getTotalFramesValue() => totalFramesNotifier.value;
  int getDefaultEmptyDurationFramesValue() => defaultEmptyDurationFrames;


  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    logger.logInfo('Disposing TimelineNavigationService', _logTag);

    // Remove internal listeners using the stored function reference
    isPlayheadLockedNotifier.removeListener(_scrollListener);
    currentFrameNotifier.removeListener(_scrollListener);

    // Unregister handler to prevent calls after disposal - No longer needed
    // _scrollToFrameHandler = null;

    // Dispose ValueNotifiers
    scrollToFrameRequestNotifier.dispose(); // Dispose the new notifier
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    timelineEndNotifier.dispose();
    isPlayheadLockedNotifier.dispose();

    super.dispose();
  }
}