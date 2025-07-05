import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'package:flipedit/persistence/database/project_database.dart'
    show ChangeLog; // For toChangeLog
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
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
  final TimelineNavigationViewModel _timelineNavViewModel;
  final ValueNotifier<List<ClipModel>> _clipsNotifier; // Made private

  // State for undo/redo and serialization
  ClipModel? _originalClipState; // State of the main clip before move
  Map<int, ClipModel>?
  _originalNeighborStates; // Original states of updated neighbors
  List<ClipModel>?
  _deletedNeighborsState; // Original states of deleted neighbors

  ClipModel? _movedClipStateAfterExecute; // State of the main clip after move
  Map<int, ClipModel>?
  _updatedNeighborStatesAfterExecute; // State of neighbors after update
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
    required TimelineNavigationViewModel timelineNavViewModel,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    // Optional: For deserialization, to restore state
    ClipModel? originalClipState,
    Map<int, ClipModel>? originalNeighborStates,
    List<ClipModel>? deletedNeighborsState,
  }) : _projectDatabaseService = projectDatabaseService,
       _timelineLogicService = timelineLogicService,
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
    final List<ClipModel> currentClips = List<ClipModel>.from(
      _clipsNotifier.value,
    );
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
        newStartTimeOnTrackMs +
        clipToMove.durationOnTrackMs; // Duration of the clip being moved

    // Clear states for "after" execute, to be populated
    _movedClipStateAfterExecute = null;
    _updatedNeighborStatesAfterExecute = {};

    try {
      // First create a direct visual update for immediate feedback
      final List<ClipModel> visualUpdateClips = List<ClipModel>.from(
        currentClips,
      );
      // Remove the current version of the clip
      visualUpdateClips.removeWhere((c) => c.databaseId == clipId);
      // Add updated clip with new position
      final updatedVisualClip = clipToMove.copyWith(
        trackId: newTrackId,
        startTimeOnTrackMs: newStartTimeOnTrackMs,
        endTimeOnTrackMs: newEndTimeMs,
      );
      visualUpdateClips.add(updatedVisualClip);
      // Update UI immediately for responsiveness
      di<TimelineStateViewModel>().setClips(visualUpdateClips);

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

        if (!isRedo) {
          // Only capture original state on first execute
          final originalNeighbor = currentClips.firstWhereOrNull(
            (c) => c.databaseId == neighborId,
          );
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
        if (!isRedo) {
          // Only capture original state on first execute
          final deletedNeighbor = currentClips.firstWhereOrNull(
            (c) => c.databaseId == neighborId,
          );
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
      final List<ClipModel> updatedClipModels = List<ClipModel>.from(
        placementResult['updatedClips'],
      );
      // _clipsNotifier.value = updatedClipModels; // Update UI - Old way
      di<TimelineStateViewModel>().setClips(updatedClipModels); // New way

      // Store the "after" states for serialization
      _movedClipStateAfterExecute =
          updatedClipModels
              .firstWhereOrNull((c) => c.databaseId == clipId)
              ?.copyWith();
      for (final updatedClipModel in updatedClipModels) {
        if (updatedClipModel.databaseId != clipId &&
            neighborUpdates.any(
              (nu) => nu['id'] == updatedClipModel.databaseId,
            )) {
          _updatedNeighborStatesAfterExecute![updatedClipModel.databaseId!] =
              updatedClipModel.copyWith();
        }
      }

      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug(
          '[MoveClipCommand] Timeline paused, fetching frame via HTTP...',
          _logTag,
        );
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

    if (_originalClipState == null) {
      logger.logError(
        '[MoveClipCommand] Cannot undo, original clip state was not captured',
        _logTag,
      );
      return;
    }

    try {
      if (_originalClipState != null) {
        // Create a direct visual representation first
        final List<ClipModel> updatedClips = List<ClipModel>.from(
          _clipsNotifier.value,
        );

        // Remove the current version of the clip
        updatedClips.removeWhere((c) => c.databaseId == clipId);

        // Add the original clip state
        updatedClips.add(_originalClipState!.copyWith());

        // Update UI immediately with the correct visual position
        di<TimelineStateViewModel>().setClips(updatedClips);

        // Update the database directly with the EXACT original values to ensure complete reset
        await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
          'trackId': _originalClipState!.trackId,
          'startTimeOnTrackMs': _originalClipState!.startTimeOnTrackMs,
          'endTimeOnTrackMs': _originalClipState!.endTimeOnTrackMs,
          'startTimeInSourceMs': _originalClipState!.startTimeInSourceMs,
          'endTimeInSourceMs': _originalClipState!.endTimeInSourceMs,
        }, log: true);

        // One more visual update from db to ensure UI matches
        final freshClips = await _projectDatabaseService.getAllTimelineClips();
        di<TimelineStateViewModel>().setClips(freshClips);

        logger.logDebug(
          '[MoveClipCommand][Undo] HTTP frame fetch removed, video player will update.',
          _logTag,
        );
      }
    } catch (e) {
      logger.logError(
        '[MoveClipCommand] Error during final position fix: $e',
        _logTag,
      );
    }

    try {
      // Also, if any neighbors were updated during the original execution, restore their original states
      if (_originalNeighborStates != null) {
        for (final originalNeighborEntry in _originalNeighborStates!.entries) {
          final int neighborId = originalNeighborEntry.key;
          final ClipModel originalNeighbor = originalNeighborEntry.value;
          await _projectDatabaseService.clipDao!.updateClipFields(
            neighborId,
            {
              'trackId': originalNeighbor.trackId,
              'startTimeOnTrackMs': originalNeighbor.startTimeOnTrackMs,
              'endTimeOnTrackMs': originalNeighbor.endTimeOnTrackMs,
              'startTimeInSourceMs': originalNeighbor.startTimeInSourceMs,
              'endTimeInSourceMs': originalNeighbor.endTimeInSourceMs,
            },
            log: false, // Avoid too many logs for neighbors
          );
        }
      }

      // Moreover, if any neighbors were deleted during the execution, restore them
      if (_deletedNeighborsState != null) {
        for (final deletedNeighbor in _deletedNeighborsState!) {
          final reconstructedClip = ClipModel(
            databaseId: deletedNeighbor.databaseId,
            trackId: deletedNeighbor.trackId,
            name: deletedNeighbor.name,
            type: deletedNeighbor.type,
            sourcePath: deletedNeighbor.sourcePath,
            sourceDurationMs: deletedNeighbor.sourceDurationMs,
            startTimeInSourceMs: deletedNeighbor.startTimeInSourceMs,
            endTimeInSourceMs: deletedNeighbor.endTimeInSourceMs,
            startTimeOnTrackMs: deletedNeighbor.startTimeOnTrackMs,
            endTimeOnTrackMs: deletedNeighbor.endTimeOnTrackMs,
            previewPositionX: deletedNeighbor.previewPositionX,
            previewPositionY: deletedNeighbor.previewPositionY,
            previewWidth: deletedNeighbor.previewWidth,
            previewHeight: deletedNeighbor.previewHeight,
            effects: deletedNeighbor.effects,
            metadata: deletedNeighbor.metadata,
          );
          await _projectDatabaseService.clipDao!.insertClip(
            reconstructedClip.toDbCompanion(),
          );
        }
      }

      // Refresh UI with fresh clips after all DB operations
      final freshClips = await _projectDatabaseService.getAllTimelineClips();
      di<TimelineStateViewModel>().setClips(freshClips);

      logger.logInfo(
        '[MoveClipCommand] Successfully undone move for clip $clipId',
        _logTag,
      );
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
      'originalNeighborStates': _originalNeighborStates?.map(
        (key, value) => MapEntry(key.toString(), value.toJson()),
      ),
      'deletedNeighborsState':
          _deletedNeighborsState?.map((clip) => clip.toJson()).toList(),
      // "After" state for redo
      'movedClipStateAfterExecute': _movedClipStateAfterExecute?.toJson(),
      'updatedNeighborStatesAfterExecute': _updatedNeighborStatesAfterExecute
          ?.map((key, value) => MapEntry(key.toString(), value.toJson())),
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
      'updatedNeighborStatesAfterExecute':
          fullJson['updatedNeighborStatesAfterExecute'],
      // We also need to know which neighbors were deleted to correctly redo the deletion.
      // The `deletedNeighborsState` contains their original state, but for redo, we just need their IDs.
      'deletedNeighborIds':
          _deletedNeighborsState?.map((c) => c.databaseId).toList(),
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
    Map<String, dynamic> commandData,
  ) {
    final Map<String, dynamic>? oldData =
        commandData['oldData'] as Map<String, dynamic>?;
    final Map<String, dynamic> newData =
        commandData['newData'] as Map<String, dynamic>;
    // final String entityId = commandData['entityId'] as String; // clipId as string

    // --- Extract data for "original" state (for undo) from oldData ---
    ClipModel? originalClipState;
    if (oldData?['originalClipState'] != null) {
      originalClipState = ClipModel.fromJson(
        oldData!['originalClipState'] as Map<String, dynamic>,
      );
    }

    Map<int, ClipModel>? originalNeighborStates;
    if (oldData?['originalNeighborStates'] != null) {
      originalNeighborStates =
          (oldData!['originalNeighborStates'] as Map<String, dynamic>).map(
            (key, value) => MapEntry(
              int.parse(key),
              ClipModel.fromJson(value as Map<String, dynamic>),
            ),
          );
    }

    List<ClipModel>? deletedNeighborsState;
    if (oldData?['deletedNeighborsState'] != null) {
      deletedNeighborsState =
          (oldData!['deletedNeighborsState'] as List<dynamic>)
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
      movedClipStateAfterExecute = ClipModel.fromJson(
        newData['movedClipStateAfterExecute'] as Map<String, dynamic>,
      );
    }

    Map<int, ClipModel>? updatedNeighborStatesAfterExecute;
    if (newData['updatedNeighborStatesAfterExecute'] != null) {
      updatedNeighborStatesAfterExecute =
          (newData['updatedNeighborStatesAfterExecute'] as Map<String, dynamic>)
              .map(
                (key, value) => MapEntry(
                  int.parse(key),
                  ClipModel.fromJson(value as Map<String, dynamic>),
                ),
              );
    }

    // --- Retrieve dependencies using di ---
    final timelineLogicService = di<TimelineLogicService>();
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    final clipsNotifier = di<TimelineViewModel>().clipsNotifier;

    final command = MoveClipCommand(
      clipId: clipId,
      newTrackId: newTrackId,
      newStartTimeOnTrackMs: newStartTimeOnTrackMs,
      projectDatabaseService: projectDatabaseService, // Passed in
      timelineLogicService: timelineLogicService, // From di
      timelineNavViewModel: timelineNavViewModel, // From di
      clipsNotifier: clipsNotifier, // From di
      originalClipState: originalClipState, // For undo
      originalNeighborStates: originalNeighborStates, // For undo
      deletedNeighborsState: deletedNeighborsState, // For undo
    );

    // Restore "after execute" states to the command instance,
    // these were captured by toJson and stored in newData.
    command._movedClipStateAfterExecute = movedClipStateAfterExecute;
    command._updatedNeighborStatesAfterExecute =
        updatedNeighborStatesAfterExecute;

    return command;
  }
}
