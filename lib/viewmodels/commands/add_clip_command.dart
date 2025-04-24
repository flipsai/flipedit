import '../timeline_viewmodel.dart';
import '../commands/timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// Command to add a clip to the timeline at a specific position.
class AddClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel clipData;
  final int trackId;
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;
  final double? localPositionX;
  final double? scrollOffsetX;

  static const _logTag = "AddClipCommand";

  AddClipCommand({
    required this.vm,
    required this.clipData,
    required this.trackId,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    this.localPositionX,
    this.scrollOffsetX,
  });

  @override
  Future<void> execute() async {
    int targetStartTimeMs;
    final logTag = _logTag;
    logger.logInfo(
      '[AddClipCommand] Executing: trackId=$trackId, clip=${clipData.name}, type=${clipData.type}',
      logTag,
    );
    final tracks = vm.projectDatabaseService.tracksNotifier.value;
    vm.currentTrackIds = tracks.map((t) => t.id).toList();
    if (!vm.currentTrackIds.contains(trackId)) {
      logger.logError(
        '[AddClipCommand] Track ID $trackId is not in current tracks list: ${vm.currentTrackIds}',
        logTag,
      );
      // Continue anyway
    }
    if (localPositionX != null && scrollOffsetX != null) {
      targetStartTimeMs = vm.calculateMsPositionFromPixels(
        localPositionX!,
        scrollOffsetX!,
        vm.zoom,
      );
      logger.logInfo(
        '[AddClipCommand] Calculated position: localX=$localPositionX, scrollX=$scrollOffsetX, targetMs=$targetStartTimeMs',
        logTag,
      );
    } else {
      targetStartTimeMs = ClipModel.framesToMs(vm.currentFrame);
      logger.logInfo(
        '[AddClipCommand] Using current frame position: frame=${vm.currentFrame}, targetMs=$targetStartTimeMs',
        logTag,
      );
    }
    // Call placeClipOnTrack directly as it contains the core logic
    final result = await vm.placeClipOnTrack(
      clipId: null, // Indicate new clip
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      startTimeOnTrackMs: targetStartTimeMs,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
    );
    // Assuming placeClipOnTrack returns bool for success
    logger.logInfo('[AddClipCommand] placeClipOnTrack result: $result', logTag);
  }

  @override
  Future<void> undo() async {
    // Undo not implemented yet
  }
}
