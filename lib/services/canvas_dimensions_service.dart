import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import '../utils/logger.dart' as logger;
import '../utils/constants.dart';
import '../services/project_database_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flipedit/persistence/database/project_database.dart';

/// Service for managing canvas dimensions settings
class CanvasDimensionsService {
  final String _logTag = 'CanvasDimensionsService';
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();

  // Key for storing dimensions in project metadata
  static const String _projectDimensionsKey = 'canvas_dimensions';

  // Default canvas dimensions from constants - use the AppConstants values
  static const int _defaultVideoWidth = AppConstants.defaultVideoWidth;
  static const int _defaultVideoHeight = AppConstants.defaultVideoHeight;

  // Notifiers for canvas dimensions
  final ValueNotifier<double> canvasWidthNotifier;
  final ValueNotifier<double> canvasHeightNotifier;

  // Track if there are clips in the timeline
  final ValueNotifier<bool> hasClipsNotifier = ValueNotifier<bool>(false);

  // Track if user has been prompted about dimensions for the current session
  final ValueNotifier<bool> _hasPromptedUserNotifier = ValueNotifier<bool>(
    false,
  );

  CanvasDimensionsService()
    : // Initialize with default video dimensions from AppConstants
      canvasWidthNotifier = ValueNotifier<double>(
        _defaultVideoWidth.toDouble(),
      ),
      canvasHeightNotifier = ValueNotifier<double>(
        _defaultVideoHeight.toDouble(),
      ) {
    logger.logInfo(
      'CanvasDimensionsService initialized with dimensions: '
      '${canvasWidthNotifier.value} x ${canvasHeightNotifier.value}, '
      'default video size: ${AppConstants.defaultVideoWidth} x ${AppConstants.defaultVideoHeight}',
      _logTag,
    );

    // Try to load saved dimensions from project
    loadDimensionsFromProject();

    // Listen for changes to dimensions
    canvasWidthNotifier.addListener(_handleDimensionsChanged);
    canvasHeightNotifier.addListener(_handleDimensionsChanged);
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
    logger.logInfo(
      'hasClips changing from ${hasClipsNotifier.value} to $value',
      _logTag,
    );
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
    logger.logInfo(
      'shouldPromptForDimensions: $shouldPrompt (hasClips: $hasClips, hasPrompted: ${_hasPromptedUserNotifier.value})',
      _logTag,
    );
    return shouldPrompt;
  }

  void markUserPrompted() {
    _hasPromptedUserNotifier.value = true;
    logger.logInfo('User has been prompted about canvas dimensions', _logTag);
  }

  void updateCanvasDimensions(double width, double height) {
    canvasWidth = width;
    canvasHeight = height;
    logger.logInfo('Canvas dimensions updated to ${width}x$height', _logTag);
    // Note: no need to call _syncDimensionsToPreviewServer() here as the listeners will do it
  }

  void resetToDefaults() {
    // Use video dimensions from AppConstants
    canvasWidth = AppConstants.defaultVideoWidth.toDouble();
    canvasHeight = AppConstants.defaultVideoHeight.toDouble();
    logger.logInfo(
      'Canvas dimensions reset to default video size: ${canvasWidth}x$canvasHeight',
      _logTag,
    );
  }

  // Call this when the timeline is refreshed to update the hasClips flag
  void updateHasClipsState(int clipCount) {
    logger.logInfo(
      'updateHasClipsState called with clipCount: $clipCount',
      _logTag,
    );
    hasClips = clipCount > 0;
  }

  // Handler called when dimensions change
  void _handleDimensionsChanged() {
    _saveDimensionsToProject();
  }

  // Save canvas dimensions to project metadata
  Future<void> _saveDimensionsToProject() async {
    try {
      if (_databaseService.trackDao == null) {
        logger.logWarning('Cannot save dimensions: No project loaded', _logTag);
        return;
      }

      // Get the first track for metadata storage
      // We use the first track as a metadata container since there's no dedicated settings table
      final tracks = _databaseService.tracksNotifier.value;
      if (tracks.isEmpty) {
        // No tracks to save to yet
        logger.logWarning(
          'Cannot save dimensions: No tracks available',
          _logTag,
        );
        return;
      }

      final firstTrack = tracks.first;
      Map<String, dynamic> metadata = {};

      // Parse existing metadata if available
      if (firstTrack.metadataJson != null &&
          firstTrack.metadataJson!.isNotEmpty) {
        try {
          metadata =
              jsonDecode(firstTrack.metadataJson!) as Map<String, dynamic>;
        } catch (e) {
          logger.logError('Error parsing track metadata: $e', _logTag);
          metadata = {};
        }
      }

      // Add or update dimensions in metadata
      metadata[_projectDimensionsKey] = {
        'width': canvasWidth,
        'height': canvasHeight,
      };

      // Save updated metadata
      await _databaseService.trackDao!.updateTrack(
        TracksCompanion(
          id: Value(firstTrack.id),
          metadataJson: Value(jsonEncode(metadata)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      logger.logInfo(
        'Saved canvas dimensions (${canvasWidth.toInt()}x${canvasHeight.toInt()}) to project metadata',
        _logTag,
      );
    } catch (e) {
      logger.logError('Error saving canvas dimensions to project: $e', _logTag);
    }
  }

  // Load canvas dimensions from project metadata
  Future<void> loadDimensionsFromProject() async {
    try {
      if (_databaseService.trackDao == null) {
        logger.logWarning('Cannot load dimensions: No project loaded', _logTag);
        return;
      }

      // Get the first track for metadata retrieval
      final tracks = _databaseService.tracksNotifier.value;
      if (tracks.isEmpty) {
        logger.logWarning(
          'Cannot load dimensions: No tracks available',
          _logTag,
        );
        return;
      }

      final firstTrack = tracks.first;
      if (firstTrack.metadataJson == null || firstTrack.metadataJson!.isEmpty) {
        logger.logInfo(
          'No metadata found on track, using default dimensions',
          _logTag,
        );
        return;
      }

      // Parse metadata
      try {
        final metadata =
            jsonDecode(firstTrack.metadataJson!) as Map<String, dynamic>;
        final dimensionsData = metadata[_projectDimensionsKey];

        if (dimensionsData != null && dimensionsData is Map<String, dynamic>) {
          final width = dimensionsData['width'];
          final height = dimensionsData['height'];

          if (width != null && height != null) {
            // Update dimensions without triggering save (to prevent circular call)
            canvasWidthNotifier.value = width.toDouble();
            canvasHeightNotifier.value = height.toDouble();

            logger.logInfo(
              'Loaded canvas dimensions from project: ${width}x$height',
              _logTag,
            );

            return;
          }
        }
      } catch (e) {
        logger.logError('Error parsing dimensions from metadata: $e', _logTag);
      }

      logger.logInfo(
        'No saved dimensions found in project, using defaults',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        'Error loading canvas dimensions from project: $e',
        _logTag,
      );
    }
  }

  // Clean up resources
  void dispose() {
    canvasWidthNotifier.removeListener(_handleDimensionsChanged);
    canvasHeightNotifier.removeListener(_handleDimensionsChanged);
    canvasWidthNotifier.dispose();
    canvasHeightNotifier.dispose();
    hasClipsNotifier.dispose();
    _hasPromptedUserNotifier.dispose();
  }
}
