import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For firstWhereOrNull
import '../../services/timeline_logic_service.dart'; // Import the new service
import 'package:watch_it/watch_it.dart'; // Import for di

/// Command to resize a clip by adjusting its start or end time.
class ResizeClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int clipId;
  final String direction; // 'left' or 'right'
  // Add dependency on TimelineLogicService
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final int newBoundaryFrame; // The frame where the new edge will be

  // Store original state for undo
  ClipModel? _originalClipState;
  List<ClipModel>? _originalNeighborStates;

  static const _logTag = "ResizeClipCommand";

  ResizeClipCommand({
    required this.vm,
    required this.clipId,
    required this.direction,
    required this.newBoundaryFrame,
  }) : assert(direction == 'left' || direction == 'right',
            'Direction must be "left" or "right"');

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[ResizeClipCommand] Executing: clipId=$clipId, direction=$direction, newBoundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final clipToResize = vm.clips.firstWhereOrNull((c) => c.databaseId == clipId);

    if (clipToResize == null) {
      logger.logError('[ResizeClipCommand] Clip $clipId not found in ViewModel', _logTag);
      throw Exception('Clip $clipId not found for resizing');
    }

    // --- Store state for Undo ---
    _originalClipState = clipToResize.copyWith();

    // Calculate the *potential* new TRACK time range to find affected neighbors
    int potentialNewStartMs = clipToResize.startTimeOnTrackMs;
    // Use existing endTimeOnTrackMs for potential end
    int potentialNewEndMs = clipToResize.endTimeOnTrackMs;
    // final newBoundaryMs = ClipModel.framesToMs(newBoundaryFrame); // Removed redundant definition

    if (direction == 'left') {
      potentialNewStartMs = ClipModel.framesToMs(newBoundaryFrame); // Calculate here directly
      // potentialNewEndMs remains the same
    } else { // direction == 'right'
      // potentialNewStartMs remains the same
      potentialNewEndMs = ClipModel.framesToMs(newBoundaryFrame); // Calculate here directly
    }

    // Ensure track start is before track end
    if (potentialNewStartMs >= potentialNewEndMs) {
      logger.logWarning('[ResizeClipCommand] Resize would result in zero or negative track duration. Clamping.', _logTag);
      final minDurationMs = ClipModel.framesToMs(1);
      if (direction == 'left') {
        potentialNewStartMs = potentialNewEndMs - minDurationMs;
      } else {
        potentialNewEndMs = potentialNewStartMs + minDurationMs;
      }
    }


    _originalNeighborStates = _timelineLogicService.getOverlappingClips(
      vm.clips,
      clipToResize.trackId,
      potentialNewStartMs,
      potentialNewEndMs,
      clipId,
    ).map((c) => c.copyWith()).toList();

    // Also include neighbors affected by the *original* range if the resize shrinks the clip
    final originalEndTimeMs = clipToResize.endTimeOnTrackMs; // Use original track end time
    final oldNeighbors = _timelineLogicService.getOverlappingClips(
      vm.clips,
      clipToResize.trackId,
      clipToResize.startTimeOnTrackMs,
      originalEndTimeMs,
      clipId,
    ).map((c) => c.copyWith()).toList();
    for (final oldNeighbor in oldNeighbors) {
      if (!_originalNeighborStates!.any((n) => n.databaseId == oldNeighbor.databaseId)) {
        _originalNeighborStates!.add(oldNeighbor);
      }
    }
    // --- End Store state ---


    // Calculate the final parameters for placeClipOnTrack
    // Store original times for delta calculation
    final originalStartTimeOnTrackMs = clipToResize.startTimeOnTrackMs;
    final originalEndTimeOnTrackMs = clipToResize.endTimeOnTrackMs;
    final originalStartTimeInSourceMs = clipToResize.startTimeInSourceMs;
    final originalEndTimeInSourceMs = clipToResize.endTimeInSourceMs;
    final sourceDurationMs = clipToResize.sourceDurationMs;

    // --- Calculate Target Times based on Drag ---
    int targetStartTimeOnTrackMs = originalStartTimeOnTrackMs;
    int targetEndTimeOnTrackMs = originalEndTimeOnTrackMs;
    int targetStartTimeInSourceMs = originalStartTimeInSourceMs;
    int targetEndTimeInSourceMs = originalEndTimeInSourceMs;
    final newBoundaryMs = ClipModel.framesToMs(newBoundaryFrame);

    if (direction == 'left') {
      targetStartTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs = targetStartTimeOnTrackMs - originalStartTimeOnTrackMs;
      targetStartTimeInSourceMs = originalStartTimeInSourceMs + trackDeltaMs;
      // targetEndTimeOnTrackMs & targetEndTimeInSourceMs remain original
    } else { // direction == 'right'
      targetEndTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs = targetEndTimeOnTrackMs - originalEndTimeOnTrackMs;
      targetEndTimeInSourceMs = originalEndTimeInSourceMs + trackDeltaMs;
      // targetStartTimeOnTrackMs & targetStartTimeInSourceMs remain original
    }

    // --- Clamp Source Times ---
    // Ensure start is within [0, sourceDuration]
    int finalStartTimeInSourceMs = targetStartTimeInSourceMs.clamp(0, sourceDurationMs);
    // Ensure end is within [start, sourceDuration]
    int finalEndTimeInSourceMs = targetEndTimeInSourceMs.clamp(finalStartTimeInSourceMs, sourceDurationMs);
    // Recalculate start based on clamped end if needed (e.g., duration becomes 0)
    finalStartTimeInSourceMs = finalStartTimeInSourceMs.clamp(0, finalEndTimeInSourceMs);

    // --- Recalculate Track Times based on Clamped Source Times ---
    int finalStartTimeOnTrackMs;
    int finalEndTimeOnTrackMs;

    if (direction == 'left') {
       // End track time is fixed, calculate start track time based on clamped source start
       final sourceDeltaMs = finalStartTimeInSourceMs - originalStartTimeInSourceMs;
       finalStartTimeOnTrackMs = originalStartTimeOnTrackMs + sourceDeltaMs;
       finalEndTimeOnTrackMs = originalEndTimeOnTrackMs; // End remains anchored
    } else { // direction == 'right'
       // Start track time is fixed, calculate end track time based on clamped source end
       final sourceDeltaMs = finalEndTimeInSourceMs - originalEndTimeInSourceMs;
       finalStartTimeOnTrackMs = originalStartTimeOnTrackMs; // Start remains anchored
       finalEndTimeOnTrackMs = originalEndTimeOnTrackMs + sourceDeltaMs;
    }

    // --- Final Duration Checks ---
    // Ensure minimum track duration (1 frame)
    final minTrackDurationMs = ClipModel.framesToMs(1);
    if (finalEndTimeOnTrackMs - finalStartTimeOnTrackMs < minTrackDurationMs) {
        logger.logWarning('[ResizeClipCommand] Final track duration adjusted to minimum.', _logTag);
        if (direction == 'left') {
            finalStartTimeOnTrackMs = finalEndTimeOnTrackMs - minTrackDurationMs;
        } else {
            finalEndTimeOnTrackMs = finalStartTimeOnTrackMs + minTrackDurationMs;
        }
    }
    // Ensure minimum source duration (adjust end time if possible, preserving start)
    final minSourceDurationMs = 1; // Use 1ms minimum source duration
    if (finalEndTimeInSourceMs - finalStartTimeInSourceMs < minSourceDurationMs && sourceDurationMs > 0) {
        logger.logWarning('[ResizeClipCommand] Final source duration adjusted to minimum.', _logTag);
        finalEndTimeInSourceMs = (finalStartTimeInSourceMs + minSourceDurationMs).clamp(finalStartTimeInSourceMs, sourceDurationMs);
    } else if (sourceDurationMs == 0) {
         finalStartTimeInSourceMs = 0;
         finalEndTimeInSourceMs = 0;
     }

    // --- Call placeClipOnTrack with Final Consistent Values ---
    logger.logInfo('[ResizeClipCommand] Final values: Track[$finalStartTimeOnTrackMs-$finalEndTimeOnTrackMs], Source[$finalStartTimeInSourceMs-$finalEndTimeInSourceMs]', _logTag);
    try {
      final success = await vm.placeClipOnTrack(
        clipId: clipId,
        trackId: clipToResize.trackId,
        type: clipToResize.type,
        sourcePath: clipToResize.sourcePath,
        sourceDurationMs: sourceDurationMs,
        startTimeOnTrackMs: finalStartTimeOnTrackMs, // Use final calculated track time
        endTimeOnTrackMs: finalEndTimeOnTrackMs,     // Use final calculated track time
        startTimeInSourceMs: finalStartTimeInSourceMs, // Use final clamped source time
        endTimeInSourceMs: finalEndTimeInSourceMs,     // Use final clamped source time
      );

      if (success) {
        logger.logInfo('[ResizeClipCommand] Successfully resized clip $clipId', _logTag);
        // await vm.refreshClips(); // Rely on stream/notifier updates
      } else {
        logger.logWarning('[ResizeClipCommand] placeClipOnTrack returned false for clip $clipId resize', _logTag);
      }
    } catch (e) {
      logger.logError('[ResizeClipCommand] Error resizing clip $clipId: $e', _logTag);
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[ResizeClipCommand] Undoing resize of clipId=$clipId', _logTag);
    if (_originalClipState == null || _originalNeighborStates == null) {
      logger.logError('[ResizeClipCommand] Cannot undo: Original state not saved', _logTag);
      return;
    }

    try {
      // 1. Restore neighbors (similar complexity to MoveClipCommand undo)
      logger.logInfo('[ResizeClipCommand] Restoring neighbors (basic implementation)', _logTag);
       for (final originalNeighbor in _originalNeighborStates!) {
          final currentNeighbor = vm.clips.firstWhereOrNull((c) => c.databaseId == originalNeighbor.databaseId);
          if (currentNeighbor != null) {
              await vm.projectDatabaseService.clipDao!.updateClipFields(
                originalNeighbor.databaseId!,
                {
                  'trackId': originalNeighbor.trackId,
                  'startTimeOnTrackMs': originalNeighbor.startTimeOnTrackMs,
                  'startTimeInSourceMs': originalNeighbor.startTimeInSourceMs,
                  'endTimeInSourceMs': originalNeighbor.endTimeInSourceMs,
                },
              );
          } else {
              // TODO: Implement re-insertion of deleted neighbors during undo.
              logger.logWarning('[ResizeClipCommand] Undo cannot yet restore deleted neighbor ${originalNeighbor.databaseId}', _logTag);
          }
       }


      // 2. Resize the clip back to its original state using placeClipOnTrack
      logger.logInfo('[ResizeClipCommand] Restoring clip $clipId back to original state', _logTag);
      final success = await vm.placeClipOnTrack(
        clipId: clipId,
        trackId: _originalClipState!.trackId,
        type: _originalClipState!.type,
        sourcePath: _originalClipState!.sourcePath,
        sourceDurationMs: _originalClipState!.sourceDurationMs, // Restore source duration
        startTimeOnTrackMs: _originalClipState!.startTimeOnTrackMs,
        endTimeOnTrackMs: _originalClipState!.endTimeOnTrackMs,     // Restore end time on track
        startTimeInSourceMs: _originalClipState!.startTimeInSourceMs,
        endTimeInSourceMs: _originalClipState!.endTimeInSourceMs,
      );

      if (success) {
        logger.logInfo('[ResizeClipCommand] Successfully resized clip $clipId back', _logTag);
        // await vm.refreshClips(); // Rely on stream/notifier updates
      } else {
        logger.logWarning('[ResizeClipCommand] placeClipOnTrack returned false when resizing clip $clipId back', _logTag);
      }

      // Clear state after successful undo
      _originalClipState = null;
      _originalNeighborStates = null;

    } catch (e) {
      logger.logError('[ResizeClipCommand] Error undoing resize of clip $clipId: $e', _logTag);
      rethrow;
    }
  }
}