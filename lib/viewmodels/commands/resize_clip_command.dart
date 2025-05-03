import 'package:flutter/foundation.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';

class ResizeClipCommand implements TimelineCommand {
  final int clipId;
  final String direction;
  final int newBoundaryFrame;
  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final ValueNotifier<List<ClipModel>> clipsNotifier;

  ClipModel? _originalClipState;
  Map<int, Map<String, dynamic>>? _neighborUpdatesForUndo;
  List<ClipModel>? _neighborsDeletedForUndo;

  static const _logTag = "ResizeClipCommand";

  ResizeClipCommand({
    required this.clipId,
    required this.direction,
    required this.newBoundaryFrame,
    required this.clipsNotifier,
  }) : assert(
         direction == 'left' || direction == 'right',
         'Direction must be "left" or "right"',
       );

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[ResizeClipCommand] Executing: clipId=$clipId, direction=$direction, newBoundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final currentClips = clipsNotifier.value;
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

    _originalClipState = clipToResize.copyWith();
    _neighborUpdatesForUndo = {};
    _neighborsDeletedForUndo = [];

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
      logger.logWarning(
        '[ResizeClipCommand] Final track duration adjusted to minimum.',
        _logTag,
      );
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
      logger.logWarning(
        '[ResizeClipCommand] Final source duration adjusted to minimum.',
        _logTag,
      );
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
        'startTimeOnTrackMs': mainClipUpdateData['startTimeOnTrackMs'],
        'endTimeOnTrackMs': mainClipUpdateData['endTimeOnTrackMs'],
        'startTimeInSourceMs': mainClipUpdateData['startTimeInSourceMs'],
        'endTimeInSourceMs': mainClipUpdateData['endTimeInSourceMs'],
      }, log: true);

      logger.logDebug(
        '[ResizeClipCommand] Updating ViewModel state...',
        _logTag,
      );
      clipsNotifier.value = List<ClipModel>.from(
        placementResult['updatedClips'],
      );

      logger.logInfo(
        '[ResizeClipCommand] Successfully executed resize for clip $clipId',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        '[ResizeClipCommand] Error executing resize for clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      '[ResizeClipCommand] Undoing resize for clipId=$clipId',
      _logTag,
    );
    if (_originalClipState == null ||
        _neighborUpdatesForUndo == null ||
        _neighborsDeletedForUndo == null) {
      logger.logError(
        '[ResizeClipCommand] Cannot undo: Original state not fully saved',
        _logTag,
      );
      return;
    }
    if (_projectDatabaseService.clipDao == null) {
      logger.logError(
        '[ResizeClipCommand] Clip DAO not initialized for undo',
        _logTag,
      );
      throw Exception('Clip DAO not initialized for undo');
    }

    try {
      logger.logDebug(
        '[ResizeClipCommand][Undo] Restoring DB state...',
        _logTag,
      );

      await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
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
        '[ResizeClipCommand][Undo] ViewModel state should refresh via listeners.',
        _logTag,
      );

      logger.logInfo(
        '[ResizeClipCommand] Successfully undone resize for clip $clipId',
        _logTag,
      );

      _originalClipState = null;
      _neighborUpdatesForUndo = null;
      _neighborsDeletedForUndo = null;
    } catch (e) {
      logger.logError(
        '[ResizeClipCommand] Error undoing resize for clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }
}
