import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/media_duration_service.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/views/dialogs/canvas_dimensions_dialog.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:watch_it/watch_it.dart';

const _logTag = 'ImportMediaCommand';

class ImportMediaCommand {
  final ProjectViewModel _projectViewModel;
  final ProjectDatabaseService _databaseService;
  final MediaDurationService _mediaDurationService = di<MediaDurationService>();
  final CanvasDimensionsService _canvasDimensionsService =
      di<CanvasDimensionsService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  /// Creates an ImportMediaCommand.
  ///
  /// [projectViewModel] - The current project ViewModel (must be loaded).
  /// [databaseService] - The service for asset import and persistence.
  ImportMediaCommand(this._projectViewModel, this._databaseService);

  /// Opens a file picker, optionally prompts for canvas dimensions, and imports the selected media file.
  ///
  /// Returns `true` if import was successful, `false` otherwise (including cancellation or error).

  Future<bool> execute(BuildContext context) async {
    // Check if a project is loaded using the injected ViewModel
    if (!_projectViewModel.isProjectLoaded) {
      logWarning(_logTag, "Cannot import media: No project loaded.");
      return false;
    }

    logInfo(_logTag, "Opening file picker dialog");

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        String? filePath = result.files.single.path;
        logInfo(_logTag, "File selected: $filePath");

        if (filePath != null) {
          try {
            // Check if we need to prompt for canvas dimensions BEFORE importing
            // This logic was moved from AddClipCommand
            final isFirstClip = _stateViewModel.clips.isEmpty;
            final shouldPrompt =
                _canvasDimensionsService.shouldPromptForDimensions ||
                isFirstClip;

            if (shouldPrompt) {
              logInfo(
                _logTag,
                "Checking media dimensions for potential canvas size prompt: $filePath",
              );
              try {
                final mediaInfo = await _mediaDurationService.getMediaInfo(
                  filePath,
                );
                if (mediaInfo.width > 0 && mediaInfo.height > 0) {
                  logInfo(
                    _logTag,
                    "First clip or prompt needed. Showing dimensions dialog.",
                  );
                  final useClipDimensions = await CanvasDimensionsDialog.show(
                    context,
                    mediaInfo.width,
                    mediaInfo.height,
                  );
                  logInfo(
                    _logTag,
                    "Canvas dimensions dialog result: $useClipDimensions",
                  );
                  if (useClipDimensions == true) {
                    _canvasDimensionsService.updateCanvasDimensions(
                      mediaInfo.width.toDouble(),
                      mediaInfo.height.toDouble(),
                    );
                    logInfo(
                      _logTag,
                      "Canvas dimensions updated to ${mediaInfo.width}x${mediaInfo.height}",
                    );
                  }
                  _canvasDimensionsService.markUserPrompted();
                } else {
                  logWarning(
                    _logTag,
                    "Could not get valid dimensions for prompt check for $filePath",
                  );
                }
              } catch (dimError) {
                logError(
                  _logTag,
                  "Error getting media dimensions for prompt check: $dimError",
                );
              }
            }

            logInfo(_logTag, "Proceeding to import file as asset: $filePath");
            // Call the internal asset import logic
            final assetId = await _importAsset(filePath);

            if (assetId != null) {
              logInfo(
                _logTag,
                "Media imported successfully via command: $filePath (Asset ID: $assetId)",
              );
              return true;
            } else {
              logError(
                _logTag,
                "Failed to import media: Database operation returned null",
              );
              return false;
            }
          } catch (importError) {
            logError(_logTag, "Error during asset import: $importError");
            return false;
          }
        } else {
          logWarning(_logTag, "File path is null after picking");
          return false;
        }
      } else {
        logInfo(_logTag, "File picking cancelled or no file selected");
        return false; // Treat cancellation as unsuccessful import for return value
      }
    } catch (e) {
      logError(_logTag, "Error picking file: $e");
      return false;
    }
  }

  /// Handles the backend logic of analyzing and importing the media file to the database.
  Future<int?> _importAsset(String filePath) async {
    if (!_projectViewModel.isProjectLoaded) {
      throw StateError("Cannot import media asset: No project loaded.");
    }

    logInfo(_logTag, "Processing asset: $filePath");

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException("File does not exist", filePath);
      }

      // Get file info
      final fileSize = await file.length();
      final extension = p.extension(filePath).toLowerCase();

      // Determine asset type
      final assetType = _getAssetTypeFromExtension(extension);

      // Default media metadata
      int durationMs = 0;
      int? width;
      int? height;

      // For video and audio, get media info from Python server
      if (assetType == ClipType.video || assetType == ClipType.audio) {
        logInfo(_logTag, "Getting media info via Python server: $filePath");
        final mediaInfo = await _mediaDurationService.getMediaInfo(filePath);

        durationMs = mediaInfo.durationMs;
        width = mediaInfo.width > 0 ? mediaInfo.width : null;
        height = mediaInfo.height > 0 ? mediaInfo.height : null;

        logInfo(
          _logTag,
          "Media info returned: duration=${durationMs}ms, dimensions=${width}x$height",
        );
      } else if (assetType == ClipType.image) {
        // For images, set a default duration and get dimensions
        logInfo(_logTag, "Getting dimensions for image: $filePath");
        final mediaInfo = await _mediaDurationService.getMediaInfo(filePath);

        durationMs = 5000; // 5 seconds default for images
        width = mediaInfo.width > 0 ? mediaInfo.width : null;
        height = mediaInfo.height > 0 ? mediaInfo.height : null;

        logInfo(
          _logTag,
          "Image info: default duration=${durationMs}ms, dimensions=${width}x$height",
        );
      }

      // Import asset using the database service
      logInfo(_logTag, "Calling databaseService.importAsset for: $filePath");
      return await _databaseService.importAsset(
        filePath: filePath,
        type: assetType,
        durationMs: durationMs,
        width: width,
        height: height,
        fileSize: fileSize.toDouble(),
      );
    } catch (e) {
      logError(_logTag, "Error importing media asset: $e");
      return null; // Return null on error as per original logic
    }
  }

  /// Helper to determine asset type from file extension.
  ClipType _getAssetTypeFromExtension(String extension) {
    switch (extension) {
      case '.mp4':
      case '.mov':
      case '.avi':
      case '.mkv':
      case '.webm':
        return ClipType.video;
      case '.mp3':
      case '.wav':
      case '.aac':
      case '.ogg':
      case '.flac':
        return ClipType.audio;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.webp':
        return ClipType.image;
      default:
        logWarning(
          _logTag,
          "Unknown file extension: $extension, defaulting to video",
        );
        return ClipType.video;
    }
  }
}
