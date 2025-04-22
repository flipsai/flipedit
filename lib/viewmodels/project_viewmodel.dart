import 'dart:async';

import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/utils/logger.dart'; // Import logger
import 'package:flutter/widgets.dart'; // Keep for BuildContext
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:watch_it/watch_it.dart';

import 'commands/import_media_command.dart'; // Import the new command
import 'commands/create_project_command.dart'; // Import CreateProjectCommand
import 'commands/load_project_command.dart'; // Import LoadProjectCommand

const _lastProjectIdKey = 'last_opened_project_id'; // Key for SharedPreferences
const _logTag = 'ProjectViewModel'; // Add log tag for consistency

class ProjectViewModel {
  final ProjectMetadataService _metadataService = di<ProjectMetadataService>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();
  final SharedPreferences _prefs; // Add SharedPreferences field
  final UndoRedoService _undoRedoService = di<UndoRedoService>(); // Get UndoRedoService

  // Commands
  late final ImportMediaCommand importMediaCommand;
  late final CreateProjectCommand createProjectCommand;
  late final LoadProjectCommand loadProjectCommand;

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

    // Initialize commands
    importMediaCommand = ImportMediaCommand(this, _databaseService);
    createProjectCommand = CreateProjectCommand(_metadataService);
    loadProjectCommand = LoadProjectCommand(
      _metadataService,
      _databaseService,
      _prefs,
      _undoRedoService,
    );
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

  Future<int> createNewProject(String name) async {
    // Delegate to command
    return await createProjectCommand.execute(name: name);
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

  Future<void> loadProject(int projectId) async {
    // Delegate to command
    await loadProjectCommand.execute(projectId);
  }

  // New command to load the last opened project
  Future<void> loadLastOpenedProjectCommand() async {
    final lastProjectId = _prefs.getInt(_lastProjectIdKey);
    if (lastProjectId != null) {
      try {
        // Attempt to load the project using the stored ID
        await loadProject(lastProjectId);
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

  // Public method to initiate media import, delegates to the command
  Future<bool> importMedia(BuildContext context) async {
    // Delegate directly to the command's execute method
    return await importMediaCommand.execute(context);
  }

  void dispose() {
    currentProjectNotifier.removeListener(_onProjectChanged);
    isProjectLoadedNotifier.dispose();
  }
}
