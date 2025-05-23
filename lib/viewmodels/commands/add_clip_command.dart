import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import '../../services/commands/undoable_command.dart'; // Added import
import '../timeline_state_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import '../../models/enums/clip_type.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import '../../services/media_duration_service.dart';
import '../../services/canvas_dimensions_service.dart';
import 'package:watch_it/watch_it.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';

class AddClipCommand implements TimelineCommand, UndoableCommand {
  // Implement UndoableCommand
  final ClipModel
  clipDataInput; // Renamed to avoid confusion with internal state
  final int trackId;
  final int startTimeOnTrackMs;

  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();
  final MediaDurationService _mediaDurationService = di<MediaDurationService>();
  final CanvasDimensionsService _canvasDimensionsService =
      di<CanvasDimensionsService>();
  final TimelineNavigationViewModel _timelineNavViewModel =
      di<TimelineNavigationViewModel>();

  int? _insertedClipId;
  List<ClipModel>? _originalNeighborStates;
  List<int>? _removedNeighborIds;

  static const String commandType = 'insert'; // Match the error message
  static const _logTag = "AddClipCommand";

  AddClipCommand({
    required ClipModel clipData, // Use local var name
    required this.trackId,
    required this.startTimeOnTrackMs,
    // Fields for fromJson restoration
    int? insertedClipId,
    List<ClipModel>? originalNeighborStates,
    List<int>? removedNeighborIds,
  }) : clipDataInput = clipData {
    // Assign to new field
    // Restore state if provided (e.g., fromJson)
    if (insertedClipId != null) _insertedClipId = insertedClipId;
    if (originalNeighborStates != null)
      _originalNeighborStates = originalNeighborStates;
    if (removedNeighborIds != null) _removedNeighborIds = removedNeighborIds;
  }

  /// Validates the clip source duration and updates it if necessary
  Future<ClipModel> _validateClipSourceDuration(ClipModel clip) async {
    // Only check for video and audio clips
    if (clip.type != ClipType.video && clip.type != ClipType.audio) {
      return clip; // No validation needed for other types
    }

    logger.logInfo(
      '[AddClipCommand] Validating source duration for: ${clip.sourcePath}',
      _logTag,
    );

    // Get duration from the Python server
    final actualDurationMs = await _mediaDurationService.getMediaDurationMs(
      clip.sourcePath,
    );

    // If duration is significantly different (over 100ms), update it
    if (actualDurationMs > 0 &&
        (clip.sourceDurationMs == 0 ||
            (clip.sourceDurationMs - actualDurationMs).abs() > 100)) {
      logger.logInfo(
        '[AddClipCommand] Updating source duration from ${clip.sourceDurationMs}ms to ${actualDurationMs}ms',
        _logTag,
      );

      // Create a copy with the updated duration
      return clip.copyWith(
        sourceDurationMs: actualDurationMs,
        // If clip is using full duration, update the endTimeInSourceMs as well
        endTimeInSourceMs:
            clip.endTimeInSourceMs >= clip.sourceDurationMs
                ? actualDurationMs
                : clip.endTimeInSourceMs,
      );
    }

    return clip; // No changes needed
  }

  /// Adjusts preview dimensions based on canvas settings or media dimensions
  ClipModel _adjustPreviewDimensions(ClipModel clip) {
    // Use canvas dimensions for clip preview instead of default 100x100
    final canvasWidth = _canvasDimensionsService.canvasWidth;
    final canvasHeight = _canvasDimensionsService.canvasHeight;

    // Get appropriate preview size based on canvas dimensions
    final previewWidth = canvasWidth;
    final previewHeight = canvasHeight;

    logger.logInfo(
      '[AddClipCommand] Setting clip preview dimensions to match canvas: ${previewWidth}x$previewHeight',
      _logTag,
    );

    return clip.copyWith(
      previewWidth: previewWidth,
      previewHeight: previewHeight,
    );
  }

  @override
  Future<void> execute() async {
    if (_databaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return;
    }

    // Check if this is the first clip being added to the timeline
    final isFirstClip = _stateViewModel.clips.isEmpty;
    if (isFirstClip) {
      logger.logInfo(
        '[AddClipCommand] This is the first clip being added to the timeline',
        _logTag,
      );
    }

    // Step 1: Validate and potentially update the clip source duration
    var processedClipData = await _validateClipSourceDuration(clipDataInput);

    // Step 2: Adjust preview dimensions based on canvas settings
    processedClipData = _adjustPreviewDimensions(processedClipData);

    final initialEndTimeOnTrackMs =
        startTimeOnTrackMs + processedClipData.durationInSourceMs;
    final sourceDurationMs = processedClipData.sourceDurationMs;

    logger.logInfo(
      '[AddClipCommand] Preparing placement: track=$trackId, startTrack=$startTimeOnTrackMs, endTrack=$initialEndTimeOnTrackMs, startSource=${processedClipData.startTimeInSourceMs}, endSource=${processedClipData.endTimeInSourceMs}, sourceDuration=$sourceDurationMs',
      _logTag,
    );

    final placement = _timelineLogicService.prepareClipPlacement(
      clips: _stateViewModel.clips,
      clipId: null,
      trackId: trackId,
      type: processedClipData.type,
      sourcePath: processedClipData.sourcePath,
      sourceDurationMs: sourceDurationMs,
      startTimeOnTrackMs: startTimeOnTrackMs,
      endTimeOnTrackMs: initialEndTimeOnTrackMs,
      startTimeInSourceMs: processedClipData.startTimeInSourceMs,
      endTimeInSourceMs: processedClipData.endTimeInSourceMs,
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
        name: drift.Value(processedClipData.name),
        type: drift.Value(processedClipData.type.name),
        sourcePath: drift.Value(processedClipData.sourcePath),
        sourceDurationMs: drift.Value(newClipDataMap['sourceDurationMs']),
        startTimeOnTrackMs: drift.Value(newClipDataMap['startTimeOnTrackMs']),
        endTimeOnTrackMs: drift.Value(newClipDataMap['endTimeOnTrackMs']),
        startTimeInSourceMs: drift.Value(newClipDataMap['startTimeInSourceMs']),
        endTimeInSourceMs: drift.Value(newClipDataMap['endTimeInSourceMs']),
        previewPositionX: drift.Value(processedClipData.previewPositionX),
        previewPositionY: drift.Value(processedClipData.previewPositionY),
        previewWidth: drift.Value(processedClipData.previewWidth),
        previewHeight: drift.Value(processedClipData.previewHeight),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
        metadata: drift.Value(
          processedClipData.metadata.isNotEmpty
              ? jsonEncode(processedClipData.metadata)
              : null,
        ),
      ),
      // log: false, // Removed: ClipDao.insertClip doesn't have this param
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
          clip.databaseId ==
              null && // The new clip doesn't have an ID yet in this list
          clip.sourcePath == processedClipData.sourcePath &&
          clip.startTimeOnTrackMs == newClipDataMap['startTimeOnTrackMs'],
    );

    if (newClipIndex != -1 && _insertedClipId != null) {
      final newClipWithId = finalUpdatedClips[newClipIndex].copyWith(
        databaseId: drift.Value(_insertedClipId), // Assign the actual DB ID
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

    await _stateViewModel.refreshClips(); // Refresh the UI

    logger.logInfo(
      '[AddClipCommand] Triggered refresh in State ViewModel.',
      _logTag,
    );

    // Remove direct call to undoRedoService.init()
    // final UndoRedoService undoRedoService = di<UndoRedoService>();
    // await undoRedoService.init();
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
          // log: false, // Removed: ClipDao.insertClip doesn't have this param
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

  @override
  project_db.ChangeLog toChangeLog(String entityId) {
    return project_db.ChangeLog(
      id: -1,
      entity: 'clip',
      entityId: _insertedClipId?.toString() ?? entityId,
      action: commandType,
      oldData: jsonEncode({
        'originalNeighborStates':
            _originalNeighborStates?.map((c) => c.toJson()).toList(),
        'removedNeighborIds': _removedNeighborIds,
      }),
      newData: jsonEncode({
        'clipDataInput': clipDataInput.toJson(),
        'trackId': trackId,
        'startTimeOnTrackMs': startTimeOnTrackMs,
        'insertedClipId': _insertedClipId,
      }),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory AddClipCommand.fromJson(
    ProjectDatabaseService projectDatabaseService,
    Map<String, dynamic> commandData,
  ) {
    final newData = commandData['newData'] as Map<String, dynamic>;
    final oldData = commandData['oldData'] as Map<String, dynamic>? ?? {};

    final clipDataInput = ClipModel.fromJson(
      newData['clipDataInput'] as Map<String, dynamic>,
    );
    final trackId = newData['trackId'] as int;
    final startTimeOnTrackMs = newData['startTimeOnTrackMs'] as int;
    final insertedClipId = newData['insertedClipId'] as int?;

    List<ClipModel>? originalNeighborStates;
    if (oldData['originalNeighborStates'] != null) {
      originalNeighborStates =
          (oldData['originalNeighborStates'] as List<dynamic>)
              .map((item) => ClipModel.fromJson(item as Map<String, dynamic>))
              .toList();
    }

    List<int>? removedNeighborIds;
    if (oldData['removedNeighborIds'] != null) {
      removedNeighborIds = List<int>.from(
        oldData['removedNeighborIds'] as List<dynamic>,
      );
    }

    return AddClipCommand(
      clipData: clipDataInput,
      trackId: trackId,
      startTimeOnTrackMs: startTimeOnTrackMs,
      insertedClipId: insertedClipId,
      originalNeighborStates: originalNeighborStates,
      removedNeighborIds: removedNeighborIds,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'actionType': commandType,
      'entityId': _insertedClipId?.toString() ?? 'unknown',
      'oldData': {
        'originalNeighborStates':
            _originalNeighborStates?.map((c) => c.toJson()).toList(),
        'removedNeighborIds': _removedNeighborIds,
      },
      'newData': {
        'clipDataInput': clipDataInput.toJson(),
        'trackId': trackId,
        'startTimeOnTrackMs': startTimeOnTrackMs,
        'insertedClipId': _insertedClipId,
      },
    };
  }
}
