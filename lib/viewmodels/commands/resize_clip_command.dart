import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/persistence/database/project_database.dart' show ChangeLog;
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_sync_service.dart';
import '../../services/preview_http_service.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

class ResizeClipCommand implements TimelineCommand, UndoableCommand {
  final int clipId;
  final String direction; // 'left' or 'right'
  final int newBoundaryFrame;

  // Dependencies
  final ProjectDatabaseService _projectDatabaseService;
  final TimelineLogicService _timelineLogicService;
  final PreviewSyncService _previewSyncService;
  final PreviewHttpService _previewHttpService;
  final TimelineNavigationViewModel _navigationViewModel;
  final ValueNotifier<List<ClipModel>> _clipsNotifier;

  // State for undo/redo and serialization
  ClipModel? _originalClipState;
  Map<int, ClipModel>? _originalNeighborStates;
  List<ClipModel>? _deletedNeighborsState;
  
  ClipModel? _resizedClipStateAfterExecute;
  Map<int, ClipModel>? _updatedNeighborStatesAfterExecute;

  static const String commandType = 'resizeClip';
  static const _logTag = "ResizeClipCommand";

  ResizeClipCommand({
    required this.clipId,
    required this.direction,
    required this.newBoundaryFrame,
    required ProjectDatabaseService projectDatabaseService,
    required TimelineLogicService timelineLogicService,
    required PreviewSyncService previewSyncService,
    required PreviewHttpService previewHttpService,
    required TimelineNavigationViewModel navigationViewModel,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    ClipModel? originalClipState, // Renamed for clarity in constructor
    Map<int, ClipModel>? originalNeighborStates, // Renamed
    List<ClipModel>? deletedNeighborsState, // Renamed
  })  : _projectDatabaseService = projectDatabaseService,
        _timelineLogicService = timelineLogicService,
        _previewSyncService = previewSyncService,
        _previewHttpService = previewHttpService,
        _navigationViewModel = navigationViewModel,
        _clipsNotifier = clipsNotifier,
        _originalClipState = originalClipState, // Assign to internal field
        _originalNeighborStates = originalNeighborStates, // Assign to internal field
        _deletedNeighborsState = deletedNeighborsState, // Assign to internal field
        assert(
         direction == 'left' || direction == 'right',
         'Direction must be "left" or "right"',
       );

  @override
  Future<void> execute() async {
    final bool isRedo = _originalClipState != null;

    logger.logInfo(
      '[ResizeClipCommand] Executing (isRedo: $isRedo): clipId=$clipId, direction=$direction, newBoundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final currentClips = _clipsNotifier.value;
    final clipToResize = currentClips.firstWhereOrNull(
      (c) => c.databaseId == clipId,
    );

    if (clipToResize == null) {
      logger.logError(
        '[ResizeClipCommand] Clip $clipId not found in provided clips list',
        _logTag,
      );
      throw Exception('Clip $clipId not found for resizing');
    }

    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[ResizeClipCommand] Clip DAO not initialized', _logTag);
      throw Exception('Clip DAO not initialized');
    }

    if (!isRedo) {
      _originalClipState = clipToResize.copyWith();
      _originalNeighborStates = {}; 
      _deletedNeighborsState = [];
    }

    _resizedClipStateAfterExecute = null;
    _updatedNeighborStatesAfterExecute = {};
    
    final originalStartTimeOnTrackMs = clipToResize.startTimeOnTrackMs;
    final originalEndTimeOnTrackMs = clipToResize.endTimeOnTrackMs;
    final originalStartTimeInSourceMs = clipToResize.startTimeInSourceMs;
    final originalEndTimeInSourceMs = clipToResize.endTimeInSourceMs;
    final sourceDurationMs = clipToResize.sourceDurationMs;

    int targetStartTimeOnTrackMs = originalStartTimeOnTrackMs;
    int targetEndTimeOnTrackMs = originalEndTimeOnTrackMs;
    int targetStartTimeInSourceMs = originalStartTimeInSourceMs;
    int targetEndTimeInSourceMs = originalEndTimeInSourceMs;
    final newBoundaryMs = ClipModel.framesToMs(newBoundaryFrame);

    if (direction == 'left') {
      targetStartTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs =
          targetStartTimeOnTrackMs - originalStartTimeOnTrackMs;
      targetStartTimeInSourceMs = originalStartTimeInSourceMs + trackDeltaMs;
    } else {
      targetEndTimeOnTrackMs = newBoundaryMs;
      final trackDeltaMs = targetEndTimeOnTrackMs - originalEndTimeOnTrackMs;
      targetEndTimeInSourceMs = originalEndTimeInSourceMs + trackDeltaMs;
    }

    int finalStartTimeInSourceMs = targetStartTimeInSourceMs.clamp(
      0,
      sourceDurationMs,
    );
    int finalEndTimeInSourceMs = targetEndTimeInSourceMs.clamp(
      finalStartTimeInSourceMs,
      sourceDurationMs,
    );
    finalStartTimeInSourceMs = finalStartTimeInSourceMs.clamp(
      0,
      finalEndTimeInSourceMs,
    );

    int finalStartTimeOnTrackMs;
    int finalEndTimeOnTrackMs;

    if (direction == 'left') {
      final sourceDeltaMs =
          finalStartTimeInSourceMs - originalStartTimeInSourceMs;
      finalStartTimeOnTrackMs = originalStartTimeOnTrackMs + sourceDeltaMs;
      finalEndTimeOnTrackMs = originalEndTimeOnTrackMs;
    } else {
      final sourceDeltaMs = finalEndTimeInSourceMs - originalEndTimeInSourceMs;
      finalStartTimeOnTrackMs = originalStartTimeOnTrackMs;
      finalEndTimeOnTrackMs = originalEndTimeOnTrackMs + sourceDeltaMs;
    }

    final minTrackDurationMs = ClipModel.framesToMs(1);
    if (finalEndTimeOnTrackMs - finalStartTimeOnTrackMs < minTrackDurationMs) {
      if (direction == 'left') {
        finalStartTimeOnTrackMs = finalEndTimeOnTrackMs - minTrackDurationMs;
      } else {
        finalEndTimeOnTrackMs = finalStartTimeOnTrackMs + minTrackDurationMs;
      }
    }
    final minSourceDurationMs = 1;
    if (finalEndTimeInSourceMs - finalStartTimeInSourceMs <
            minSourceDurationMs &&
        sourceDurationMs > 0) {
      finalEndTimeInSourceMs = (finalStartTimeInSourceMs + minSourceDurationMs)
          .clamp(finalStartTimeInSourceMs, sourceDurationMs);
    } else if (sourceDurationMs == 0) {
      finalStartTimeInSourceMs = 0;
      finalEndTimeInSourceMs = 0;
    }

    logger.logInfo(
      '[ResizeClipCommand] Final values: Track[$finalStartTimeOnTrackMs-$finalEndTimeOnTrackMs], Source[$finalStartTimeInSourceMs-$finalEndTimeInSourceMs]',
      _logTag,
    );

    try {
      final placementResult = _timelineLogicService.prepareClipPlacement(
        clips: currentClips,
        clipId: clipId,
        trackId: clipToResize.trackId,
        type: clipToResize.type,
        sourcePath: clipToResize.sourcePath,
        sourceDurationMs: sourceDurationMs,
        startTimeOnTrackMs: finalStartTimeOnTrackMs,
        endTimeOnTrackMs: finalEndTimeOnTrackMs,
        startTimeInSourceMs: finalStartTimeInSourceMs,
        endTimeInSourceMs: finalEndTimeInSourceMs,
      );

      if (!placementResult['success']) {
        throw Exception('prepareClipPlacement failed during resize command');
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

      logger.logDebug('[ResizeClipCommand] Applying DB updates...', _logTag);

      for (final update in neighborUpdates) {
        final int neighborId = update['id'];
        final Map<String, dynamic> fields = Map.from(update['fields']);
        final originalNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
        if (originalNeighbor != null && !isRedo) {
            _originalNeighborStates![neighborId] = originalNeighbor.copyWith();
        }
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighborId,
          fields,
          log: false, 
        );
      }

      for (final int neighborId in neighborsToDelete) {
        final deletedNeighbor = currentClips.firstWhereOrNull((c) => c.databaseId == neighborId);
        if (deletedNeighbor != null && !isRedo) {
          _deletedNeighborsState!.add(deletedNeighbor.copyWith());
        }
        await _projectDatabaseService.clipDao!.deleteClip(neighborId);
      }

      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        mainClipUpdateData,
        log: false, 
      );

      logger.logDebug('[ResizeClipCommand] Updating ViewModel state...', _logTag);
      final List<ClipModel> updatedClipModelsFromPlacement = List<ClipModel>.from(placementResult['updatedClips']);
      _clipsNotifier.value = updatedClipModelsFromPlacement; 

      _resizedClipStateAfterExecute = updatedClipModelsFromPlacement.firstWhereOrNull((c) => c.databaseId == clipId)?.copyWith();
      for (final updatedClipModel in updatedClipModelsFromPlacement) {
        if (updatedClipModel.databaseId != clipId && 
            neighborUpdates.any((nu) => nu['id'] == updatedClipModel.databaseId)) {
          _updatedNeighborStatesAfterExecute![updatedClipModel.databaseId!] = updatedClipModel.copyWith();
        }
      }
      
      // logger.logWarning('[ResizeClipCommand] Execute: Preview/Navigation updates are currently commented out. Verify method names.', _logTag);
      // await _previewSyncService.syncClipsToPreview([mainClipUpdateData['id'] as int]);
      // _previewHttpService.updatePlayer();
      // _navigationViewModel.recalculateContentDuration();
      
      logger.logInfo(
        '[ResizeClipCommand] Successfully performed resize for clip $clipId.',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        '[ResizeClipCommand] Error performing resize: $e',
        _logTag,
      );
      if (!isRedo && _originalClipState != null) {
        logger.logWarning('[ResizeClipCommand] Attempting basic rollback due to error during execute...', _logTag);
        try {
          await _projectDatabaseService.clipDao!.updateClipFields(
            _originalClipState!.databaseId!,
            _clipModelToFieldMap(_originalClipState!),
            log: false,
          );
          _originalNeighborStates?.forEach((id, model) async {
            await _projectDatabaseService.clipDao!.updateClipFields(id, _clipModelToFieldMap(model), log: false);
          });
          _deletedNeighborsState?.forEach((model) async {
            await _projectDatabaseService.clipDao!.insertClip(model.toCompanion()); // Assumes toCompanion exists
          });
          logger.logInfo('[ResizeClipCommand] Basic DB rollback completed.', _logTag);
        } catch (rollbackError) {
          logger.logError('[ResizeClipCommand] Error during basic rollback: $rollbackError', _logTag);
        }
      }
      rethrow;
    }
  }

  Map<String, dynamic> _clipModelToFieldMap(ClipModel clip) {
    return {
      'trackId': clip.trackId,
      'startTimeOnTrackMs': clip.startTimeOnTrackMs,
      'endTimeOnTrackMs': clip.endTimeOnTrackMs,
      'startTimeInSourceMs': clip.startTimeInSourceMs,
      'endTimeInSourceMs': clip.endTimeInSourceMs,
      'sourcePath': clip.sourcePath,
      'sourceDurationMs': clip.sourceDurationMs,
      'name': clip.name,
      'type': clip.type.name,
      'previewPositionX': clip.previewPositionX,
      'previewPositionY': clip.previewPositionY,
      'previewWidth': clip.previewWidth,
      'previewHeight': clip.previewHeight,
    };
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[ResizeClipCommand] Undoing resize for clip $clipId', _logTag);
    if (_originalClipState == null) {
      logger.logError('[ResizeClipCommand] Cannot undo: Original state not saved', _logTag);
      return;
    }
    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[ResizeClipCommand] Clip DAO not initialized for undo', _logTag);
      throw Exception('Clip DAO not initialized for undo');
    }

    try {
      await _projectDatabaseService.clipDao!.updateClipFields(
        _originalClipState!.databaseId!,
        _clipModelToFieldMap(_originalClipState!),
        log: false,
      );

      if (_originalNeighborStates != null) {
        for (final entry in _originalNeighborStates!.entries) {
          final originalNeighbor = entry.value;
          await _projectDatabaseService.clipDao!.updateClipFields(
            originalNeighbor.databaseId!,
            _clipModelToFieldMap(originalNeighbor),
            log: false,
          );
        }
      }

      if (_deletedNeighborsState != null) {
        for (final deletedClip in _deletedNeighborsState!) {
          await _projectDatabaseService.clipDao!.insertClip(deletedClip.toCompanion()); // Assumes toCompanion
        }
      }
      
      List<ClipModel> currentClipsInNotifier = List.from(_clipsNotifier.value);
      List<ClipModel> resultUiClips = [];
      Set<int?> processedIds = {};

      void addOrUpdateInUiList(ClipModel clip) {
        if (clip.databaseId == null) return;
        if (processedIds.contains(clip.databaseId)) { 
          int index = resultUiClips.indexWhere((c) => c.databaseId == clip.databaseId);
          if (index != -1) resultUiClips[index] = clip;
          return;
        }
        resultUiClips.add(clip);
        processedIds.add(clip.databaseId);
      }

      if (_originalClipState != null) addOrUpdateInUiList(_originalClipState!);
      _originalNeighborStates?.values.forEach(addOrUpdateInUiList);
      _deletedNeighborsState?.forEach(addOrUpdateInUiList);
      
      for (var existingClip in currentClipsInNotifier) {
          if (!processedIds.contains(existingClip.databaseId)) {
              // This clip was not part of the undo operation's direct restoration,
              // but it was in the notifier. We need to decide if it should remain.
              // If it was created by the 'execute' step, it should be removed.
              // This logic is complex. For now, we only add back the known original states.
              // A more robust solution might involve comparing with _resizedClipStateAfterExecute etc.
          }
      }
      // A simpler UI update for now:
      List<ClipModel> allClipsAfterUndo = [];
      if(_originalClipState != null) allClipsAfterUndo.add(_originalClipState!);
      if(_originalNeighborStates != null) allClipsAfterUndo.addAll(_originalNeighborStates!.values);
      if(_deletedNeighborsState != null) allClipsAfterUndo.addAll(_deletedNeighborsState!);
      
      // Get IDs of clips that were present *after* execute but are *not* in the restored set
      Set<int?> idsAfterExecute = <int?>{ // Explicitly type the set
        if (_resizedClipStateAfterExecute != null) _resizedClipStateAfterExecute!.databaseId,
        ...(_updatedNeighborStatesAfterExecute?.keys ?? const <int>[]), // Correctly handle null keys
      }.whereNotNull().toSet();

      Set<int?> idsInRestoredSet = allClipsAfterUndo.map((c) => c.databaseId).whereNotNull().toSet();
      Set<int?> idsToRemoveFromCurrentNotifier = idsAfterExecute.difference(idsInRestoredSet);

      List<ClipModel> finalNotifierList = List.from(currentClipsInNotifier);
      finalNotifierList.removeWhere((c) => idsToRemoveFromCurrentNotifier.contains(c.databaseId));
      
      // Add or update with restored clips
      for (var restoredClip in allClipsAfterUndo) {
        int index = finalNotifierList.indexWhere((c) => c.databaseId == restoredClip.databaseId);
        if (index != -1) {
          finalNotifierList[index] = restoredClip;
        } else {
          finalNotifierList.add(restoredClip);
        }
      }
      _clipsNotifier.value = finalNotifierList;

      // logger.logWarning('[ResizeClipCommand] Undo: Preview/Navigation updates are currently commented out.', _logTag);
      // await _previewSyncService.syncClipsToPreview([_originalClipState!.databaseId!]);
      // _previewHttpService.updatePlayer();
      // _navigationViewModel.recalculateContentDuration();

      logger.logInfo('[ResizeClipCommand] Successfully undone resize for clip $clipId', _logTag);
    } catch (e) {
      logger.logError('[ResizeClipCommand] Error undoing resize: $e', _logTag);
      rethrow;
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'oldData': {
        'originalClipState': _originalClipState?.toJson(),
        'originalNeighborStates': _originalNeighborStates?.map((key, value) => MapEntry(key.toString(), value.toJson())),
        'deletedNeighborsState': _deletedNeighborsState?.map((clip) => clip.toJson()).toList(),
      },
      'newData': {
        'clipId': clipId,
        'direction': direction,
        'newBoundaryFrame': newBoundaryFrame,
        'resizedClipStateAfterExecute': _resizedClipStateAfterExecute?.toJson(),
        'updatedNeighborStatesAfterExecute': _updatedNeighborStatesAfterExecute?.map((key, value) => MapEntry(key.toString(), value.toJson())),
      },
    };
  }

  @override
  ChangeLog toChangeLog(String entityId) { 
    final commandState = toJson();
    return ChangeLog(
      id: -1, 
      entity: 'clip',
      entityId: entityId, 
      action: ResizeClipCommand.commandType,
      oldData: jsonEncode(commandState['oldData']),
      newData: jsonEncode(commandState['newData']),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory ResizeClipCommand.fromJson(
      ProjectDatabaseService projectDatabaseService, 
      Map<String, dynamic> commandData) { 
    
    final oldData = commandData['oldData'] as Map<String, dynamic>? ?? {}; // Ensure not null
    final newData = commandData['newData'] as Map<String, dynamic>;

    ClipModel? originalClipStateFromJson;
    if (oldData['originalClipState'] != null) {
      originalClipStateFromJson = ClipModel.fromJson(oldData['originalClipState'] as Map<String, dynamic>);
    }

    Map<int, ClipModel>? originalNeighborStatesFromJson;
    if (oldData['originalNeighborStates'] != null) {
      originalNeighborStatesFromJson = (oldData['originalNeighborStates'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), ClipModel.fromJson(value as Map<String, dynamic>)),
      );
    }

    List<ClipModel>? deletedNeighborsStateFromJson;
    if (oldData['deletedNeighborsState'] != null) {
      deletedNeighborsStateFromJson = (oldData['deletedNeighborsState'] as List<dynamic>)
          .map((item) => ClipModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    final command = ResizeClipCommand(
      clipId: newData['clipId'] as int,
      direction: newData['direction'] as String,
      newBoundaryFrame: newData['newBoundaryFrame'] as int,
      projectDatabaseService: projectDatabaseService, 
      timelineLogicService: di<TimelineLogicService>(),
      previewSyncService: di<PreviewSyncService>(),
      previewHttpService: di<PreviewHttpService>(),
      navigationViewModel: di<TimelineNavigationViewModel>(),
      clipsNotifier: di<TimelineViewModel>().clipsNotifier, 
      originalClipState: originalClipStateFromJson,
      originalNeighborStates: originalNeighborStatesFromJson,
      deletedNeighborsState: deletedNeighborsStateFromJson,
    );

    if (newData['resizedClipStateAfterExecute'] != null) {
      command._resizedClipStateAfterExecute = ClipModel.fromJson(newData['resizedClipStateAfterExecute'] as Map<String, dynamic>);
    }
    if (newData['updatedNeighborStatesAfterExecute'] != null) {
      command._updatedNeighborStatesAfterExecute = (newData['updatedNeighborStatesAfterExecute'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), ClipModel.fromJson(value as Map<String, dynamic>)),
      );
    }
    return command;
  }
}
