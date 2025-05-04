import 'package:flutter/foundation.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_http_service.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class MoveClipCommand implements TimelineCommand {
  final int clipId;
  final int newTrackId;
  final int newStartTimeOnTrackMs;
  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final PreviewHttpService _previewHttpService = di<PreviewHttpService>();
  final TimelineNavigationViewModel _timelineNavViewModel = di<TimelineNavigationViewModel>();
  final ValueNotifier<List<ClipModel>> clipsNotifier;
 
  ClipModel? _originalClipState;
  Map<int, Map<String, dynamic>>? _neighborUpdatesForUndo;
  List<ClipModel>? _neighborsDeletedForUndo;

  static const _logTag = "MoveClipCommand";

  MoveClipCommand({
    required this.clipId,
    required this.newTrackId,
    required this.newStartTimeOnTrackMs,
    required this.clipsNotifier,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[MoveClipCommand] Executing: clipId=$clipId, newTrackId=$newTrackId, newStartTimeMs=$newStartTimeOnTrackMs',
      _logTag,
    );

    final currentClips = clipsNotifier.value;
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

    _originalClipState = clipToMove.copyWith();
    _neighborUpdatesForUndo = {};
    _neighborsDeletedForUndo = [];

    final int newEndTimeMs =
        newStartTimeOnTrackMs + clipToMove.durationOnTrackMs;

    try {
      final placementResult = _timelineLogicService.prepareClipPlacement(
        clips: currentClips,
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
        final Map<String, dynamic> fields = Map.from(update['fields']);
        final originalNeighbor = currentClips.firstWhereOrNull(
          (c) => c.databaseId == neighborId,
        );
        if (originalNeighbor != null) {
          final Map<String, dynamic> originalValues = {};
          fields.forEach((key, _) {
            switch (key) {
              case 'trackId':
                originalValues[key] = originalNeighbor.trackId;
                break;
              case 'startTimeOnTrackMs':
                originalValues[key] = originalNeighbor.startTimeOnTrackMs;
                break;
              case 'endTimeOnTrackMs':
                originalValues[key] = originalNeighbor.endTimeOnTrackMs;
                break;
              case 'startTimeInSourceMs':
                originalValues[key] = originalNeighbor.startTimeInSourceMs;
                break;
              case 'endTimeInSourceMs':
                originalValues[key] = originalNeighbor.endTimeInSourceMs;
                break;
            }
          });
          _neighborUpdatesForUndo![neighborId] = originalValues;
        }
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighborId,
          fields,
          log: false,
        );
      }

      for (final int neighborId in neighborsToDelete) {
        final deletedNeighbor = currentClips.firstWhereOrNull(
          (c) => c.databaseId == neighborId,
        );
        if (deletedNeighbor != null) {
          _neighborsDeletedForUndo!.add(deletedNeighbor.copyWith());
        }
        await _projectDatabaseService.clipDao!.deleteClip(neighborId);
      }

      await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
        'trackId': mainClipUpdateData['trackId'],
        'startTimeOnTrackMs': mainClipUpdateData['startTimeOnTrackMs'],
        'endTimeOnTrackMs': mainClipUpdateData['endTimeOnTrackMs'],
        'startTimeInSourceMs': mainClipUpdateData['startTimeInSourceMs'],
        'endTimeInSourceMs': mainClipUpdateData['endTimeInSourceMs'],
      }, log: true);

      logger.logDebug('[MoveClipCommand] Updating ViewModel state...', _logTag);
      clipsNotifier.value = List<ClipModel>.from(
        placementResult['updatedClips'],
      );

      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug('[MoveClipCommand] Timeline paused, fetching frame via HTTP...', _logTag);
        await _previewHttpService.fetchAndUpdateFrame();
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
    if (_originalClipState == null ||
        _neighborUpdatesForUndo == null ||
        _neighborsDeletedForUndo == null) {
      logger.logError(
        '[MoveClipCommand] Cannot undo: Original state not fully saved',
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

      await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
        'trackId': _originalClipState!.trackId,
        'startTimeOnTrackMs': _originalClipState!.startTimeOnTrackMs,
        'endTimeOnTrackMs': _originalClipState!.endTimeOnTrackMs,
        'startTimeInSourceMs': _originalClipState!.startTimeInSourceMs,
        'endTimeInSourceMs': _originalClipState!.endTimeInSourceMs,
      }, log: true);

      for (final neighborId in _neighborUpdatesForUndo!.keys) {
        final originalValues = _neighborUpdatesForUndo![neighborId]!;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighborId,
          originalValues,
          log: false,
        );
      }

      for (final deletedNeighbor in _neighborsDeletedForUndo!) {
        final companion = deletedNeighbor.toDbCompanion();
        await _projectDatabaseService.clipDao!.insertClip(companion);
      }

      logger.logDebug(
        '[MoveClipCommand][Undo] ViewModel state should refresh via listeners.',
        _logTag,
      );

      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug('[MoveClipCommand][Undo] Timeline paused, fetching frame via HTTP...', _logTag);
        await _previewHttpService.fetchAndUpdateFrame();
      }

      logger.logInfo(
        '[MoveClipCommand] Successfully undone move for clip $clipId',
        _logTag,
      );

      _originalClipState = null;
      _neighborUpdatesForUndo = null;
      _neighborsDeletedForUndo = null;
    } catch (e) {
      logger.logError(
        '[MoveClipCommand] Error undoing move for clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }
}
