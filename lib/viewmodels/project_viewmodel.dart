import 'dart:async';

import 'package:flipedit/models/project_asset.dart'; // Required for ProjectAsset
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart'; // Import logger
import 'package:flutter/foundation.dart';
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
  // Add a temporary empty assets notifier for backward compatibility
  final ValueNotifier<List<ProjectAsset>> projectAssetsNotifier = ValueNotifier([]);

  ProjectViewModel({required SharedPreferences prefs}) : _prefs = prefs { 
    currentProjectNotifier = _metadataService.currentProjectMetadataNotifier;
    isProjectLoadedNotifier = ValueNotifier(
      currentProjectNotifier.value != null,
    );
    
    // Use tracks from the database service
    tracksNotifier = _databaseService.tracksNotifier;

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
        print('ProjectViewModel: Successfully loaded last project ID: $lastProjectId');
      } catch (e) {
        // Handle cases where the last project might have been deleted or is otherwise inaccessible
        print('ProjectViewModel: Failed to load last project ID $lastProjectId: $e');
        // Optionally clear the invalid ID
        await _prefs.remove(_lastProjectIdKey);
      }
    } else {
      print('ProjectViewModel: No last project ID found in SharedPreferences.');
    }
  }

  Future<void> addTrackCommand({required String type}) async {
    await _databaseService.addTrack(type: type);
  }

  Future<void> saveProjectCommand() async {
    // No explicit save needed in new architecture - handled automatically
    print("ProjectViewModel: Project changes are saved automatically in new architecture.");
  }

  // Temporary media asset command for backward compatibility
  Future<void> importMediaAssetCommand(String filePath) async {
    if (!isProjectLoaded) {
      throw StateError("Cannot import media: No project loaded.");
    }
    
    logInfo("ProjectViewModel", "Media importing not implemented in new architecture yet");
    logInfo("ProjectViewModel", "Selected file: $filePath");
    // In the future, this will use the database service to import media
  }

  // Media asset management will be handled by the database service in future updates

  @override
  void onDispose() {
    currentProjectNotifier.removeListener(_onProjectChanged);
    isProjectLoadedNotifier.dispose();
  }
}
