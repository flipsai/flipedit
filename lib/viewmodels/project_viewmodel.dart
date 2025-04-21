import 'dart:async';
import 'dart:io';

import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart'; // Import logger
import 'package:flipedit/utils/media_utils.dart'; // Import media utilities
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:watch_it/watch_it.dart';

const _lastProjectIdKey = 'last_opened_project_id'; // Key for SharedPreferences

class ProjectViewModel {
  final ProjectMetadataService _metadataService = di<ProjectMetadataService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final SharedPreferences _prefs; // Add SharedPreferences field

  late final ValueNotifier<ProjectMetadata?> currentProjectNotifier;
  late final ValueNotifier<bool> isProjectLoadedNotifier;
  // Use the notifier from ProjectDatabaseService for tracks
  late final ValueNotifier<List<Track>> tracksNotifier;
  // Use the notifier from ProjectDatabaseService for assets
  late final ValueNotifier<List<model.ProjectAsset>> projectAssetsNotifier;

  ProjectViewModel({required SharedPreferences prefs}) : _prefs = prefs { 
    currentProjectNotifier = _metadataService.currentProjectMetadataNotifier;
    isProjectLoadedNotifier = ValueNotifier(
      currentProjectNotifier.value != null,
    );
    
    // Use tracks from the database service
    tracksNotifier = _databaseService.tracksNotifier;
    
    // Use assets from the database service
    projectAssetsNotifier = _databaseService.assetsNotifier;

    // Listen to the service's project notifier to update the load status
    currentProjectNotifier.addListener(_onProjectChanged);
  }

  // Listener for when the project in metadata service changes
  void _onProjectChanged() {
    final projectLoaded = currentProjectNotifier.value != null;
    // Only update and notify if the value actually changed
    if (isProjectLoadedNotifier.value != projectLoaded) {
      isProjectLoadedNotifier.value = projectLoaded;
    }
  }

  ProjectMetadata? get currentProject => currentProjectNotifier.value;
  bool get isProjectLoaded => isProjectLoadedNotifier.value;
  // Getter for tracks from database service
  List<Track> get tracks => tracksNotifier.value;
  // Getter for assets from database service
  List<model.ProjectAsset> get projectAssets => projectAssetsNotifier.value;

  Future<int> createNewProjectCommand(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Project name cannot be empty.');
    }
    
    // Use metadata service to create project
    return await _metadataService.createNewProject(name: name.trim());
  }

  Future<List<ProjectMetadata>> getAllProjects() async {
    try {
      // Use metadata service to get all projects
      return await _metadataService.watchAllProjectsMetadata().first;
    } catch (e) {
      debugPrint('Error getting projects: $e');
      return [];
    }
  }

  Future<void> loadProjectCommand(int projectId) async {
    // Load project metadata and database
    final projectDb = await _metadataService.loadProject(projectId);
    
    if (projectDb != null) {
      // Load project in database service
      await _databaseService.loadProject(projectId);
      
      // Save the loaded project ID if successful
      if (isProjectLoaded) {
        await _prefs.setInt(_lastProjectIdKey, projectId);
      }
    }
  }

  // New command to load the last opened project
  Future<void> loadLastOpenedProjectCommand() async {
    final lastProjectId = _prefs.getInt(_lastProjectIdKey);
    if (lastProjectId != null) {
      try {
        // Attempt to load the project using the stored ID
        await loadProjectCommand(lastProjectId);
        logInfo("ProjectViewModel", "Successfully loaded last project ID: $lastProjectId");
      } catch (e) {
        // Handle cases where the last project might have been deleted or is otherwise inaccessible
        logError("ProjectViewModel", "Failed to load last project ID $lastProjectId: $e");
        // Optionally clear the invalid ID
        await _prefs.remove(_lastProjectIdKey);
      }
    } else {
      logInfo("ProjectViewModel", "No last project ID found in SharedPreferences.");
    }
  }

  Future<void> addTrackCommand({required String type}) async {
    await _databaseService.addTrack(type: type);
  }

  Future<void> saveProjectCommand() async {
    // No explicit save needed in new architecture - handled automatically
    logInfo("ProjectViewModel", "Project changes are saved automatically in new architecture.");
  }

  // Media importing implementation
  Future<int?> importMediaAssetCommand(String filePath) async {
    if (!isProjectLoaded) {
      throw StateError("Cannot import media: No project loaded.");
    }
    
    logInfo("ProjectViewModel", "Importing media: $filePath");
    
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw FileSystemException("File does not exist", filePath);
      }
      
      // Get file info
      final fileSize = await file.length();
      final extension = p.extension(filePath).toLowerCase();
      
      // Determine asset type based on file extension
      final assetType = _getAssetTypeFromExtension(extension);
      
      // Get media duration and dimensions
      int durationMs = 0;
      int? width;
      int? height;
      
      // For video and audio assets, get the duration
      if (assetType == ClipType.video || assetType == ClipType.audio) {
        // Use a media utility to get the duration
        final mediaDuration = await MediaUtils.getMediaDuration(filePath);
        durationMs = mediaDuration?.inMilliseconds ?? 0;
        
        // For video, also get dimensions
        if (assetType == ClipType.video) {
          final dimensions = await MediaUtils.getVideoDimensions(filePath);
          width = dimensions?.width;
          height = dimensions?.height;
        }
      } else if (assetType == ClipType.image) {
        // For images, set duration to 0 (static) and get dimensions
        final dimensions = await MediaUtils.getImageDimensions(filePath);
        width = dimensions?.width;
        height = dimensions?.height;
      }
      
      // Generate thumbnail
      String? thumbnailPath = await MediaUtils.generateThumbnail(filePath, assetType);
      
      // Import asset to database
      return await _databaseService.importAsset(
        filePath: filePath,
        type: assetType,
        durationMs: durationMs,
        width: width,
        height: height,
        fileSize: fileSize.toDouble(),
        thumbnailPath: thumbnailPath,
      );
    } catch (e) {
      logError("ProjectViewModel", "Error importing media: $e");
      return null;
    }
  }
  
  // Helper to determine asset type from file extension
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
        // Default to video for unknown types
        logWarning("ProjectViewModel", "Unknown file extension: $extension, defaulting to video");
        return ClipType.video;
    }
  }

  void dispose() {
    currentProjectNotifier.removeListener(_onProjectChanged);
    isProjectLoadedNotifier.dispose();
  }
}
