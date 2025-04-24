import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For firstWhereOrNull

/// Command to resize a clip by adjusting its start or end time.
class ResizeClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int clipId;
  final String direction; // 'left' or 'right'
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

    // Calculate the *potential* new time range to find affected neighbors
    int potentialNewStartMs = clipToResize.startTimeOnTrackMs;
    int potentialNewEndMs = clipToResize.startTimeOnTrackMs + clipToResize.durationMs;
    final newBoundaryMs = ClipModel.framesToMs(newBoundaryFrame);

    if (direction == 'left') {
      potentialNewStartMs = newBoundaryMs;
    } else { // direction == 'right'
      potentialNewEndMs = newBoundaryMs;
    }
    // Ensure start is before end if resizing causes inversion (though placeClipOnTrack might handle this)
    if (potentialNewStartMs >= potentialNewEndMs) {
         logger.logWarning('[ResizeClipCommand] Resize would result in zero or negative duration. Clamping.', _logTag);
         if (direction == 'left') {
            potentialNewStartMs = potentialNewEndMs - ClipModel.framesToMs(1); // Minimum 1 frame duration
         } else {
            potentialNewEndMs = potentialNewStartMs + ClipModel.framesToMs(1);
         }
    }


    _originalNeighborStates = vm.getOverlappingClips(
      clipToResize.trackId,
      potentialNewStartMs,
      potentialNewEndMs,
      clipId, // Exclude the clip being resized itself
    ).map((c) => c.copyWith()).toList(); // Deep copy for undo

    // Also include neighbors affected by the *original* range if the resize shrinks the clip
     final originalEndTimeMs = clipToResize.startTimeOnTrackMs + clipToResize.durationMs;
     final oldNeighbors = vm.getOverlappingClips(
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


    // Calculate the actual parameters for placeClipOnTrack
    int newStartTimeOnTrackMs = clipToResize.startTimeOnTrackMs;
    int newEndTimeOnTrackMs = clipToResize.startTimeOnTrackMs + clipToResize.durationMs;
    int newStartTimeInSourceMs = clipToResize.startTimeInSourceMs;
    int newEndTimeInSourceMs = clipToResize.endTimeInSourceMs;
    final originalStartMs = clipToResize.startTimeOnTrackMs;


    if (direction == 'left') {
      newStartTimeOnTrackMs = newBoundaryMs;
      // Adjust source start time based on how much the track start time changed
      final deltaMs = newStartTimeOnTrackMs - originalStartMs;
      newStartTimeInSourceMs = clipToResize.startTimeInSourceMs + deltaMs;
      // End time on track doesn't change directly, but duration does
      newEndTimeOnTrackMs = originalStartMs + clipToResize.durationMs;
    } else { // direction == 'right'
      newEndTimeOnTrackMs = newBoundaryMs;
      // Adjust source end time based on how much the track end time changed
      final deltaMs = newEndTimeOnTrackMs - (originalStartMs + clipToResize.durationMs);
      newEndTimeInSourceMs = clipToResize.endTimeInSourceMs + deltaMs;
       // Start time on track doesn't change
       newStartTimeOnTrackMs = originalStartMs;
    }

     // Basic validation: Ensure duration is positive
     if (newEndTimeOnTrackMs <= newStartTimeOnTrackMs || newEndTimeInSourceMs <= newStartTimeInSourceMs) {
       logger.logError('[ResizeClipCommand] Invalid resize parameters resulted in zero/negative duration.', _logTag);
       // Decide how to handle: throw error, or revert to original? Reverting might be safer.
       // For now, let placeClipOnTrack handle it or potentially fail.
       // A more robust solution would clamp values here.
       // Example clamp:
       if (newEndTimeOnTrackMs <= newStartTimeOnTrackMs) {
           newEndTimeOnTrackMs = newStartTimeOnTrackMs + ClipModel.framesToMs(1);
           // Recalculate corresponding source end time if needed
       }
        if (newEndTimeInSourceMs <= newStartTimeInSourceMs) {
           newEndTimeInSourceMs = newStartTimeInSourceMs + ClipModel.framesToMs(1);
           // Recalculate corresponding track end time if needed
       }
       logger.logWarning('[ResizeClipCommand] Clamped duration to minimum 1 frame.', _logTag);

     }


    try {
      // Use placeClipOnTrack to handle the resize and neighbor trimming
      final success = await vm.placeClipOnTrack(
        clipId: clipId,
        trackId: clipToResize.trackId, // Track ID doesn't change
        type: clipToResize.type,
        sourcePath: clipToResize.sourcePath,
        startTimeOnTrackMs: newStartTimeOnTrackMs,
        startTimeInSourceMs: newStartTimeInSourceMs,
        endTimeInSourceMs: newEndTimeInSourceMs, // placeClipOnTrack uses this to calculate duration
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
      logger.logInfo('[ResizeClipCommand] Resizing clip $clipId back to original state', _logTag);
      final success = await vm.placeClipOnTrack(
        clipId: clipId,
        trackId: _originalClipState!.trackId,
        type: _originalClipState!.type,
        sourcePath: _originalClipState!.sourcePath,
        startTimeOnTrackMs: _originalClipState!.startTimeOnTrackMs,
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