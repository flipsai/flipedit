import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For firstWhereOrNull
import '../../services/timeline_logic_service.dart'; // Import the new service
import 'package:watch_it/watch_it.dart'; // Import for di

/// Command to move a clip to a new track and/or start time.
class MoveClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int clipId;
  final int newTrackId;
  // Add dependency on TimelineLogicService
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final int newStartTimeOnTrackMs;

  // Store original state for undo
  int? _originalTrackId;
  int? _originalStartTimeOnTrackMs;
  // Store state of neighbors affected by the move for undo
  List<ClipModel>? _originalNeighborStates;
  ClipModel? _originalClipState; // Store the state of the moved clip itself

  static const _logTag = "MoveClipCommand";

  MoveClipCommand({
    required this.vm,
    required this.clipId,
    required this.newTrackId,
    required this.newStartTimeOnTrackMs,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[MoveClipCommand] Executing: clipId=$clipId, newTrackId=$newTrackId, newStartTimeMs=$newStartTimeOnTrackMs',
      _logTag,
    );

    final clipToMove = vm.clips.firstWhereOrNull((c) => c.databaseId == clipId);

    if (clipToMove == null) {
      logger.logError('[MoveClipCommand] Clip $clipId not found in ViewModel', _logTag);
      throw Exception('Clip $clipId not found for moving');
    }

    // --- Store state for Undo ---
    _originalClipState = clipToMove.copyWith(); // Save state of the moved clip
    _originalTrackId = clipToMove.trackId;
    _originalStartTimeOnTrackMs = clipToMove.startTimeOnTrackMs;

    // Find neighbors potentially affected by the *new* position
    final newEndTimeMs = newStartTimeOnTrackMs + clipToMove.durationOnTrackMs; // Use durationOnTrackMs
    _originalNeighborStates = _timelineLogicService.getOverlappingClips( // Use the new service
      vm.clips, // Pass the current clips
      newTrackId,
      newStartTimeOnTrackMs,
      newEndTimeMs,
      clipId, // Exclude the clip being moved itself
    ).map((c) => c.copyWith()).toList(); // Deep copy for undo

    // Also store neighbors affected by the *old* position (needed if moving back overlaps differently)
    final oldEndTimeMs = clipToMove.startTimeOnTrackMs + clipToMove.durationOnTrackMs; // Use durationOnTrackMs
    final oldNeighbors = _timelineLogicService.getOverlappingClips( // Use the new service
      vm.clips, // Pass the current clips
      clipToMove.trackId,
      clipToMove.startTimeOnTrackMs,
      oldEndTimeMs,
      clipId,
    ).map((c) => c.copyWith()).toList();
    // Add old neighbors if they weren't already captured as new neighbors
    for (final oldNeighbor in oldNeighbors) {
      if (!_originalNeighborStates!.any((n) => n.databaseId == oldNeighbor.databaseId)) {
        _originalNeighborStates!.add(oldNeighbor);
      }
    }
    // --- End Store state ---


    try {
      // Delegate the complex placement logic (including neighbor trimming)
      // to the existing placeClipOnTrack method.
      final success = await vm.placeClipOnTrack(
        clipId: clipId, // Pass clipId to indicate an update/move
        trackId: newTrackId,
        type: clipToMove.type,
        sourcePath: clipToMove.sourcePath,
        sourceDurationMs: clipToMove.sourceDurationMs, // Pass original source duration
        startTimeOnTrackMs: newStartTimeOnTrackMs,
        // End time on track is calculated from start + duration for a move
        endTimeOnTrackMs: newStartTimeOnTrackMs + clipToMove.durationOnTrackMs,
        startTimeInSourceMs: clipToMove.startTimeInSourceMs, // Keep original source times
        endTimeInSourceMs: clipToMove.endTimeInSourceMs,     // Keep original source times
      );

      if (success) {
        logger.logInfo('[MoveClipCommand] Successfully moved clip $clipId', _logTag);
        // Refresh might be needed if placeClipOnTrack doesn't update the notifier sufficiently
        // await vm.refreshClips(); // Rely on stream/notifier updates from placeClipOnTrack
      } else {
        logger.logWarning('[MoveClipCommand] placeClipOnTrack returned false for clip $clipId', _logTag);
        // Consider throwing an error or handling the failure case
      }
    } catch (e) {
      logger.logError('[MoveClipCommand] Error moving clip $clipId: $e', _logTag);
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[MoveClipCommand] Undoing move of clipId=$clipId', _logTag);
    if (_originalTrackId == null || _originalStartTimeOnTrackMs == null || _originalNeighborStates == null || _originalClipState == null) {
      logger.logError('[MoveClipCommand] Cannot undo: Original state not saved', _logTag);
      return;
    }

    try {
      // 1. Restore the neighbors that were affected by the original move
      //    This needs careful handling. `placeClipOnTrack` when moving the clip *back*
      //    should ideally handle trimming/removing clips at the *original* location.
      //    However, we might need to explicitly restore neighbors that were fully removed
      //    or significantly altered by the initial `execute` call.
      //    A simpler approach for now: rely on moving the clip back and let
      //    `placeClipOnTrack` recalculate overlaps at the original position.
      //    We might need to enhance `placeClipOnTrack` or add specific restore logic here later.

      // Restore neighbors first (attempt to put them back as they were)
      // This is complex because placeClipOnTrack might have deleted them.
      // A full undo might require restoring deleted clips and then updating others.
      // For now, we focus on moving the main clip back.
      logger.logInfo('[MoveClipCommand] Restoring neighbors (basic implementation)', _logTag);
      for (final originalNeighbor in _originalNeighborStates!) {
         // Check if neighbor still exists
         final currentNeighbor = vm.clips.firstWhereOrNull((c) => c.databaseId == originalNeighbor.databaseId);
         if (currentNeighbor != null) {
            // If it exists, update it back to its original state
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
             // If it was deleted, we need to re-insert it.
             // This requires the ClipsCompanion logic similar to RemoveClipCommand undo.
             // TODO: Implement re-insertion of deleted neighbors during undo.
             logger.logWarning('[MoveClipCommand] Undo cannot yet restore deleted neighbor ${originalNeighbor.databaseId}', _logTag);
         }
      }


      // 2. Move the clip back to its original position using placeClipOnTrack
      //    This will handle overlaps at the original location.
      logger.logInfo('[MoveClipCommand] Moving clip $clipId back to original position', _logTag);
      final success = await vm.placeClipOnTrack(
        clipId: clipId, // Identify the clip to restore
        trackId: _originalTrackId!,
        type: _originalClipState!.type,
        sourcePath: _originalClipState!.sourcePath,
        sourceDurationMs: _originalClipState!.sourceDurationMs, // Restore original source duration
        startTimeOnTrackMs: _originalStartTimeOnTrackMs!,
        endTimeOnTrackMs: _originalClipState!.endTimeOnTrackMs, // Restore original end time on track
        startTimeInSourceMs: _originalClipState!.startTimeInSourceMs,
        endTimeInSourceMs: _originalClipState!.endTimeInSourceMs,
      );

      if (success) {
        logger.logInfo('[MoveClipCommand] Successfully moved clip $clipId back', _logTag);
        // await vm.refreshClips(); // Rely on stream/notifier updates
      } else {
        logger.logWarning('[MoveClipCommand] placeClipOnTrack returned false when moving clip $clipId back', _logTag);
      }

      // Clear state after successful undo
      _originalTrackId = null;
      _originalStartTimeOnTrackMs = null;
      _originalNeighborStates = null;
      _originalClipState = null;

    } catch (e) {
      logger.logError('[MoveClipCommand] Error undoing move of clip $clipId: $e', _logTag);
      rethrow;
    }
  }
}