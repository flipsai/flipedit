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

// Add this static variable to track the last request time
class UpdateRequestTracker {
  static DateTime _lastPreviewRequestTime = DateTime.now().subtract(const Duration(seconds: 5));
  
  // Make throttling even more aggressive - don't allow faster than one request every 500ms
  static bool shouldThrottle() {
    final now = DateTime.now();
    final timeSinceLast = now.difference(_lastPreviewRequestTime);
    return timeSinceLast < const Duration(milliseconds: 500);
  }
  
  static void updateTimestamp() {
    _lastPreviewRequestTime = DateTime.now();
  }
  
  // Add a counter for consecutive requests to implement exponential backoff
  static int _consecutiveRequests = 0;
  static const int _maxConsecutiveRequests = 5;
  
  static Duration getThrottleDelay() {
    // Increase consecutive request counter
    _consecutiveRequests = (_consecutiveRequests + 1).clamp(0, _maxConsecutiveRequests);
    
    // Calculate delay with exponential backoff: 300ms, 600ms, 900ms, etc.
    final baseDelay = 300;
    final calculatedDelay = baseDelay * _consecutiveRequests;
    
    return Duration(milliseconds: calculatedDelay);
  }
  
  static void resetConsecutiveRequests() {
    _consecutiveRequests = 0;
  }
}

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

    // Check if we should throttle this request
    if (UpdateRequestTracker.shouldThrottle()) {
      final throttleDelay = UpdateRequestTracker.getThrottleDelay();
      logInfo('Throttling preview update request for ${throttleDelay.inMilliseconds}ms to avoid server overload', _logTag);
      await Future.delayed(throttleDelay);
    } else {
      // Reset consecutive requests counter if we're not throttling
      UpdateRequestTracker.resetConsecutiveRequests();
    }
    UpdateRequestTracker.updateTimestamp();

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
    await Future.delayed(const Duration(milliseconds: 750));
    
    // Directly trigger a frame refresh via HTTP 
    // Only attempt once to reduce server load
    try {
      logInfo(
        'Initiating HTTP frame refresh',
        _logTag,
      );
      
      // Skip debug info request entirely to reduce load
      // Pass the current frame from the navigation view model
      final frameToRefresh = _navigationViewModel.currentFrame;
      logInfo('Attempting to refresh frame $frameToRefresh via HTTP', _logTag);
      await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
      logInfo(
        'HTTP frame refresh request for frame $frameToRefresh completed',
        _logTag,
      );
    } catch (e) {
      logWarning(
        'Failed to refresh frame via HTTP API: $e',
        _logTag,
      );
    }

    await _undoRedoService.init();

    logInfo('Successfully updated preview rect for clip $clipId', _logTag);
  }

  @override
  Future<void> undo() async {
    logInfo('Undoing UpdateClipPreviewRectCommand for clip $clipId', _logTag);

    // Apply throttling to undo operations as well
    if (UpdateRequestTracker.shouldThrottle()) {
      final throttleDelay = UpdateRequestTracker.getThrottleDelay();
      logInfo('Throttling undo preview update request for ${throttleDelay.inMilliseconds}ms to avoid server overload', _logTag);
      await Future.delayed(throttleDelay);
    } else {
      // Reset consecutive requests counter if we're not throttling
      UpdateRequestTracker.resetConsecutiveRequests();
    }
    UpdateRequestTracker.updateTimestamp();

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
    await Future.delayed(const Duration(milliseconds: 750));
    
    // Directly trigger a frame refresh via HTTP after undo
    // Only attempt once to reduce server load
    try {
      logInfo(
        'Initiating HTTP frame refresh after undo',
        _logTag,
      );
      
      // Skip debug info request entirely to reduce load
      // Pass the current frame from the navigation view model
      final frameToRefresh = _navigationViewModel.currentFrame;
      logInfo('Attempting to refresh frame $frameToRefresh via HTTP after undo', _logTag);
      await _previewHttpService.fetchAndUpdateFrame(frameToRefresh);
      logInfo(
        'HTTP frame refresh request for frame $frameToRefresh after undo completed',
        _logTag,
      );
    } catch (e) {
      logWarning(
        'Failed to refresh frame via HTTP API after undo: $e',
        _logTag,
      );
    }

    logInfo(
      'Successfully triggered undo for preview rect update for clip $clipId. ViewModel refreshed.',
      _logTag,
    );
  }
}
