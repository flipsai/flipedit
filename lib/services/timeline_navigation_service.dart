import 'package:flipedit/models/clip.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;

typedef GetClips = List<ClipModel> Function();
typedef GetIsPlaying = bool Function();

class TimelineNavigationService extends ChangeNotifier {
  final String _logTag = 'TimelineNavigationService';

  final GetClips _getClips;
  final GetIsPlaying _getIsPlaying;

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    final clampedValue = value.clamp(0.1, 5.0);
    if (zoomNotifier.value == clampedValue) return;
    zoomNotifier.value = clampedValue;
    logger.logDebug('Zoom updated to: $clampedValue', _logTag);
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFramesValue = totalFramesNotifier.value;
    final int maxAllowedFrame =
        totalFramesValue > 0
            ? totalFramesValue - 1
            : defaultEmptyDurationFrames;
    final clampedValue = value.clamp(0, maxAllowedFrame);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);
  int get totalFrames => totalFramesNotifier.value;

  final ValueNotifier<int> timelineEndNotifier = ValueNotifier<int>(0);
  int get timelineEnd => timelineEndNotifier.value;

  final ValueNotifier<bool> isPlayheadLockedNotifier = ValueNotifier<bool>(
    false,
  );
  bool get isPlayheadLocked => isPlayheadLockedNotifier.value;

  final ValueNotifier<int?> scrollToFrameRequestNotifier = ValueNotifier<int?>(
    null,
  );

  static const int DEFAULT_EMPTY_DURATION_MS = 600000; // 10 minutes
  final int defaultEmptyDurationFrames = ClipModel.msToFrames(
    DEFAULT_EMPTY_DURATION_MS,
  );

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
    _scrollListener = _checkAndTriggerScroll;

    // Add listeners
    isPlayheadLockedNotifier.addListener(_scrollListener);
    currentFrameNotifier.addListener(_scrollListener);
  }

  int _calculateTotalFrames() {
    final clips = _getClips();
    if (clips.isEmpty) {
      return 0;
    }
    final maxEndTimeMs = clips.fold<int>(0, (max, clip) {
      final endTime = clip.endTimeOnTrackMs;
      return endTime > max ? endTime : max;
    });

    return ClipModel.msToFrames(maxEndTimeMs);
  }

  void recalculateAndUpdateTotalFrames() {
    if (_isDisposed) return;

    final newTotalFrames = _calculateTotalFrames();
    bool changed = false;

    if (totalFramesNotifier.value != newTotalFrames) {
      totalFramesNotifier.value = newTotalFrames;
      logger.logInfo('Total frames updated to: $newTotalFrames', _logTag);
      changed = true;
    }

    final newTimelineEnd =
        newTotalFrames > 0 ? newTotalFrames : defaultEmptyDurationFrames;
    if (timelineEndNotifier.value != newTimelineEnd) {
      timelineEndNotifier.value = newTimelineEnd;
      logger.logInfo(
        'Timeline end updated to: $newTimelineEnd frames',
        _logTag,
      );
      changed = true;
    }

    final current = currentFrame; // Use getter
    final maxAllowedFrame =
        newTotalFrames > 0 ? newTotalFrames - 1 : defaultEmptyDurationFrames;
    if (current > maxAllowedFrame) {
      currentFrame = maxAllowedFrame; // Use setter for clamping
      logger.logDebug(
        'Clamped current frame to $currentFrame after total frames update',
        _logTag,
      );
    }
  }

  void _checkAndTriggerScroll() {
    if (_isDisposed) return;

    final bool isPlaying = _getIsPlaying();
    final bool isLocked = isPlayheadLockedNotifier.value;
    final int frame = currentFrameNotifier.value;

    if (isPlaying && isLocked && frame % 20 == 0) {
      scrollToFrameRequestNotifier.value = frame;
    }
  }

  void togglePlayheadLock() {
    isPlayheadLockedNotifier.value = !isPlayheadLockedNotifier.value;
    logger.logInfo(
      '🔒 Playhead Lock toggled: ${isPlayheadLockedNotifier.value}',
      _logTag,
    );
    _checkAndTriggerScroll();
  }

  int getCurrentFrameValue() => currentFrameNotifier.value;
  void setCurrentFrameValue(int frame) => currentFrame = frame;
  int getTotalFramesValue() => totalFramesNotifier.value;
  int getDefaultEmptyDurationFramesValue() => defaultEmptyDurationFrames;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    logger.logInfo('Disposing TimelineNavigationService', _logTag);

    isPlayheadLockedNotifier.removeListener(_scrollListener);
    currentFrameNotifier.removeListener(_scrollListener);

    scrollToFrameRequestNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    timelineEndNotifier.dispose();
    isPlayheadLockedNotifier.dispose();

    super.dispose();
  }
}
