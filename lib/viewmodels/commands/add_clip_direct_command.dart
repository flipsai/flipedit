import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import '../../models/enums/clip_type.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'remove_clip_command.dart'; // Import for undo logic

/// Command to add a clip directly using specified timecodes.
class AddClipDirectCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int trackId;
  final ClipType type;
  final String sourcePath;
  final int startTimeOnTrackMs;
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;

  // Store ID of the added clip for undo
  int? _addedClipId;
  // Store state of neighbors affected by the add for undo
  List<ClipModel>? _originalNeighborStates;


  static const _logTag = "AddClipDirectCommand";

  AddClipDirectCommand({
    required this.vm,
    required this.trackId,
    required this.type,
    required this.sourcePath,
    required this.startTimeOnTrackMs,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[AddClipDirectCommand] Executing: trackId=$trackId, type=$type, path=$sourcePath, startTrackMs=$startTimeOnTrackMs',
      _logTag,
    );

     // --- Store state for Undo ---
     // Find neighbors potentially affected by the new clip's position
     final newClipDuration = endTimeInSourceMs - startTimeInSourceMs;
     final newEndTimeMs = startTimeOnTrackMs + newClipDuration;
     _originalNeighborStates = vm.getOverlappingClips(
       trackId,
       startTimeOnTrackMs,
       newEndTimeMs,
       null, // No clip ID to exclude yet
     ).map((c) => c.copyWith()).toList(); // Deep copy for undo
     // --- End Store state ---


    try {
      // Delegate the complex placement logic (including neighbor trimming)
      // to the existing placeClipOnTrack method.
      // Note: placeClipOnTrack now returns the ID of the created clip if successful.
      final result = await vm.placeClipOnTrack(
        clipId: null, // Indicate new clip creation
        trackId: trackId,
        type: type,
        sourcePath: sourcePath,
        startTimeOnTrackMs: startTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );

      // placeClipOnTrack returns bool, but the insertClip inside returns the ID.
      // We need to retrieve the ID for undo. This requires modifying placeClipOnTrack
      // or finding the clip after insertion. Let's assume placeClipOnTrack is modified
      // to return the ID, or we find it.
      // For now, we'll assume `result` indicates success, but we don't have the ID yet.
      // TODO: Modify placeClipOnTrack to return the new clip's ID or find it after insertion.

      if (result) { // Assuming placeClipOnTrack returns bool for success
         // Find the newly added clip to store its ID for undo
         // This is inefficient; placeClipOnTrack should return the ID.
         // final addedClip = vm.clips.lastWhereOrNull( ... ); // Complex logic to find it
         // _addedClipId = addedClip?.databaseId;
        logger.logInfo('[AddClipDirectCommand] Successfully added clip (ID retrieval pending)', _logTag);
        // await vm.refreshClips(); // Rely on stream/notifier updates
      } else {
        logger.logWarning('[AddClipDirectCommand] placeClipOnTrack returned false', _logTag);
      }
    } catch (e) {
      logger.logError('[AddClipDirectCommand] Error adding clip: $e', _logTag);
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[AddClipDirectCommand] Undoing add clip (ID: $_addedClipId)', _logTag);
    if (_addedClipId == null) {
      logger.logError('[AddClipDirectCommand] Cannot undo: Added clip ID not stored. Manual removal might be needed or find logic implemented.', _logTag);
      // Attempt to find the clip based on parameters if ID wasn't stored
      // This is a fallback and less reliable.
      // final potentialClip = vm.clips.firstWhereOrNull(...);
      // if (potentialClip != null) _addedClipId = potentialClip.databaseId;
      // else return; // Still can't find it
       return; // Cannot proceed without ID
    }
     if (_originalNeighborStates == null) {
       logger.logError('[AddClipDirectCommand] Cannot undo: Original neighbor state not saved', _logTag);
       return;
     }


    try {
      // 1. Restore neighbors
      logger.logInfo('[AddClipDirectCommand] Restoring neighbors (basic implementation)', _logTag);
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
              // If the neighbor was deleted by placeClipOnTrack, re-insert it.
              // TODO: Implement re-insertion of deleted neighbors during undo.
              logger.logWarning('[AddClipDirectCommand] Undo cannot yet restore deleted neighbor ${originalNeighbor.databaseId}', _logTag);
          }
       }

      // 2. Remove the added clip
      logger.logInfo('[AddClipDirectCommand] Removing the originally added clip $_addedClipId', _logTag);
      final removeCommand = RemoveClipCommand(vm: vm, clipId: _addedClipId!);
      await removeCommand.execute(); // Use the RemoveClipCommand to handle removal and notifier update

      logger.logInfo('[AddClipDirectCommand] Successfully undone add clip $_addedClipId', _logTag);

      // Clear state
      _addedClipId = null;
      _originalNeighborStates = null;

    } catch (e) {
      logger.logError('[AddClipDirectCommand] Error undoing add clip: $e', _logTag);
      rethrow;
    }
  }
}

// Helper needed for firstWhereOrNull if not using collection package
extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}