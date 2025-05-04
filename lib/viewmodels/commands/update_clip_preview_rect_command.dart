import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:watch_it/watch_it.dart';

import '../../models/clip.dart';
import '../../services/project_database_service.dart';
import '../../services/preview_sync_service.dart';
import '../../services/preview_http_service.dart';
import '../../services/undo_redo_service.dart';
import '../../utils/logger.dart';
import '../../viewmodels/timeline_navigation_viewmodel.dart';
import '../timeline_state_viewmodel.dart';
import 'timeline_command.dart';

class UpdateClipPreviewRectCommand extends TimelineCommand {
  final int clipId;
  final Rect newRect;
  final String _logTag = 'UpdateClipPreviewRectCommand';

  final ProjectDatabaseService _dbService = di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();
  final PreviewHttpService _previewHttpService = di<PreviewHttpService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();
  final TimelineNavigationViewModel _navigationViewModel = di<TimelineNavigationViewModel>();

  ClipModel? _originalClipModel;
  int? _originalClipIndex;

  UpdateClipPreviewRectCommand({required this.clipId, required this.newRect});

  @override
  Future<void> execute() async {
    logInfo('Executing UpdateClipPreviewRectCommand for clip $clipId', _logTag);

    _originalClipIndex = _stateViewModel.clipsNotifier.value.indexWhere(
      (c) => c.databaseId == clipId,
    );
    if (_originalClipIndex == null || _originalClipIndex! < 0) {
      logError(
        'Clip with ID $clipId not found in ViewModel.',
        null,
        null,
        _logTag,
      );
      throw Exception('Clip not found for update');
    }
    _originalClipModel =
        _stateViewModel.clipsNotifier.value[_originalClipIndex!];

    final updatedClipModel = _originalClipModel!.copyWithPreviewRect(newRect);

    final metadataJson =
        updatedClipModel.metadata.isNotEmpty
            ? jsonEncode(updatedClipModel.metadata)
            : null;
    final success = await _dbService.clipDao?.updateClipFields(clipId, {
      'metadataJson': metadataJson,
    });

    if (success != true) {
      logError(
        'Failed to update clip $clipId preview rect in database.',
        null,
        null,
        _logTag,
      );
      throw Exception('Database update failed');
    }

    final updatedList = List<ClipModel>.from(
      _stateViewModel.clipsNotifier.value,
    );
    updatedList[_originalClipIndex!] = updatedClipModel;
    _stateViewModel.clipsNotifier.value = updatedList;

    // Sync changes to preview server
    await _previewSyncService.sendClipsToPreviewServer();
    logInfo(
      'Sent updated clips to preview server after rectangle update',
      _logTag,
    );

    // Send a refresh_from_db command to trigger database-based refresh
    _previewSyncService.sendMessage("refresh_from_db");
    logInfo(
      'Sent refresh_from_db command to preview server',
      _logTag,
    );
    
    // Log current frame before refresh
    final currentFrame = _navigationViewModel.currentFrameNotifier.value;
    logInfo(
      'Current timeline frame before refresh: $currentFrame',
      _logTag,
    );
    
    // Add a longer delay to allow the database refresh to complete
    logInfo(
      'Waiting for server database refresh to complete...',
      _logTag,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Directly trigger a frame refresh via HTTP
    bool refreshSuccessful = false;
    for (int attempt = 1; attempt <= 5 && !refreshSuccessful; attempt++) {
      try {
        logInfo(
          'Initiating HTTP frame refresh (attempt $attempt)',
          _logTag,
        );
        
        // Get debug timeline info first to check if database was properly updated
        if (attempt == 1) {
          try {
            await _previewHttpService.getTimelineDebugInfo();
          } catch (e) {
            logWarning('Failed to get debug info: $e', _logTag);
          }
        }
        
        await _previewHttpService.fetchAndUpdateFrame();
        logInfo(
          'HTTP frame refresh completed successfully',
          _logTag,
        );
        refreshSuccessful = true;
      } catch (e) {
        logWarning(
          'Attempt $attempt failed to refresh frame via HTTP API: $e',
          _logTag,
        );
        
        if (attempt < 5) {
          // Increase delay with each retry
          final delay = attempt * 250;
          logInfo(
            'Waiting ${delay}ms before next attempt...',
            _logTag,
          );
          await Future.delayed(Duration(milliseconds: delay));
        }
      }
    }
    
    if (!refreshSuccessful) {
      logError(
        'All HTTP frame refresh attempts failed',
        _logTag,
      );
    }

    await _undoRedoService.init();

    logInfo('Successfully updated preview rect for clip $clipId', _logTag);
  }

  @override
  Future<void> undo() async {
    logInfo('Undoing UpdateClipPreviewRectCommand for clip $clipId', _logTag);

    await _undoRedoService.undo();

    await _stateViewModel.refreshClips();

    // Sync changes to preview server after undo
    await _previewSyncService.sendClipsToPreviewServer();
    logInfo(
      'Sent clips to preview server after undo',
      _logTag,
    );
    
    // Send refresh_from_db command
    _previewSyncService.sendMessage("refresh_from_db");
    logInfo(
      'Sent refresh_from_db command after undo',
      _logTag,
    );
    
    // Log current frame before refresh
    final currentFrame = _navigationViewModel.currentFrameNotifier.value;
    logInfo(
      'Current timeline frame before undo refresh: $currentFrame',
      _logTag,
    );
    
    // Add a longer delay to allow the database refresh to complete after undo
    logInfo(
      'Waiting for server database refresh to complete after undo...',
      _logTag,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Directly trigger a frame refresh via HTTP after undo
    bool refreshSuccessful = false;
    for (int attempt = 1; attempt <= 5 && !refreshSuccessful; attempt++) {
      try {
        logInfo(
          'Initiating HTTP frame refresh after undo (attempt $attempt)',
          _logTag,
        );
        
        // Get debug timeline info first to check if database was properly updated
        if (attempt == 1) {
          try {
            await _previewHttpService.getTimelineDebugInfo();
          } catch (e) {
            logWarning('Failed to get debug info after undo: $e', _logTag);
          }
        }
        
        await _previewHttpService.fetchAndUpdateFrame();
        logInfo(
          'HTTP frame refresh after undo completed successfully',
          _logTag,
        );
        refreshSuccessful = true;
      } catch (e) {
        logWarning(
          'Attempt $attempt failed to refresh frame via HTTP API after undo: $e',
          _logTag,
        );
        
        if (attempt < 5) {
          final delay = attempt * 250;
          logInfo(
            'Waiting ${delay}ms before next attempt after undo...',
            _logTag,
          );
          await Future.delayed(Duration(milliseconds: delay));
        }
      }
    }
    
    if (!refreshSuccessful) {
      logError(
        'All HTTP frame refresh attempts failed after undo',
        _logTag,
      );
    }

    logInfo(
      'Successfully triggered undo for preview rect update for clip $clipId. ViewModel refreshed.',
      _logTag,
    );
  }
}
