import 'package:drift/drift.dart' as drift;
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import '../timeline_viewmodel.dart';
import '../timeline_state_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';
import '../../services/undo_redo_service.dart';

class AddClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel clipData;
  final int trackId;
  final int startTimeOnTrackMs;

  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  int? _insertedClipId;
  List<ClipModel>? _originalNeighborStates;
  List<int>? _removedNeighborIds;

  static const _logTag = "AddClipCommand";

  AddClipCommand({
    required this.vm,
    required this.clipData,
    required this.trackId,
    required this.startTimeOnTrackMs,
  });

  @override
  Future<void> execute() async {
    if (_databaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return;
    }

    final initialEndTimeOnTrackMs =
        startTimeOnTrackMs + clipData.durationInSourceMs;
    final sourceDurationMs = clipData.sourceDurationMs;

    logger.logInfo(
      '[AddClipCommand] Preparing placement: track=$trackId, startTrack=$startTimeOnTrackMs, endTrack=$initialEndTimeOnTrackMs, startSource=${clipData.startTimeInSourceMs}, endSource=${clipData.endTimeInSourceMs}, sourceDuration=$sourceDurationMs',
      _logTag,
    );

    final placement = _timelineLogicService.prepareClipPlacement(
      clips: _stateViewModel.clips,
      clipId: null,
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      sourceDurationMs: sourceDurationMs,
      startTimeOnTrackMs: startTimeOnTrackMs,
      endTimeOnTrackMs: initialEndTimeOnTrackMs,
      startTimeInSourceMs: clipData.startTimeInSourceMs,
      endTimeInSourceMs: clipData.endTimeInSourceMs,
    );

    if (!placement['success']) {
      logger.logError('Failed to calculate clip placement', _logTag);
      return;
    }

    final currentClips = _stateViewModel.clips;
    _originalNeighborStates =
        (placement['clipUpdates'] as List<Map<String, dynamic>>)
            .map<ClipModel?>((updateMap) {
              try {
                return currentClips.firstWhere(
                  (c) => c.databaseId == updateMap['id'],
                );
              } catch (_) {
                return null;
              }
            })
            .where((c) => c != null)
            .map((c) => c!.copyWith())
            .toList();
    _removedNeighborIds = List<int>.from(
      placement['clipsToRemove'] as List<int>,
    );

    logger.logInfo(
      '[AddClipCommand] Planned Neighbor Updates: ${placement['clipUpdates']}',
      _logTag,
    );
    logger.logInfo(
      '[AddClipCommand] Planned Neighbor Removals: ${placement['clipsToRemove']}',
      _logTag,
    );

    logger.logInfo(
      '[AddClipCommand] Applying DB changes: updates=${placement['clipUpdates'].length}, removals=${placement['clipsToRemove'].length}',
      _logTag,
    );

    for (final update in placement['clipUpdates']) {
      await _databaseService.clipDao!.updateClipFields(
        update['id'],
        update['fields'],
      );
    }

    for (final id in _removedNeighborIds!) {
      await _databaseService.clipDao!.deleteClip(id);
    }

    final newClipDataMap = placement['newClipData'] as Map<String, dynamic>;
    logger.logInfo(
      '[AddClipCommand] Inserting new clip: $newClipDataMap',
      _logTag,
    );

    _insertedClipId = await _databaseService.clipDao!.insertClip(
      project_db.ClipsCompanion(
        trackId: drift.Value(trackId),
        name: drift.Value(clipData.name),
        type: drift.Value(clipData.type.name),
        sourcePath: drift.Value(clipData.sourcePath),
        sourceDurationMs: drift.Value(newClipDataMap['sourceDurationMs']),
        startTimeOnTrackMs: drift.Value(newClipDataMap['startTimeOnTrackMs']),
        endTimeOnTrackMs: drift.Value(newClipDataMap['endTimeOnTrackMs']),
        startTimeInSourceMs: drift.Value(newClipDataMap['startTimeInSourceMs']),
        endTimeInSourceMs: drift.Value(newClipDataMap['endTimeInSourceMs']),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    logger.logInfo(
      '[AddClipCommand] Inserted new clip with ID: $_insertedClipId',
      _logTag,
    );

    List<ClipModel> finalUpdatedClips = List<ClipModel>.from(
      placement['updatedClips'],
    );

    final newClipIndex = finalUpdatedClips.indexWhere(
      (clip) =>
          clip.databaseId == null &&
          clip.sourcePath == clipData.sourcePath &&
          clip.startTimeOnTrackMs == newClipDataMap['startTimeOnTrackMs'],
    );

    if (newClipIndex != -1 && _insertedClipId != null) {
      final newClipWithId = finalUpdatedClips[newClipIndex].copyWith(
        databaseId: drift.Value(_insertedClipId),
      );
      finalUpdatedClips[newClipIndex] = newClipWithId;
      logger.logInfo(
        '[AddClipCommand] Updated new clip ID in optimistic list: $_insertedClipId',
        _logTag,
      );
    } else {
      logger.logWarning(
        '[AddClipCommand] Could not find newly inserted clip in optimistic list to update its ID.',
        _logTag,
      );
    }

    await _stateViewModel.refreshClips();
    logger.logInfo(
      '[AddClipCommand] Triggered refresh in State ViewModel.',
      _logTag,
    );

    final UndoRedoService undoRedoService = di<UndoRedoService>();
    await undoRedoService.init();
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      '[AddClipCommand] Undoing add clip: $_insertedClipId',
      _logTag,
    );
    if (_insertedClipId == null ||
        _originalNeighborStates == null ||
        _removedNeighborIds == null) {
      logger.logError('Cannot undo AddClipCommand: Missing state', _logTag);
      return;
    }
    if (_databaseService.clipDao == null) {
      logger.logError(
        'Cannot undo AddClipCommand: Clip DAO not initialized',
        _logTag,
      );
      return;
    }

    try {
      await _databaseService.clipDao!.deleteClip(_insertedClipId!);

      for (final originalNeighbor in _originalNeighborStates!) {
        logger.logInfo(
          '[AddClipCommand] Restoring updated neighbor: ${originalNeighbor.databaseId}',
          _logTag,
        );
        await _databaseService.clipDao!
            .updateClipFields(originalNeighbor.databaseId!, {
              'trackId': originalNeighbor.trackId,
              'startTimeOnTrackMs': originalNeighbor.startTimeOnTrackMs,
              'endTimeOnTrackMs': originalNeighbor.endTimeOnTrackMs,
              'startTimeInSourceMs': originalNeighbor.startTimeInSourceMs,
              'endTimeInSourceMs': originalNeighbor.endTimeInSourceMs,
            });
      }

      for (final removedId in _removedNeighborIds!) {
        final originalRemovedNeighbor = _originalNeighborStates?.firstWhere(
          (c) => c.databaseId == removedId,
          orElse: () {
            logger.logError(
              "Cannot find original state for removed neighbor $removedId in captured undo state.",
              _logTag,
            );
            throw Exception(
              "Cannot find original state for removed neighbor $removedId",
            );
          },
        );

        if (originalRemovedNeighbor == null) continue;

        logger.logInfo(
          '[AddClipCommand] Restoring removed neighbor: $removedId',
          _logTag,
        );
        await _databaseService.clipDao!.insertClip(
          originalRemovedNeighbor.toDbCompanion(),
        );
      }

      await _stateViewModel.refreshClips();

      _insertedClipId = null;
      _originalNeighborStates = null;
      _removedNeighborIds = null;
      logger.logInfo('[AddClipCommand] Undo complete', _logTag);
    } catch (e, s) {
      logger.logError('[AddClipCommand] Error during undo: $e\n$s', _logTag);
    }
  }
}
