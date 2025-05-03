import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import '../utils/logger.dart' as logger;
import '../utils/constants.dart';
import '../services/preview_sync_service.dart';

/// Service for managing canvas dimensions settings
class CanvasDimensionsService {
  final String _logTag = 'CanvasDimensionsService';
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();

  // Default canvas dimensions from constants - use the AppConstants values
  static const double _defaultPreviewWidth = 1280.0;  // Preview size
  static const double _defaultPreviewHeight = 720.0;  // Preview size

  // Notifiers for canvas dimensions
  final ValueNotifier<double> canvasWidthNotifier;
  final ValueNotifier<double> canvasHeightNotifier;
  
  // Track if there are clips in the timeline
  final ValueNotifier<bool> hasClipsNotifier = ValueNotifier<bool>(false);
  
  // Track if user has been prompted about dimensions for the current session
  final ValueNotifier<bool> _hasPromptedUserNotifier = ValueNotifier<bool>(false);
  
  CanvasDimensionsService() : 
    // Initialize with default video dimensions from AppConstants
    canvasWidthNotifier = ValueNotifier<double>(_defaultPreviewWidth),
    canvasHeightNotifier = ValueNotifier<double>(_defaultPreviewHeight) {
    logger.logInfo('CanvasDimensionsService initialized with dimensions: ' +
        '${canvasWidthNotifier.value} x ${canvasHeightNotifier.value}, ' +
        'default video size: ${AppConstants.defaultVideoWidth} x ${AppConstants.defaultVideoHeight}', 
        _logTag);
    
    // Send initial dimensions to the preview server
    // Use a small delay to ensure preview service is ready
    Future.delayed(const Duration(seconds: 2), () {
      _syncDimensionsToPreviewServer();
    });
    
    // Listen for changes to dimensions
    canvasWidthNotifier.addListener(_syncDimensionsToPreviewServer);
    canvasHeightNotifier.addListener(_syncDimensionsToPreviewServer);
  }
  
  double get canvasWidth => canvasWidthNotifier.value;
  double get canvasHeight => canvasHeightNotifier.value;
  
  set canvasWidth(double value) {
    if (value > 0 && canvasWidthNotifier.value != value) {
      canvasWidthNotifier.value = value;
      logger.logInfo('Canvas width updated to $value', _logTag);
      // No need to call _syncDimensionsToPreviewServer here as listener will do it
    }
  }
  
  set canvasHeight(double value) {
    if (value > 0 && canvasHeightNotifier.value != value) {
      canvasHeightNotifier.value = value;
      logger.logInfo('Canvas height updated to $value', _logTag);
      // No need to call _syncDimensionsToPreviewServer here as listener will do it
    }
  }
  
  bool get hasClips => hasClipsNotifier.value;
  
  set hasClips(bool value) {
    logger.logInfo('hasClips changing from ${hasClipsNotifier.value} to $value', _logTag);
    if (hasClipsNotifier.value != value) {
      hasClipsNotifier.value = value;
      
      // If we're transitioning to having no clips, reset prompt flag
      if (!value) {
        _hasPromptedUserNotifier.value = false;
        logger.logInfo('Reset canvas dimension prompt flag', _logTag);
      }
    }
  }
  
  bool get shouldPromptForDimensions {
    // Only prompt when adding the first clip and haven't already prompted in this session
    bool shouldPrompt = !hasClips && !_hasPromptedUserNotifier.value;
    logger.logInfo('shouldPromptForDimensions: $shouldPrompt (hasClips: $hasClips, hasPrompted: ${_hasPromptedUserNotifier.value})', _logTag);
    return shouldPrompt;
  }
  
  void markUserPrompted() {
    _hasPromptedUserNotifier.value = true;
    logger.logInfo('User has been prompted about canvas dimensions', _logTag);
  }
  
  void updateCanvasDimensions(double width, double height) {
    canvasWidth = width;
    canvasHeight = height;
    logger.logInfo('Canvas dimensions updated to ${width}x${height}', _logTag);
    // Note: no need to call _syncDimensionsToPreviewServer() here as the listeners will do it
  }
  
  void resetToDefaults() {
    // Use video dimensions from AppConstants
    canvasWidth = AppConstants.defaultVideoWidth.toDouble();
    canvasHeight = AppConstants.defaultVideoHeight.toDouble();
    logger.logInfo('Canvas dimensions reset to default video size: ${canvasWidth}x${canvasHeight}', _logTag);
  }
  
  // Call this when the timeline is refreshed to update the hasClips flag
  void updateHasClipsState(int clipCount) {
    logger.logInfo('updateHasClipsState called with clipCount: $clipCount', _logTag);
    hasClips = clipCount > 0;
  }
  
  // Send canvas dimensions to the preview server
  void _syncDimensionsToPreviewServer() {
    try {
      final message = jsonEncode({
        'type': 'canvas_dimensions',
        'payload': {
          'width': canvasWidth.toInt(),
          'height': canvasHeight.toInt(),
        }
      });
      
      _previewSyncService.sendMessage(message);
      logger.logInfo('Sent canvas dimensions to preview server: ${canvasWidth.toInt()}x${canvasHeight.toInt()}', _logTag);
    } catch (e) {
      logger.logError('Error sending canvas dimensions to preview server: $e', _logTag);
    }
  }
  
  // Clean up resources
  void dispose() {
    canvasWidthNotifier.removeListener(_syncDimensionsToPreviewServer);
    canvasHeightNotifier.removeListener(_syncDimensionsToPreviewServer);
    canvasWidthNotifier.dispose();
    canvasHeightNotifier.dispose();
    hasClipsNotifier.dispose();
    _hasPromptedUserNotifier.dispose();
  }
} 