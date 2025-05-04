import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import '../timeline_viewmodel.dart';
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
import '../../services/undo_redo_service.dart';
import '../../services/preview_http_service.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';

class AddClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel clipData;
  final int trackId;
  final int startTimeOnTrackMs;

  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();
  final MediaDurationService _mediaDurationService = di<MediaDurationService>();
  final CanvasDimensionsService _canvasDimensionsService = di<CanvasDimensionsService>();
  final PreviewHttpService _previewHttpService = di<PreviewHttpService>();
  final TimelineNavigationViewModel _timelineNavViewModel = di<TimelineNavigationViewModel>();
 
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
    final actualDurationMs = await _mediaDurationService.getMediaDurationMs(clip.sourcePath);
    
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
        endTimeInSourceMs: clip.endTimeInSourceMs >= clip.sourceDurationMs ? 
          actualDurationMs : 
          clip.endTimeInSourceMs,
      );
    }
    
    return clip; // No changes needed
  }
  
  /// Sets up default preview rectangle based on current canvas dimensions and media dimensions
  Future<ClipModel> _setupPreviewRect(ClipModel clip) async {
    // If the clip already has a previewRect, don't override it
    if (clip.metadata.containsKey('previewRect')) {
      logger.logInfo(
        '[AddClipCommand] Clip already has previewRect, skipping auto-detection',
        _logTag,
      );
      return clip;
    }

    logger.logInfo(
      '[AddClipCommand] Auto-detecting dimensions for: ${clip.sourcePath}',
      _logTag,
    );
    
    try {
      // Get media info from Python server
      final mediaInfo = await _mediaDurationService.getMediaInfo(clip.sourcePath);
      
      if (mediaInfo.width > 0 && mediaInfo.height > 0) {
        // Default preview rect values with detected dimensions
        int previewWidth = mediaInfo.width;
        int previewHeight = mediaInfo.height;
        
        // Get current canvas dimensions
        double canvasWidth = _canvasDimensionsService.canvasWidth;
        double canvasHeight = _canvasDimensionsService.canvasHeight;
        
        final left = (canvasWidth - previewWidth) / 2;
        final top = (canvasHeight - previewHeight) / 2;
        
        // Create previewRect metadata
        final previewRect = {
          'left': left,
          'top': top,
          'width': previewWidth.toDouble(),
          'height': previewHeight.toDouble(),
        };
        
        // Create updated metadata
        final updatedMetadata = Map<String, dynamic>.from(clip.metadata);
        updatedMetadata['previewRect'] = previewRect;
        
        logger.logInfo(
          '[AddClipCommand] Created preview rect: ${previewWidth}x${previewHeight} at position (${left.round()},${top.round()})',
          _logTag,
        );
        
        // Return clip with updated metadata
        return clip.copyWith(
          metadata: updatedMetadata,
        );
      }
    } catch (e) {
      logger.logError(
        '[AddClipCommand] Error detecting media dimensions: $e',
        _logTag,
      );
    }
    
    return clip; // Return original clip if dimensions detection fails
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
      logger.logInfo('[AddClipCommand] This is the first clip being added to the timeline', _logTag);
    }

    // Step 1: Validate and potentially update the clip source duration
    var processedClipData = await _validateClipSourceDuration(clipData);
    
    // Step 2: Set up preview rectangle based on media dimensions and current canvas size
    processedClipData = await _setupPreviewRect(processedClipData);

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
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
        metadataJson: drift.Value(
          processedClipData.metadata.isNotEmpty
              ? jsonEncode(processedClipData.metadata)
              : null,
        ),
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
          clip.sourcePath == processedClipData.sourcePath &&
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

    // Fetch frame if paused
    if (!_timelineNavViewModel.isPlayingNotifier.value) {
      logger.logDebug('[AddClipCommand] Timeline paused, fetching frame via HTTP...', _logTag);
      // Pass the current frame from the navigation view model
      final frameToRefresh = _timelineNavViewModel.currentFrame;
      logger.logDebug('[AddClipCommand] Attempting to refresh frame $frameToRefresh via HTTP', _logTag);
      await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
    }

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

      // Fetch frame if paused
      if (!_timelineNavViewModel.isPlayingNotifier.value) {
        logger.logDebug('[AddClipCommand][Undo] Timeline paused, fetching frame via HTTP...', _logTag);
        // Pass the current frame from the navigation view model
        final frameToRefresh = _timelineNavViewModel.currentFrame;
        logger.logDebug('[AddClipCommand][Undo] Attempting to refresh frame $frameToRefresh via HTTP', _logTag);
        await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
      }

      _insertedClipId = null;
      _originalNeighborStates = null;
      _removedNeighborIds = null;
      logger.logInfo('[AddClipCommand] Undo complete', _logTag);
    } catch (e, s) {
      logger.logError('[AddClipCommand] Error during undo: $e\n$s', _logTag);
    }
  }
}
