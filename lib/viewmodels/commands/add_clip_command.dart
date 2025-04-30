import 'package:drift/drift.dart' as drift;
import 'package:flipedit/persistence/database/project_database.dart' as project_db;
import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart'; // Import the service
import 'package:watch_it/watch_it.dart';
import '../../services/undo_redo_service.dart'; // ADDED Import for UndoRedoService

/// Command to add a clip to the timeline at a specific position.
class AddClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel clipData; // Should contain initial source times, path, type etc.
  final int trackId;
  final int startTimeOnTrackMs; // The desired start time on the track

  // Dependencies
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();

  // State for undo
  int? _insertedClipId;
  List<ClipModel>? _originalNeighborStates; // To restore neighbors changed by placement
  List<int>? _removedNeighborIds; // To restore neighbors removed by placement

  static const _logTag = "AddClipCommand";

  AddClipCommand({
    required this.vm,
    required this.clipData, // Contains source path, type, source times, source duration
    required this.trackId,
    required this.startTimeOnTrackMs, // The desired start time on the track
  });

  @override
  Future<void> execute() async {
    if (_databaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return;
    }

    // --- Prepare Clip Data for Placement ---
    // Calculate initial end time on track based on the source segment duration
    final initialEndTimeOnTrackMs = startTimeOnTrackMs + clipData.durationInSourceMs;
    // Use source duration from the clipData (assuming it was populated correctly during import)
    // TODO: Ensure clipData.sourceDurationMs is reliable.
    final sourceDurationMs = clipData.sourceDurationMs;

    logger.logInfo(
      '[AddClipCommand] Preparing placement: track=$trackId, startTrack=$startTimeOnTrackMs, endTrack=$initialEndTimeOnTrackMs, startSource=${clipData.startTimeInSourceMs}, endSource=${clipData.endTimeInSourceMs}, sourceDuration=$sourceDurationMs',
      _logTag,
    );

    // 1. Calculate placement using the logic service
    final placement = _timelineLogicService.prepareClipPlacement(
      clips: vm.clips, // Pass current clips from ViewModel
      clipId: null, // Explicitly null for adding
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      sourceDurationMs: sourceDurationMs,     // Pass source duration
      startTimeOnTrackMs: startTimeOnTrackMs, // Pass desired track start
      endTimeOnTrackMs: initialEndTimeOnTrackMs, // Pass calculated track end
      startTimeInSourceMs: clipData.startTimeInSourceMs, // Pass initial source start
      endTimeInSourceMs: clipData.endTimeInSourceMs,     // Pass initial source end (will be clamped)
    );

    if (!placement['success']) {
      logger.logError('Failed to calculate clip placement', _logTag);
      return;
    }

    // Store state for undo BEFORE making changes
    final currentClips = vm.clips; // Get a stable list reference
    _originalNeighborStates = (placement['clipUpdates'] as List<Map<String, dynamic>>)
        .map<ClipModel?>((updateMap) {
          try {
            return currentClips.firstWhere((c) => c.databaseId == updateMap['id']);
          } catch (_) {
            return null; // Return null if not found
          }
        })
        .where((c) => c != null) // Filter out nulls
        .map((c) => c!.copyWith()) // Create deep copies for non-null clips
        .toList();
    _removedNeighborIds = List<int>.from(placement['clipsToRemove'] as List<int>); // Store IDs of removed clips

    // --- LOGGING: Show planned DB changes ---
    logger.logInfo('[AddClipCommand] Planned Neighbor Updates: ${placement['clipUpdates']}', _logTag);
    logger.logInfo('[AddClipCommand] Planned Neighbor Removals: ${placement['clipsToRemove']}', _logTag);
    // --------------------------------------


    // 2. Handle persistence operations
    logger.logInfo(
        '[AddClipCommand] Applying DB changes: updates=${placement['clipUpdates'].length}, removals=${placement['clipsToRemove'].length}',
        _logTag);

    // 2.1 Apply updates to overlapping clips
    for (final update in placement['clipUpdates']) {
      await _databaseService.clipDao!.updateClipFields(
        update['id'],
        update['fields'],
        // log: true, // DAO methods don't have this parameter
      );
    }

    // 2.2 Remove fully overlapped clips
    for (final id in _removedNeighborIds!) { // Use stored list
      await _databaseService.clipDao!.deleteClip(id); // log: true removed
    }

    // 2.3 Insert the new clip using the final calculated placement data
    final newClipDataMap = placement['newClipData'] as Map<String, dynamic>; // Defined here
    logger.logInfo('[AddClipCommand] Inserting new clip: $newClipDataMap', _logTag);

    _insertedClipId = await _databaseService.clipDao!.insertClip(
      project_db.ClipsCompanion(
        trackId: drift.Value(trackId),
        name: drift.Value(clipData.name), // Use name from clipData
        type: drift.Value(clipData.type.name),
        sourcePath: drift.Value(clipData.sourcePath),
        sourceDurationMs: drift.Value(newClipDataMap['sourceDurationMs']), // Store source duration
        startTimeOnTrackMs: drift.Value(newClipDataMap['startTimeOnTrackMs']),
        endTimeOnTrackMs: drift.Value(newClipDataMap['endTimeOnTrackMs']), // Store track end time
        startTimeInSourceMs: drift.Value(newClipDataMap['startTimeInSourceMs']),
        endTimeInSourceMs: drift.Value(newClipDataMap['endTimeInSourceMs']),
        // metadataJson: clipData.metadata.isNotEmpty ? drift.Value(jsonEncode(clipData.metadata)) : const drift.Value.absent(), // TODO: Handle metadata
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    logger.logInfo('[AddClipCommand] Inserted new clip with ID: $_insertedClipId', _logTag);


    // 3. Update ViewModel state DIRECTLY with the calculated list
    // await vm.refreshClips(); // REPLACED
    List<ClipModel> finalUpdatedClips = List<ClipModel>.from(placement['updatedClips']); // Make mutable copy
    // final newClipDataMap = placement['newClipData'] as Map<String, dynamic>; // REMOVED Redundant definition

    // Find the newly added clip (which has databaseId: null) in the optimistic list
    final newClipIndex = finalUpdatedClips.indexWhere((clip) => clip.databaseId == null && clip.sourcePath == clipData.sourcePath && clip.startTimeOnTrackMs == newClipDataMap['startTimeOnTrackMs']);

    if (newClipIndex != -1 && _insertedClipId != null) {
       // Update the clip in the list with its actual databaseId
       // Use drift.Value() wrapper for nullable ID in copyWith if required by the model
       final newClipWithId = finalUpdatedClips[newClipIndex].copyWith(databaseId: drift.Value(_insertedClipId));
       finalUpdatedClips[newClipIndex] = newClipWithId;
       logger.logInfo('[AddClipCommand] Updated new clip ID in optimistic list: $_insertedClipId', _logTag);
    } else {
        logger.logWarning('[AddClipCommand] Could not find newly inserted clip in optimistic list to update its ID.', _logTag);
    }

    vm.updateClipsAfterPlacement(finalUpdatedClips); // Use the dedicated method in ViewModel
    logger.logInfo('[AddClipCommand] Updated ViewModel clips directly.', _logTag);

    // 4. Update undo/redo state (after UI update)
    // Get UndoRedoService via DI
    final UndoRedoService undoRedoService = di<UndoRedoService>();
    await undoRedoService.init(); // Use own instance

  } // End execute

  @override
  Future<void> undo() async {
     logger.logInfo('[AddClipCommand] Undoing add clip: $_insertedClipId', _logTag);
    if (_insertedClipId == null || _originalNeighborStates == null || _removedNeighborIds == null) {
      logger.logError('Cannot undo AddClipCommand: Missing state', _logTag);
      return;
    }
     if (_databaseService.clipDao == null) {
       logger.logError('Cannot undo AddClipCommand: Clip DAO not initialized', _logTag);
       return;
     }

    try {
      // 1. Remove the inserted clip
      await _databaseService.clipDao!.deleteClip(_insertedClipId!); // log: true removed

      // 2. Restore neighbors that were updated (trimmed)
      for (final originalNeighbor in _originalNeighborStates!) {
         logger.logInfo('[AddClipCommand] Restoring updated neighbor: ${originalNeighbor.databaseId}', _logTag);
         // Use updateClipFields to restore all relevant fields
        await _databaseService.clipDao!.updateClipFields(
          originalNeighbor.databaseId!,
           {
             'trackId': originalNeighbor.trackId, // Just in case track changed (though unlikely for add)
             'startTimeOnTrackMs': originalNeighbor.startTimeOnTrackMs,
             'endTimeOnTrackMs': originalNeighbor.endTimeOnTrackMs,
             'startTimeInSourceMs': originalNeighbor.startTimeInSourceMs,
             'endTimeInSourceMs': originalNeighbor.endTimeInSourceMs,
             // We assume sourceDurationMs doesn't change
           },
          // log: true, // DAO methods don't have this parameter
       );
     }

       // 3. Restore neighbors that were removed
       for (final removedId in _removedNeighborIds!) {
           final originalRemovedNeighbor = vm.clips.firstWhere( // Find original state from *before* execute
               (c) => c.databaseId == removedId,
               orElse: () => throw Exception("Cannot find original state for removed neighbor $removedId") // Should not happen if logic is correct
           );
           logger.logInfo('[AddClipCommand] Restoring removed neighbor: $removedId', _logTag);
           // Re-insert the removed clip using its original state
           await _databaseService.clipDao!.insertClip(
               originalRemovedNeighbor.toDbCompanion(), // Use the companion converter
               // log: true // DAO methods don't have this parameter
           );
       }


      // 4. Refresh ViewModel state
      await vm.refreshClips();

      // Clear undo state
      _insertedClipId = null;
      _originalNeighborStates = null;
      _removedNeighborIds = null;
       logger.logInfo('[AddClipCommand] Undo complete', _logTag);

    } catch (e, s) {
       logger.logError('[AddClipCommand] Error during undo: $e\n$s', _logTag);
       // Consider how to handle undo failure - potentially leave state corrupted
       // or attempt to re-apply original changes?
    }
  } // End undo
}
