import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart'; // Import ProjectViewModel
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

const _logTag = 'ImportMediaCommand';

class ImportMediaCommand {
  final ProjectViewModel _projectViewModel;
  final ProjectDatabaseService _databaseService;

  ImportMediaCommand(this._projectViewModel, this._databaseService);

  /// Opens a file picker and imports the selected media file.
  /// Returns true if import was successful, false otherwise (including cancellation).
  Future<bool> execute(BuildContext context) async {
    // Check if a project is loaded using the injected ViewModel
    if (!_projectViewModel.isProjectLoaded) {
      logWarning(_logTag, "Cannot import media: No project loaded.");
      // Consider showing a user notification here via BuildContext or a dedicated service
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
            logInfo(_logTag, "Importing file via command: $filePath");
            // Call the internal asset import logic
            final assetId = await _importAsset(filePath);
            
            if (assetId != null) {
              logInfo(_logTag, "Media imported successfully via command: $filePath (Asset ID: $assetId)");
              return true;
            } else {
              logError(_logTag, "Failed to import media: Database operation returned null");
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
    // Redundant check, but good practice if this method were ever called directly
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
      
      // Get media metadata
      int durationMs = 0;
      int? width;
      int? height;
      
      // Import asset using the database service
      logInfo(_logTag, "Calling databaseService.importAsset for: $filePath");
      return await _databaseService.importAsset(
        filePath: filePath,
        type: assetType,
        durationMs: durationMs,
        width: width,
        height: height,
        fileSize: fileSize.toDouble(),
        // thumbnailPath: thumbnailPath,
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
        logWarning(_logTag, "Unknown file extension: $extension, defaulting to video");
        return ClipType.video;
    }
  }
} 