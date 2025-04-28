import 'package:flutter/foundation.dart'; // Added for ValueNotifier
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For firstWhereOrNull
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart'; // Added
import 'package:watch_it/watch_it.dart';

/// Command to move a clip to a new track and/or start time.
class MoveClipCommand implements TimelineCommand {
  final int clipId;
  final int newTrackId;
  final int newStartTimeOnTrackMs;
  final ProjectDatabaseService _projectDatabaseService = di<ProjectDatabaseService>(); // Inject service
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>(); // Inject service
  final ValueNotifier<List<ClipModel>> clipsNotifier; // Pass notifier for update

  // Store original state for undo
  ClipModel? _originalClipState; // Full state of the moved clip
  Map<int, Map<String, dynamic>>? _neighborUpdatesForUndo; // {id: {field: oldValue, ...}} for updated neighbors
  List<ClipModel>? _neighborsDeletedForUndo; // Full ClipModel for deleted neighbors

  static const _logTag = "MoveClipCommand";

  MoveClipCommand({
    required this.clipId,
    required this.newTrackId,
    required this.newStartTimeOnTrackMs,
    required this.clipsNotifier, // Add required notifier parameter
  });
  // Removed commented out/incorrect declaration below

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[MoveClipCommand] Executing: clipId=$clipId, newTrackId=$newTrackId, newStartTimeMs=$newStartTimeOnTrackMs',
      _logTag,
    );

    // Get current clips directly from the notifier
    final currentClips = clipsNotifier.value;
    final clipToMove = currentClips.firstWhereOrNull((c) => c.databaseId == clipId);

    if (clipToMove == null) {
      logger.logError('[MoveClipCommand] Clip $clipId not found in provided clips list', _logTag);
      throw Exception('Clip $clipId not found for moving');
    }

    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[MoveClipCommand] Clip DAO not initialized', _logTag);
      throw Exception('Clip DAO not initialized');
    }

    // --- Store state for Undo ---
    _originalClipState = clipToMove.copyWith(); // Save full original state
    _neighborUpdatesForUndo = {};
    _neighborsDeletedForUndo = [];

    // Determine the end time for the move based on the clip's *current* duration on track
    // Ensure calculated end time is int
    final int newEndTimeMs = newStartTimeOnTrackMs + clipToMove.durationOnTrackMs;


    try {
      // Use TimelineLogicService to calculate the effects of the placement
      final placementResult = _timelineLogicService.prepareClipPlacement(
        clips: currentClips,
        clipId: clipId,
        trackId: newTrackId,
        type: clipToMove.type,
        sourcePath: clipToMove.sourcePath,
        sourceDurationMs: clipToMove.sourceDurationMs,
        startTimeOnTrackMs: newStartTimeOnTrackMs,
        endTimeOnTrackMs: newEndTimeMs, // Use calculated end time
        startTimeInSourceMs: clipToMove.startTimeInSourceMs, // Source times don't change on move
        endTimeInSourceMs: clipToMove.endTimeInSourceMs,
      );

      if (!placementResult['success']) {
        throw Exception('prepareClipPlacement failed during move command');
      }

      final List<Map<String, dynamic>> neighborUpdates = List.from(placementResult['clipUpdates']);
      final List<int> neighborsToDelete = List.from(placementResult['clipsToRemove']);
      final Map<String, dynamic> mainClipUpdateData = Map.from(placementResult['newClipData']);

      // --- Perform Database Operations ---
      logger.logDebug('[MoveClipCommand] Applying DB updates...', _logTag);

      // 1. Update neighbors
      for (final update in neighborUpdates) {
        final int neighborId = update['id'];
        final Map<String, dynamic> fields = Map.from(update['fields']);
        // Store original values for undo BEFORE updating
        final originalNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
        if (originalNeighbor != null) {
          final Map<String, dynamic> originalValues = {};
          fields.forEach((key, _) {
            // Using switch for type safety, though Map access might work
            switch (key) {
                case 'trackId': originalValues[key] = originalNeighbor.trackId; break;
                case 'startTimeOnTrackMs': originalValues[key] = originalNeighbor.startTimeOnTrackMs; break;
                case 'endTimeOnTrackMs': originalValues[key] = originalNeighbor.endTimeOnTrackMs; break;
                case 'startTimeInSourceMs': originalValues[key] = originalNeighbor.startTimeInSourceMs; break;
                case 'endTimeInSourceMs': originalValues[key] = originalNeighbor.endTimeInSourceMs; break;
                // Add other potential fields if necessary
            }
          });
          _neighborUpdatesForUndo![neighborId] = originalValues;
        }
        await _projectDatabaseService.clipDao!.updateClipFields(neighborId, fields, log: false); // Don't log individual neighbor updates
      }

      // 2. Delete neighbors
      for (final int neighborId in neighborsToDelete) {
         // Store full clip data for undo BEFORE deleting
         final deletedNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
         if(deletedNeighbor != null) {
            _neighborsDeletedForUndo!.add(deletedNeighbor.copyWith());
         }
         await _projectDatabaseService.clipDao!.deleteClip(neighborId); // Log deletion
      }

      // 3. Update the main moved clip
      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        {
          'trackId': mainClipUpdateData['trackId'],
          'startTimeOnTrackMs': mainClipUpdateData['startTimeOnTrackMs'],
          'endTimeOnTrackMs': mainClipUpdateData['endTimeOnTrackMs'],
          'startTimeInSourceMs': mainClipUpdateData['startTimeInSourceMs'], // Should be original
          'endTimeInSourceMs': mainClipUpdateData['endTimeInSourceMs'],     // Should be original
          // sourceDurationMs doesn't change on move
        },
        log: true, // Log the primary action for undo/redo history
      );

      // --- Update ViewModel State ---
      logger.logDebug('[MoveClipCommand] Updating ViewModel state...', _logTag);
      // The placementResult['updatedClips'] contains the optimistic state
      clipsNotifier.value = List<ClipModel>.from(placementResult['updatedClips']);

      logger.logInfo('[MoveClipCommand] Successfully executed move for clip $clipId', _logTag);

    } catch (e) {
      logger.logError('[MoveClipCommand] Error executing move for clip $clipId: $e', _logTag);
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[MoveClipCommand] Undoing move for clipId=$clipId', _logTag);
    if (_originalClipState == null || _neighborUpdatesForUndo == null || _neighborsDeletedForUndo == null) {
      logger.logError('[MoveClipCommand] Cannot undo: Original state not fully saved', _logTag);
      return;
    }
     if (_projectDatabaseService.clipDao == null) {
      logger.logError('[MoveClipCommand] Clip DAO not initialized for undo', _logTag);
      throw Exception('Clip DAO not initialized for undo');
    }

    try {
      // --- Restore Database State ---
      logger.logDebug('[MoveClipCommand][Undo] Restoring DB state...', _logTag);

      // 1. Restore the main moved clip to its original state
      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        {
          'trackId': _originalClipState!.trackId,
          'startTimeOnTrackMs': _originalClipState!.startTimeOnTrackMs,
          'endTimeOnTrackMs': _originalClipState!.endTimeOnTrackMs,
          'startTimeInSourceMs': _originalClipState!.startTimeInSourceMs,
          'endTimeInSourceMs': _originalClipState!.endTimeInSourceMs,
          // Add other relevant fields if needed
        },
         log: true // Log the undo action
      );

      // 2. Restore updated neighbors
      for (final neighborId in _neighborUpdatesForUndo!.keys) {
        final originalValues = _neighborUpdatesForUndo![neighborId]!;
         await _projectDatabaseService.clipDao!.updateClipFields(neighborId, originalValues, log: false);
      }

      // 3. Re-insert deleted neighbors
      for (final deletedNeighbor in _neighborsDeletedForUndo!) {
        // Create a companion from the stored ClipModel
        final companion = deletedNeighbor.toDbCompanion(); // Corrected method name
         await _projectDatabaseService.clipDao!.insertClip(companion); // Removed log: false
      }

      // --- Refresh ViewModel State ---
      // A full refresh is the safest way to ensure consistency after complex undo
      logger.logDebug('[MoveClipCommand][Undo] ViewModel state should refresh via listeners.', _logTag);
      // Removed direct refresh call: await _projectDatabaseService.refreshClipsFromDb();
      // The ViewModel should listen to ProjectDatabaseService's clip changes

      logger.logInfo('[MoveClipCommand] Successfully undone move for clip $clipId', _logTag);

      // Clear undo state
      _originalClipState = null;
      _neighborUpdatesForUndo = null;
      _neighborsDeletedForUndo = null;

    } catch (e) {
      logger.logError('[MoveClipCommand] Error undoing move for clip $clipId: $e', _logTag);
      rethrow;
    }
  }
}