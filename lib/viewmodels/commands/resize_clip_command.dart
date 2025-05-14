import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/database/project_database.dart' show ChangeLog;
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

class ResizeClipCommand implements TimelineCommand, UndoableCommand {
  final int clipId;
  final String direction;
  final int newBoundaryFrame;

  // Dependencies
  final ProjectDatabaseService _projectDatabaseService;
  final TimelineLogicService _timelineLogicService;
  final ValueNotifier<List<ClipModel>> _clipsNotifier;

  // Core state
  // This is the state of the clip just before this command instance is supposed to act.
  // For a new user action, it's the pre-drag state.
  // For a command fromJson, it's the state that its 'oldData' represents (i.e., what undo should restore to).
  final ClipModel _initialClipState;

  // These store the "before" states that are logged and used for undo.
  // For the first execution, they are derived from _initialClipState and its context.
  // For deserialized commands, they are loaded from JSON's oldData.
  ClipModel? _persistedOldClipState;
  Map<int, ClipModel>? _persistedOldNeighborStates;
  List<ClipModel>? _persistedOldDeletedNeighborsState;

  // These store the "after" states resulting from execute(). Logged as newData.
  ClipModel? _stateAfterExecute;
  Map<int, ClipModel>? _neighborStatesAfterExecute;
  List<int>? _neighborIdsDeletedByExecute;


  static const String commandType = 'resizeClip';
  static const _logTag = "ResizeClipCommand";

  ResizeClipCommand({
    required this.clipId,
    required this.direction,
    required this.newBoundaryFrame,
    required ClipModel initialResolvedClipState, // This is the key: state before operation
    required ProjectDatabaseService projectDatabaseService,
    required TimelineLogicService timelineLogicService,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    // Optional: for fromJson to pass pre-loaded "old" states
    ClipModel? deserializedPersistedOldClipState,
    Map<int, ClipModel>? deserializedPersistedOldNeighborStates,
    List<ClipModel>? deserializedPersistedOldDeletedNeighborsState,
  })  : _initialClipState = initialResolvedClipState,
        _projectDatabaseService = projectDatabaseService,
        _timelineLogicService = timelineLogicService,
        _clipsNotifier = clipsNotifier,
        _persistedOldClipState = deserializedPersistedOldClipState,
        _persistedOldNeighborStates = deserializedPersistedOldNeighborStates,
        _persistedOldDeletedNeighborsState = deserializedPersistedOldDeletedNeighborsState,
        assert(
         direction == 'left' || direction == 'right',
         'Direction must be "left" or "right"',
       );

  @override
  Future<void> execute({bool isRedo = false}) async {
    // isRedo: true if called by UndoRedoService.redo()
    // If _persistedOldClipState is null, it's the first meaningful run for a new user action.
    // If _persistedOldClipState is not null, it means state was loaded (fromJson) or set by a previous run.
    final bool isFirstRunForUserAction = _persistedOldClipState == null && !isRedo;

    logger.logInfo(
      '[ResizeClipCommand] Executing (isRedo: $isRedo, isFirstRun: $isFirstRunForUserAction): clipId=$clipId, direction=$direction, newBoundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final currentClipsForContext = _clipsNotifier.value; // For finding neighbors
    
    final ClipModel baseClipForLogic;
    if (isFirstRunForUserAction) {
      _persistedOldClipState = _initialClipState.copyWith(); // Capture the true original state
      // Capture original neighbor states based on _initialClipState and currentClipsForContext
      _persistedOldNeighborStates = {};
      _persistedOldDeletedNeighborsState = [];
      // (Detailed neighbor capture logic would go here, finding neighbors of _initialClipState)
      // This part needs careful implementation to find neighbors correctly relative to _initialClipState.
      // For simplicity in this step, we're focusing on _persistedOldClipState.
      // A more robust neighbor capture would iterate currentClipsForContext and identify neighbors
      // of _initialClipState based on its trackId and times.
      baseClipForLogic = _initialClipState;
    } else {
      // This is a redo, or fromJson. _persistedOldClipState should be set.
      // The logic should operate on the state that the previous undo restored (which is _persistedOldClipState).
      if (_persistedOldClipState == null) {
         logger.logError('[ResizeClipCommand] Redo called but _persistedOldClipState is null.', _logTag);
         throw Exception('Invalid state for redo.');
      }
      baseClipForLogic = _persistedOldClipState!;
    }

    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[ResizeClipCommand] Clip DAO not initialized', _logTag);
      throw Exception('Clip DAO not initialized');
    }
    
    _stateAfterExecute = null;
    _neighborStatesAfterExecute = {};
    _neighborIdsDeletedByExecute = [];
    
    final originalStartTimeOnTrackMs = baseClipForLogic.startTimeOnTrackMs;
    final originalEndTimeOnTrackMs = baseClipForLogic.endTimeOnTrackMs;
    final originalStartTimeInSourceMs = baseClipForLogic.startTimeInSourceMs;
    final originalEndTimeInSourceMs = baseClipForLogic.endTimeInSourceMs;
    final sourceDurationMs = baseClipForLogic.sourceDurationMs;

    int targetStartTimeOnTrackMs = originalStartTimeOnTrackMs;
    int targetEndTimeOnTrackMs = originalEndTimeOnTrackMs;
    int targetStartTimeInSourceMs = originalStartTimeInSourceMs;
    int targetEndTimeInSourceMs = originalEndTimeInSourceMs;
    final newBoundaryMs = ClipModel.framesToMs(newBoundaryFrame);

    if (direction == 'left') {
      targetStartTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs = targetStartTimeOnTrackMs - originalStartTimeOnTrackMs;
      targetStartTimeInSourceMs = originalStartTimeInSourceMs + trackDeltaMs;
    } else { // 'right'
      targetEndTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs = targetEndTimeOnTrackMs - originalEndTimeOnTrackMs;
      targetEndTimeInSourceMs = originalEndTimeInSourceMs + trackDeltaMs;
    }

    // Clamp source times
    int finalStartTimeInSourceMs = targetStartTimeInSourceMs.clamp(0, sourceDurationMs);
    int finalEndTimeInSourceMs = targetEndTimeInSourceMs.clamp(finalStartTimeInSourceMs, sourceDurationMs);
    finalStartTimeInSourceMs = finalStartTimeInSourceMs.clamp(0, finalEndTimeInSourceMs); // Re-clamp start based on potentially adjusted end

    // Adjust track times based on clamped source times
    int finalStartTimeOnTrackMs;
    int finalEndTimeOnTrackMs;

    if (direction == 'left') {
      final sourceDeltaMs = finalStartTimeInSourceMs - originalStartTimeInSourceMs;
      finalStartTimeOnTrackMs = originalStartTimeOnTrackMs + sourceDeltaMs;
      finalEndTimeOnTrackMs = originalEndTimeOnTrackMs; // End of track remains fixed for left resize
    } else { // 'right'
      final sourceDeltaMs = finalEndTimeInSourceMs - originalEndTimeInSourceMs;
      finalStartTimeOnTrackMs = originalStartTimeOnTrackMs; // Start of track remains fixed for right resize
      finalEndTimeOnTrackMs = originalEndTimeOnTrackMs + sourceDeltaMs;
    }
    
    // Ensure minimum duration
    final minTrackDurationMs = ClipModel.framesToMs(1);
    if (finalEndTimeOnTrackMs - finalStartTimeOnTrackMs < minTrackDurationMs) {
      if (direction == 'left') {
        finalStartTimeOnTrackMs = finalEndTimeOnTrackMs - minTrackDurationMs;
      } else {
        finalEndTimeOnTrackMs = finalStartTimeOnTrackMs + minTrackDurationMs;
      }
    }
    final minSourceDurationMs = 1; 
    if (finalEndTimeInSourceMs - finalStartTimeInSourceMs < minSourceDurationMs && sourceDurationMs > 0) {
      finalEndTimeInSourceMs = (finalStartTimeInSourceMs + minSourceDurationMs).clamp(finalStartTimeInSourceMs, sourceDurationMs);
    } else if (sourceDurationMs == 0 && (finalStartTimeInSourceMs != 0 || finalEndTimeInSourceMs != 0)) {
      // Handle image/color clips (sourceDurationMs == 0) - their source times should always be 0
      finalStartTimeInSourceMs = 0;
      finalEndTimeInSourceMs = 0;
    }


    logger.logInfo(
      '[ResizeClipCommand] Final calculated values: Track[$finalStartTimeOnTrackMs-$finalEndTimeOnTrackMs], Source[$finalStartTimeInSourceMs-$finalEndTimeInSourceMs]',
      _logTag,
    );

    try {
      final placementResult = _timelineLogicService.prepareClipPlacement(
        clips: currentClipsForContext, // Use the full list for context
        clipId: clipId, // ID of the clip being resized
        trackId: baseClipForLogic.trackId, // Original track ID
        type: baseClipForLogic.type,
        sourcePath: baseClipForLogic.sourcePath,
        sourceDurationMs: sourceDurationMs, // Original source duration
        startTimeOnTrackMs: finalStartTimeOnTrackMs, // New calculated start time
        endTimeOnTrackMs: finalEndTimeOnTrackMs,   // New calculated end time
        startTimeInSourceMs: finalStartTimeInSourceMs, // New calculated source start
        endTimeInSourceMs: finalEndTimeInSourceMs,     // New calculated source end
      );

      if (!placementResult['success']) {
        throw Exception('prepareClipPlacement failed during resize command: ${placementResult['error']}');
      }

      // Validate all required data is present
      if (!placementResult.containsKey('clipUpdates') || 
          !placementResult.containsKey('clipsToRemove') ||
          !placementResult.containsKey('newClipData') ||
          !placementResult.containsKey('updatedClips')) {
        throw Exception('prepareClipPlacement returned incomplete data structure');
      }

      final List<Map<String, dynamic>> neighborUpdatesFromPlacement = List.from(placementResult['clipUpdates']);
      final List<int> neighborsToDeleteFromPlacement = List.from(placementResult['clipsToRemove']);
      
      // Add null check for newClipData
      if (placementResult['newClipData'] == null) {
        throw Exception('prepareClipPlacement did not return newClipData for the resized clip');
      }
      final Map<String, dynamic> resizedClipDataFromPlacement = placementResult['newClipData'];

      // During first run, capture actual original states of neighbors affected by placementResult
      if (isFirstRunForUserAction) {
        for (final updateMap in neighborUpdatesFromPlacement) {
          final int neighborId = updateMap['id'];
          if (neighborId == clipId) continue; // Don't capture self as neighbor here
          final originalNeighbor = currentClipsForContext.firstWhereOrNull((c) => c.databaseId == neighborId);
          if (originalNeighbor != null) {
            _persistedOldNeighborStates![neighborId] = originalNeighbor.copyWith();
          }
        }
        for (final int neighborIdToDelete in neighborsToDeleteFromPlacement) {
          final originalNeighbor = currentClipsForContext.firstWhereOrNull((c) => c.databaseId == neighborIdToDelete);
          if (originalNeighbor != null) {
            _persistedOldDeletedNeighborsState!.add(originalNeighbor.copyWith());
          }
        }
      }
      
      // Apply changes to DB
      // Prepare fields to update, ensuring all needed fields are included
      Map<String, dynamic> fieldsToUpdate = {
        'trackId': resizedClipDataFromPlacement['trackId'],
        'startTimeOnTrackMs': resizedClipDataFromPlacement['startTimeOnTrackMs'],
        'endTimeOnTrackMs': resizedClipDataFromPlacement['endTimeOnTrackMs'],
        'startTimeInSourceMs': resizedClipDataFromPlacement['startTimeInSourceMs'],
        'endTimeInSourceMs': resizedClipDataFromPlacement['endTimeInSourceMs']
      };
      
      // Handle type conversion - ensure it's a string
      if (resizedClipDataFromPlacement.containsKey('type')) {
        var typeValue = resizedClipDataFromPlacement['type'];
        if (typeValue is ClipType) {
          fieldsToUpdate['type'] = typeValue.name;
          logger.logInfo(
            '[ResizeClipCommand] Converted ClipType enum to string: ${fieldsToUpdate['type']}',
            _logTag,
          );
        } else if (typeValue is String) {
          fieldsToUpdate['type'] = typeValue;
        }
      }
      
      // Include other fields if present
      if (resizedClipDataFromPlacement.containsKey('sourcePath')) {
        fieldsToUpdate['sourcePath'] = resizedClipDataFromPlacement['sourcePath'] as String;
      }
      
      if (resizedClipDataFromPlacement.containsKey('sourceDurationMs')) {
        fieldsToUpdate['sourceDurationMs'] = resizedClipDataFromPlacement['sourceDurationMs'] as int;
      }
      
      logger.logInfo(
        '[ResizeClipCommand] Updating clip $clipId with fields: $fieldsToUpdate',
        _logTag,
      );
      
      try {
        // Log the original clip state for debugging
        final originalClip = await _projectDatabaseService.clipDao!.getClipById(clipId);
        if (originalClip != null) {
          logger.logInfo(
            '[ResizeClipCommand] Original clip state - startTime: ${originalClip.startTimeOnTrackMs}, endTime: ${originalClip.endTimeOnTrackMs}',
            _logTag,
          );
        }
        
        // Perform the update
        await _projectDatabaseService.clipDao!.updateClipFields(
          clipId,
          fieldsToUpdate,
        );
        
        // Log the new state to confirm it changed
        final updatedClip = await _projectDatabaseService.clipDao!.getClipById(clipId);
        if (updatedClip != null) {
          logger.logInfo(
            '[ResizeClipCommand] Updated clip state - startTime: ${updatedClip.startTimeOnTrackMs}, endTime: ${updatedClip.endTimeOnTrackMs}',
            _logTag,
          );
          
          // Check if values actually changed
          if (originalClip != null && 
              originalClip.startTimeOnTrackMs == updatedClip.startTimeOnTrackMs &&
              originalClip.endTimeOnTrackMs == updatedClip.endTimeOnTrackMs) {
            logger.logWarning(
              '[ResizeClipCommand] WARNING: Clip times did not change after update!',
              _logTag,
            );
          }
        }
        
        logger.logInfo(
          '[ResizeClipCommand] Successfully updated clip $clipId',
          _logTag,
        );
      } catch (e) {
        logger.logError(
          '[ResizeClipCommand] Failed to update clip fields: $e',
          _logTag,
        );
        rethrow;
      }
      
      _stateAfterExecute = ClipModel.fromDbData( // Reconstruct from DB or map? For now, assume fields are enough.
         (await _projectDatabaseService.clipDao!.getClipById(clipId))!,
      );


      for (final updateMap in neighborUpdatesFromPlacement) {
         final int neighborId = updateMap['id'];
         if (neighborId == clipId) continue; // Skip main clip, already handled
         await _projectDatabaseService.clipDao!.updateClipFields(
            neighborId,
            updateMap['fields'] as Map<String, dynamic>,
         );
         final updatedNeighborModel = ClipModel.fromDbData((await _projectDatabaseService.clipDao!.getClipById(neighborId))!);
         _neighborStatesAfterExecute![neighborId] = updatedNeighborModel;
      }

      for (final int idToRemove in neighborsToDeleteFromPlacement) {
        await _projectDatabaseService.clipDao!.deleteClip(idToRemove);
      }
      _neighborIdsDeletedByExecute = List.from(neighborsToDeleteFromPlacement);


      // Update UI state
      final List<ClipModel> updatedClipsForNotifier = List.from(currentClipsForContext);
      
      // Update the main clip
      int mainClipIdx = updatedClipsForNotifier.indexWhere((c) => c.databaseId == clipId);
      if (mainClipIdx != -1 && _stateAfterExecute != null) {
        updatedClipsForNotifier[mainClipIdx] = _stateAfterExecute!;
      } else if (_stateAfterExecute != null) {
         updatedClipsForNotifier.add(_stateAfterExecute!); // Should not happen if it existed
      }

      // Update neighbors
      _neighborStatesAfterExecute?.forEach((id, model) {
        int idx = updatedClipsForNotifier.indexWhere((c) => c.databaseId == id);
        if (idx != -1) {
          updatedClipsForNotifier[idx] = model;
        } else {
          updatedClipsForNotifier.add(model); // Should not happen if it existed
        }
      });

      // Remove deleted neighbors
      updatedClipsForNotifier.removeWhere((c) => _neighborIdsDeletedByExecute?.contains(c.databaseId) ?? false);
      
      di<TimelineStateViewModel>().setClips(updatedClipsForNotifier);

    } catch (e, s) {
      logger.logError('[ResizeClipCommand] Error during execute: $e\n$s', _logTag);
      // Consider how to handle partial failure: revert optimistic UI?
      // For now, rethrow to indicate command failure.
      rethrow;
    }
    logger.logInfo('[ResizeClipCommand] Execute finished successfully.', _logTag);
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[ResizeClipCommand] Undoing resize for clipId: $clipId', _logTag);
    if (_persistedOldClipState == null) {
      logger.logError('[ResizeClipCommand] Cannot undo: original state not available.', _logTag);
      return;
    }
    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[ResizeClipCommand] Clip DAO not initialized for undo.', _logTag);
      return;
    }

    try {
      // Restore the main clip
      await _projectDatabaseService.clipDao!.updateClipFields(
        _persistedOldClipState!.databaseId!,
        _clipModelToFieldMap(_persistedOldClipState!),
      );

      // Restore neighbors that were modified
      _persistedOldNeighborStates?.forEach((id, model) async {
        await _projectDatabaseService.clipDao!.updateClipFields(
          id,
          _clipModelToFieldMap(model),
        );
      });

      // Re-insert neighbors that were deleted
      _persistedOldDeletedNeighborsState?.forEach((model) async {
        // Ensure we don't re-insert if it somehow exists (e.g. bad state)
        final existing = await _projectDatabaseService.clipDao!.getClipById(model.databaseId!);
        if (existing == null) {
          await _projectDatabaseService.clipDao!.insertClip(model.toDbCompanion());
        } else {
           // If it exists, maybe update it to original state?
           await _projectDatabaseService.clipDao!.updateClipFields(model.databaseId!, _clipModelToFieldMap(model));
        }
      });

      // Delete neighbors that were created/pulled in by the execute operation
      // This requires knowing which clips were *newly* affected by `execute`.
      // The current `_neighborStatesAfterExecute` and `_neighborIdsDeletedByExecute`
      // describe the state *after* execute.
      // To correctly undo, we need to revert these specific changes.
      // This part is complex: if execute() pulled a clip to fill a gap, undo must push it back or delete it.
      // If execute() deleted a clip, undo re-inserts it (handled by _persistedOldDeletedNeighborsState).

      // For now, a simpler UI update based on persisted old states:
      List<ClipModel> currentClipsInNotifier = List.from(_clipsNotifier.value);
      List<ClipModel> finalNotifierList = [];

      // Add all clips from current notifier that are NOT the main clip or its original neighbors/deleted.
      final involvedIds = <int>{_persistedOldClipState!.databaseId!};
      _persistedOldNeighborStates?.keys.forEach(involvedIds.add);
      _persistedOldDeletedNeighborsState?.forEach((c) => involvedIds.add(c.databaseId!));
      
      currentClipsInNotifier.where((c) => !involvedIds.contains(c.databaseId)).forEach(finalNotifierList.add);

      // Add back the persisted states
      finalNotifierList.add(_persistedOldClipState!);
      if (_persistedOldNeighborStates != null) finalNotifierList.addAll(_persistedOldNeighborStates!.values);
      if (_persistedOldDeletedNeighborsState != null) finalNotifierList.addAll(_persistedOldDeletedNeighborsState!);
      
      di<TimelineStateViewModel>().setClips(finalNotifierList);
    } catch (e, s) {
      logger.logError('[ResizeClipCommand] Error during undo: $e\n$s', _logTag);
      rethrow;
    }
    logger.logInfo('[ResizeClipCommand] Undo finished successfully.', _logTag);
  }


  Map<String, dynamic> _clipModelToFieldMap(ClipModel clip) {
    return {
      'trackId': clip.trackId,
      'name': clip.name,
      'type': clip.type.name,
      'sourcePath': clip.sourcePath,
      'sourceDurationMs': clip.sourceDurationMs,
      'startTimeInSourceMs': clip.startTimeInSourceMs,
      'endTimeInSourceMs': clip.endTimeInSourceMs,
      'startTimeOnTrackMs': clip.startTimeOnTrackMs,
      'endTimeOnTrackMs': clip.endTimeOnTrackMs,
      'metadata': jsonEncode(clip.metadata),
      'previewPositionX': clip.previewPositionX,
      'previewPositionY': clip.previewPositionY,
      'previewWidth': clip.previewWidth,
      'previewHeight': clip.previewHeight,
    };
  }

  @override
  ChangeLog toChangeLog(String entityId) {
    if (_persistedOldClipState == null || _stateAfterExecute == null) {
      throw Exception('Cannot create ChangeLog: command state is incomplete.');
    }
    return ChangeLog(
      id: -1, // DB will assign
      entity: 'clip',
      entityId: entityId, // clipId.toString()
      action: commandType,
      oldData: jsonEncode({
        'originalClipState': _persistedOldClipState!.toJson(),
        'originalNeighborStates': _persistedOldNeighborStates?.map((key, value) => MapEntry(key.toString(), value.toJson())),
        'deletedNeighborsState': _persistedOldDeletedNeighborsState?.map((clip) => clip.toJson()).toList(),
      }),
      newData: jsonEncode({
        'resizedClipState': _stateAfterExecute!.toJson(),
        'updatedNeighborStates': _neighborStatesAfterExecute?.map((key, value) => MapEntry(key.toString(), value.toJson())),
        'deletedNeighborIdsDuringExecute': _neighborIdsDeletedByExecute, // IDs of clips deleted by execute
      }),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ResizeClipCommand.fromJson(
    ProjectDatabaseService projectDatabaseService,
    Map<String, dynamic> commandData,
  ) {
    final oldData = commandData['oldData'] as Map<String, dynamic>?;
    final newData = commandData['newData'] as Map<String, dynamic>;

    if (oldData == null || oldData['originalClipState'] == null) {
      throw Exception('Invalid JSON for ResizeClipCommand: missing oldData or originalClipState');
    }

    final ClipModel initialForConstructor = ClipModel.fromJson(oldData['originalClipState'] as Map<String, dynamic>);
    
    Map<int, ClipModel>? originalNeighborsForConstructor;
    if (oldData['originalNeighborStates'] != null) {
      originalNeighborsForConstructor = (oldData['originalNeighborStates'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), ClipModel.fromJson(value as Map<String, dynamic>)),
      );
    }

    List<ClipModel>? deletedNeighborsForConstructor;
    if (oldData['deletedNeighborsState'] != null) {
      deletedNeighborsForConstructor = (oldData['deletedNeighborsState'] as List<dynamic>)
          .map((item) => ClipModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    // Extract parameters from newData
    final clipId = newData['clipId'] as int? ?? initialForConstructor.databaseId!;
    final direction = newData['direction'] as String? ?? 'right'; // Default if not found
    int? newBoundaryFrame = newData['newBoundaryFrame'] as int?;

    if (newBoundaryFrame == null) {
      // Try to infer from resizedClipState if available
      if (newData['resizedClipState'] != null) {
        final resizedClip = ClipModel.fromJson(newData['resizedClipState'] as Map<String, dynamic>);
        newBoundaryFrame = ClipModel.msToFrames(
          direction == 'left' ? resizedClip.startTimeOnTrackMs : resizedClip.endTimeOnTrackMs
        );
      } else {
        // Use a reasonable default based on the original clip
        newBoundaryFrame = direction == 'left' 
            ? initialForConstructor.startFrame 
            : initialForConstructor.endFrame;
        logger.logWarning(
          "[ResizeClipCommand.fromJson] newBoundaryFrame not found in JSON, using original clip boundary.",
          _logTag
        );
      }
    }

    // Get dependencies from DI
    final timelineLogicService = di<TimelineLogicService>();
    final clipsNotifier = di<TimelineViewModel>().clipsNotifier;

    return ResizeClipCommand(
      clipId: clipId,
      direction: direction,
      newBoundaryFrame: newBoundaryFrame,
      initialResolvedClipState: initialForConstructor,
      projectDatabaseService: projectDatabaseService,
      timelineLogicService: timelineLogicService,
      clipsNotifier: clipsNotifier,
      deserializedPersistedOldClipState: initialForConstructor.copyWith(),
      deserializedPersistedOldNeighborStates: originalNeighborsForConstructor,
      deserializedPersistedOldDeletedNeighborsState: deletedNeighborsForConstructor,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    // This should serialize the command's identity and parameters,
    // plus the necessary "before" states for reconstruction by fromJson.
    return {
      'commandType': commandType,
      'clipId': clipId,
      'direction': direction,
      'newBoundaryFrame': newBoundaryFrame, // Critical parameter for re-execution logic
      'oldData': { // Consistent with toChangeLog's oldData structure
        'originalClipState': _persistedOldClipState?.toJson() ?? _initialClipState.toJson(),
        'originalNeighborStates': _persistedOldNeighborStates?.map((key, value) => MapEntry(key.toString(), value.toJson())),
        'deletedNeighborsState': _persistedOldDeletedNeighborsState?.map((clip) => clip.toJson()).toList(),
      },
      'newData': {
        'clipId': clipId,
        'direction': direction,
        'newBoundaryFrame': newBoundaryFrame,
        'resizedClipState': _stateAfterExecute?.toJson(),
        'updatedNeighborStates': _neighborStatesAfterExecute?.map((key, value) => MapEntry(key.toString(), value.toJson())),
        'deletedNeighborIds': _neighborIdsDeletedByExecute,
      },
    };
  }
}
