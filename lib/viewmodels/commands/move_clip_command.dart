import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'package:flipedit/persistence/database/project_database.dart' show ChangeLog; // For toChangeLog
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_http_service.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/di/service_locator.dart'; // Added for di
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Added for di
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart'; // For setClips

class MoveClipCommand implements TimelineCommand, UndoableCommand {
  final int clipId;
  final int newTrackId;
  final int newStartTimeOnTrackMs;
  
  // Dependencies - these are not part of the serialized state directly
  // but are needed for the command to function.
  final ProjectDatabaseService _projectDatabaseService;
  final TimelineLogicService _timelineLogicService;
  final PreviewHttpService _previewHttpService;
  final TimelineNavigationViewModel _timelineNavViewModel;
  final ValueNotifier<List<ClipModel>> _clipsNotifier; // Made private

  // State for undo/redo and serialization
  ClipModel? _originalClipState; // State of the main clip before move
  Map<int, ClipModel>? _originalNeighborStates; // Original states of updated neighbors
  List<ClipModel>? _deletedNeighborsState; // Original states of deleted neighbors
  
  ClipModel? _movedClipStateAfterExecute; // State of the main clip after move
  Map<int, ClipModel>? _updatedNeighborStatesAfterExecute; // State of neighbors after update
  // Note: We don't explicitly store "added" neighbors during a move, as move primarily updates/deletes.

  static const String commandType = 'moveClip';
  static const _logTag = "MoveClipCommand";

  MoveClipCommand({
    required this.clipId,
    required this.newTrackId,
    required this.newStartTimeOnTrackMs,
    // Required dependencies for operation
    required ProjectDatabaseService projectDatabaseService,
    required TimelineLogicService timelineLogicService,
    required PreviewHttpService previewHttpService,
    required TimelineNavigationViewModel timelineNavViewModel,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    // Optional: For deserialization, to restore state
    ClipModel? originalClipState,
    Map<int, ClipModel>? originalNeighborStates,
    List<ClipModel>? deletedNeighborsState,
  })  : _projectDatabaseService = projectDatabaseService,
        _timelineLogicService = timelineLogicService,
        _previewHttpService = previewHttpService,
        _timelineNavViewModel = timelineNavViewModel,
        _clipsNotifier = clipsNotifier,
        _originalClipState = originalClipState,
        _originalNeighborStates = originalNeighborStates,
        _deletedNeighborsState = deletedNeighborsState;


  @override
  Future<void> execute() async {
    // Ensure this method is idempotent or correctly captures state if called multiple times (e.g., redo)
    // If _originalClipState is already set, it means we are likely in a "redo" scenario,
    // and the "before" state is already captured.
    // However, the current execute logic re-calculates everything.
    // For a clean redo, we might need to store the "after" state as well.

    final bool isRedo = _originalClipState != null;
    if (!isRedo) {
      // This is a fresh execution, capture the "before" state.
      // The existing logic inside execute() already does a good job of this
      // by populating _originalClipState, _neighborUpdatesForUndo (which will become _originalNeighborStates),
      // and _neighborsDeletedForUndo (which will become _deletedNeighborsState).
    }


    logger.logInfo(
      '[MoveClipCommand] Executing: clipId=$clipId, newTrackId=$newTrackId, newStartTimeMs=$newStartTimeOnTrackMs',
      _logTag,
    );

    // Make a mutable, sorted copy of currentClips to ensure consistent input for TimelineLogicService
    final List<ClipModel> currentClips = List<ClipModel>.from(_clipsNotifier.value);
    currentClips.sort((a, b) {
        int trackCompare = a.trackId.compareTo(b.trackId);
        if (trackCompare != 0) return trackCompare;
        return a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs);
    });

    final clipToMove = currentClips.firstWhereOrNull(
      (c) => c.databaseId == clipId,
    );

    if (clipToMove == null) {
      logger.logError(
        '[MoveClipCommand] Clip $clipId not found in provided clips list',
        _logTag,
      );
      throw Exception('Clip $clipId not found for moving');
    }

    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[MoveClipCommand] Clip DAO not initialized', _logTag);
      throw Exception('Clip DAO not initialized');
    }

    // Capture original states if this is the first execution
    if (!isRedo) {
      _originalClipState = clipToMove.copyWith();
      _originalNeighborStates = {};
      _deletedNeighborsState = [];
    }
    // else, _originalClipState etc., are already populated from fromJson or previous execute.

    final int newEndTimeMs =
        newStartTimeOnTrackMs + clipToMove.durationOnTrackMs; // Duration of the clip being moved

    // Clear states for "after" execute, to be populated
    _movedClipStateAfterExecute = null;
    _updatedNeighborStatesAfterExecute = {};

    try {
      final placementResult = _timelineLogicService.prepareClipPlacement(
        clips: currentClips, // Use current clips from notifier for calculation
        clipId: clipId,
        trackId: newTrackId,
        type: clipToMove.type,
        sourcePath: clipToMove.sourcePath,
        sourceDurationMs: clipToMove.sourceDurationMs,
        startTimeOnTrackMs: newStartTimeOnTrackMs,
        endTimeOnTrackMs: newEndTimeMs,
        startTimeInSourceMs: clipToMove.startTimeInSourceMs,
        endTimeInSourceMs: clipToMove.endTimeInSourceMs,
      );

      if (!placementResult['success']) {
        throw Exception('prepareClipPlacement failed during move command');
      }

      final List<Map<String, dynamic>> neighborUpdates = List.from(
        placementResult['clipUpdates'],
      );
      final List<int> neighborsToDelete = List.from(
        placementResult['clipsToRemove'],
      );
      final Map<String, dynamic> mainClipUpdateData = Map.from(
        placementResult['newClipData'],
      );

      logger.logDebug('[MoveClipCommand] Applying DB updates...', _logTag);

      for (final update in neighborUpdates) {
        final int neighborId = update['id'];
        final Map<String, dynamic> fieldsToUpdate = Map.from(update['fields']);
        
        if (!isRedo) { // Only capture original state on first execute
            final originalNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
            if (originalNeighbor != null) {
                _originalNeighborStates![neighborId] = originalNeighbor.copyWith();
            }
        }
        
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighborId,
          fieldsToUpdate,
          log: false, // Handled by UndoRedoService
        );
      }

      for (final int neighborId in neighborsToDelete) {
        if (!isRedo) { // Only capture original state on first execute
            final deletedNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
            if (deletedNeighbor != null) {
                _deletedNeighborsState!.add(deletedNeighbor.copyWith());
            }
        }
        await _projectDatabaseService.clipDao!.deleteClip(neighborId);
      }
      
      // Update the main clip
      await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
        'trackId': mainClipUpdateData['trackId'],
        'startTimeOnTrackMs': mainClipUpdateData['startTimeOnTrackMs'],
        'endTimeOnTrackMs': mainClipUpdateData['endTimeOnTrackMs'],
        'startTimeInSourceMs': mainClipUpdateData['startTimeInSourceMs'],
        'endTimeInSourceMs': mainClipUpdateData['endTimeInSourceMs'],
      }, log: false); // Log handled by UndoRedoService

      logger.logDebug('[MoveClipCommand] Updating ViewModel state...', _logTag);
      
      // The placementResult['updatedClips'] contains ClipModel instances reflecting the new state.
      // We need to store these for `newData` serialization.
      final List<ClipModel> updatedClipModels = List<ClipModel>.from(placementResult['updatedClips']);
      // _clipsNotifier.value = updatedClipModels; // Update UI - Old way
      di<TimelineStateViewModel>().setClips(updatedClipModels); // New way

      // Store the "after" states for serialization
      _movedClipStateAfterExecute = updatedClipModels.firstWhereOrNull((c) => c.databaseId == clipId)?.copyWith();
      for (final updatedClipModel in updatedClipModels) {
        if (updatedClipModel.databaseId != clipId && neighborUpdates.any((nu) => nu['id'] == updatedClipModel.databaseId)) {
          _updatedNeighborStatesAfterExecute![updatedClipModel.databaseId!] = updatedClipModel.copyWith();
        }
      }


      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug('[MoveClipCommand] Timeline paused, fetching frame via HTTP...', _logTag);
        // Pass the current frame from the navigation view model
        final frameToRefresh = _timelineNavViewModel.currentFrame;
        logger.logDebug('[MoveClipCommand] Attempting to refresh frame $frameToRefresh via HTTP', _logTag);
        await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
      }

      logger.logInfo(
        '[MoveClipCommand] Successfully executed move for clip $clipId',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        '[MoveClipCommand] Error executing move for clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      '[MoveClipCommand] Undoing move for clipId=$clipId',
      _logTag,
    );
    if (_originalClipState == null || _originalNeighborStates == null || _deletedNeighborsState == null) {
      logger.logError(
        '[MoveClipCommand] Cannot undo: Original state not fully captured or command not executed yet.',
        _logTag,
      );
      return;
    }
    if (_projectDatabaseService.clipDao == null) {
      logger.logError(
        '[MoveClipCommand] Clip DAO not initialized for undo',
        _logTag,
      );
      throw Exception('Clip DAO not initialized for undo');
    }

    try {
      logger.logDebug('[MoveClipCommand][Undo] Restoring DB state...', _logTag);

      // Restore the main clip
      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        _originalClipState!.toDbCompanion().toColumns(true), // Use toColumns for full update
        log: false, // Handled by UndoRedoService
      );

      // Restore updated neighbors
      for (final entry in _originalNeighborStates!.entries) {
        final neighborId = entry.key;
        final originalNeighborState = entry.value;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighborId,
          originalNeighborState.toDbCompanion().toColumns(true),
          log: false,
        );
      }

      // Re-insert deleted neighbors
      for (final deletedNeighborState in _deletedNeighborsState!) {
        await _projectDatabaseService.clipDao!.insertClip(deletedNeighborState.toDbCompanion());
      }

      // After DB changes, refresh the clipsNotifier to reflect the undone state.
      // This requires fetching all clips again or carefully reconstructing the list.
      // For simplicity, let's assume a full refresh mechanism exists or will be added.
      // A more targeted update would be better for performance.
      // For now, we'll rely on whatever mechanism updates clipsNotifier upon DB changes.
      // If direct update is needed:
      // Accessing 'clips' table directly from the dao.
      // Reconstruct the clips list for the UI notifier more precisely.
      // Start with clips that were not directly involved in this command's execution.
      final Set<int> affectedClipIds = {_originalClipState!.databaseId!};
      _originalNeighborStates?.keys.forEach(affectedClipIds.add);
      // Note: _deletedNeighborsState contains clips that were deleted by execute(),
      // so they wouldn't be in the current _clipsNotifier.value right before this update.

      List<ClipModel> newClipsList = _clipsNotifier.value
          .where((clip) => clip.databaseId != null && !affectedClipIds.contains(clip.databaseId!))
          .toList();

      // Add the main clip in its original state
      if (_originalClipState != null) {
        newClipsList.add(_originalClipState!.copyWith()); // Use copyWith for safety
      }

      // Add original neighbor states
      _originalNeighborStates?.forEach((id, originalNeighbor) {
        newClipsList.add(originalNeighbor.copyWith()); // Use copyWith for safety
      });

      // Add back deleted neighbors
      _deletedNeighborsState?.forEach((deletedNeighbor) {
        newClipsList.add(deletedNeighbor.copyWith()); // Use copyWith for safety
      });

      // Sort the list to maintain timeline order (by track, then by start time)
      newClipsList.sort((a, b) {
        int trackCompare = a.trackId.compareTo(b.trackId);
        if (trackCompare != 0) return trackCompare;
        return a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs);
      });
      // _clipsNotifier.value = newClipsList; // Old way
      di<TimelineStateViewModel>().setClips(newClipsList); // New way


      logger.logDebug(
        '[MoveClipCommand][Undo] ViewModel state updated after undo.',
        _logTag,
      );

      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug('[MoveClipCommand][Undo] Timeline paused, fetching frame via HTTP...', _logTag);
        // Pass the current frame from the navigation view model
        final frameToRefresh = _timelineNavViewModel.currentFrame;
        logger.logDebug('[MoveClipCommand][Undo] Attempting to refresh frame $frameToRefresh via HTTP', _logTag);
        await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
      }

      logger.logInfo(
        '[MoveClipCommand] Successfully undone move for clip $clipId',
        _logTag,
      );

      // Clear the "after execute" states as they are now invalid
      _movedClipStateAfterExecute = null;
      _updatedNeighborStatesAfterExecute = null;
      // _originalClipState and others remain, as they are needed if we "redo" this command.
    } catch (e) {
      logger.logError(
        '[MoveClipCommand] Error undoing move for clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'clipId': clipId,
      'newTrackId': newTrackId,
      'newStartTimeOnTrackMs': newStartTimeOnTrackMs,
      'originalClipState': _originalClipState?.toJson(),
      'originalNeighborStates': _originalNeighborStates?.map((key, value) => MapEntry(key.toString(), value.toJson())),
      'deletedNeighborsState': _deletedNeighborsState?.map((clip) => clip.toJson()).toList(),
      // "After" state for redo
      'movedClipStateAfterExecute': _movedClipStateAfterExecute?.toJson(),
      'updatedNeighborStatesAfterExecute': _updatedNeighborStatesAfterExecute?.map((key, value) => MapEntry(key.toString(), value.toJson())),
    };
  }

  @override
  ChangeLog toChangeLog(String entityId) {
    // entityId for MoveClipCommand is the clipId being moved.
    final fullJson = toJson();
    
    // oldData: Represents the state *before* the command executed.
    // This is what `undo` needs to restore.
    final Map<String, dynamic> oldData = {
      'clipId': fullJson['clipId'], // Keep for context if needed
      'originalClipState': fullJson['originalClipState'],
      'originalNeighborStates': fullJson['originalNeighborStates'],
      'deletedNeighborsState': fullJson['deletedNeighborsState'],
    };

    // newData: Represents the state *after* the command executed,
    // or the parameters needed to re-execute it.
    // For re-execution, we need the input params and the resulting state.
    final Map<String, dynamic> newData = {
      'clipId': fullJson['clipId'],
      'newTrackId': fullJson['newTrackId'],
      'newStartTimeOnTrackMs': fullJson['newStartTimeOnTrackMs'],
      'movedClipStateAfterExecute': fullJson['movedClipStateAfterExecute'],
      'updatedNeighborStatesAfterExecute': fullJson['updatedNeighborStatesAfterExecute'],
      // We also need to know which neighbors were deleted to correctly redo the deletion.
      // The `deletedNeighborsState` contains their original state, but for redo, we just need their IDs.
      'deletedNeighborIds': _deletedNeighborsState?.map((c) => c.databaseId).toList(),
    };

    return ChangeLog(
      id: 0, // Drift will auto-increment
      entity: 'clips', // The table name this log entry pertains to
      entityId: entityId, // clipId.toString()
      action: commandType, // 'moveClip'
      oldData: jsonEncode(oldData),
      newData: jsonEncode(newData),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Factory for deserialization, aligning with CommandFromJsonFactory
  // The commandData map contains 'newData', 'oldData', and 'entityId'
  factory MoveClipCommand.fromJson(
      ProjectDatabaseService projectDatabaseService, // Passed by UndoRedoService
      Map<String, dynamic> commandData) {
    
    final Map<String, dynamic>? oldData = commandData['oldData'] as Map<String, dynamic>?;
    final Map<String, dynamic> newData = commandData['newData'] as Map<String, dynamic>;
    // final String entityId = commandData['entityId'] as String; // clipId as string

    // --- Extract data for "original" state (for undo) from oldData ---
    ClipModel? originalClipState;
    if (oldData?['originalClipState'] != null) {
      originalClipState = ClipModel.fromJson(oldData!['originalClipState'] as Map<String, dynamic>);
    }

    Map<int, ClipModel>? originalNeighborStates;
    if (oldData?['originalNeighborStates'] != null) {
      originalNeighborStates = (oldData!['originalNeighborStates'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), ClipModel.fromJson(value as Map<String, dynamic>)),
      );
    }

    List<ClipModel>? deletedNeighborsState;
    if (oldData?['deletedNeighborsState'] != null) {
      deletedNeighborsState = (oldData!['deletedNeighborsState'] as List<dynamic>)
          .map((item) => ClipModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    
    // --- Extract data for "new" state (parameters for execute/redo) from newData ---
    final int clipId = newData['clipId'] as int;
    final int newTrackId = newData['newTrackId'] as int;
    final int newStartTimeOnTrackMs = newData['newStartTimeOnTrackMs'] as int;

    // For re-populating "after execute" states if needed for consistency, though execute() recalculates.
    ClipModel? movedClipStateAfterExecute;
    if (newData['movedClipStateAfterExecute'] != null) {
        movedClipStateAfterExecute = ClipModel.fromJson(newData['movedClipStateAfterExecute'] as Map<String, dynamic>);
    }

    Map<int, ClipModel>? updatedNeighborStatesAfterExecute;
    if (newData['updatedNeighborStatesAfterExecute'] != null) {
        updatedNeighborStatesAfterExecute = (newData['updatedNeighborStatesAfterExecute'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(int.parse(key), ClipModel.fromJson(value as Map<String, dynamic>)),
        );
    }

    // --- Retrieve dependencies using di ---
    final timelineLogicService = di<TimelineLogicService>();
    final previewHttpService = di<PreviewHttpService>();
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    final clipsNotifier = di<TimelineViewModel>().clipsNotifier;


    final command = MoveClipCommand(
      clipId: clipId,
      newTrackId: newTrackId,
      newStartTimeOnTrackMs: newStartTimeOnTrackMs,
      projectDatabaseService: projectDatabaseService, // Passed in
      timelineLogicService: timelineLogicService, // From di
      previewHttpService: previewHttpService, // From di
      timelineNavViewModel: timelineNavViewModel, // From di
      clipsNotifier: clipsNotifier, // From di
      originalClipState: originalClipState, // For undo
      originalNeighborStates: originalNeighborStates, // For undo
      deletedNeighborsState: deletedNeighborsState, // For undo
    );

    // Restore "after execute" states to the command instance,
    // these were captured by toJson and stored in newData.
    command._movedClipStateAfterExecute = movedClipStateAfterExecute;
    command._updatedNeighborStatesAfterExecute = updatedNeighborStatesAfterExecute;
    
    return command;
  }
}
