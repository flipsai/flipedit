import 'dart:async';
import 'dart:io'; // Required for Path

import 'package:flipedit/models/enums/clip_type.dart'; // Required for ClipType
import 'package:flipedit/models/project_asset.dart'; // Required for ProjectAsset
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/services/project_service.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:path/path.dart' as p; // Use path package for basename

class ProjectViewModel {
  final ProjectService _projectService = di<ProjectService>();

  late final ValueNotifier<Project?> currentProjectNotifier;
  late final ValueNotifier<bool> isProjectLoadedNotifier;
  // Use the notifier from ProjectService
  late final ValueNotifier<List<ProjectAsset>> projectAssetsNotifier;

  ProjectViewModel() {
    currentProjectNotifier = _projectService.currentProjectNotifier;
    isProjectLoadedNotifier = ValueNotifier(
      currentProjectNotifier.value != null,
    );
    // Initialize from ProjectService's notifier
    projectAssetsNotifier = _projectService.currentProjectAssetsNotifier;

    // No need to listen to currentProjectNotifier to update assets,
    // ProjectService handles that now.
    // currentProjectNotifier.addListener(_onProjectChanged);
    // Listen directly to isProjectLoadedNotifier if needed for other logic
    // isProjectLoadedNotifier.addListener(_onLoadStatusChanged);
    // Listen to the service's project notifier to update the load status
    currentProjectNotifier.addListener(_onProjectChanged);
  }

  // Optional: Listener if other things depend on load status changes
  // void _onLoadStatusChanged() {
  //  notifyListeners(); // Notify listeners if the load status changes
  // }

  // Remove _onProjectChanged if it only managed assets
  /*
  void _onProjectChanged() {
    isProjectLoadedNotifier.value = currentProjectNotifier.value != null;
    // ProjectService now manages loading/clearing assets
  }
  */
  // Listener for when the project in ProjectService changes
  void _onProjectChanged() {
    final projectLoaded = currentProjectNotifier.value != null;
    // Only update and notify if the value actually changed
    if (isProjectLoadedNotifier.value != projectLoaded) {
      isProjectLoadedNotifier.value = projectLoaded;
    }
    // No need to manage assets here, ProjectService does that.
  }

  Project? get currentProject => currentProjectNotifier.value;
  bool get isProjectLoaded => isProjectLoadedNotifier.value;
  // Getter remains the same, points to the service's notifier value
  List<ProjectAsset> get projectAssets => projectAssetsNotifier.value;

  Future<int> createNewProjectCommand(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Project name cannot be empty.');
    }
    // Service now handles loading after creation
    return await _projectService.createNewProject(name: name.trim());
    // final newProjectId = await _projectService.createNewProject(
    //   name: name.trim(),
    // );
    // await _projectService.loadProject(newProjectId);
    // return newProjectId;
  }

  Future<List<Project>> getAllProjects() async {
    try {
      // Use watchAllProjects().first or a dedicated get method if added to service
      return await _projectService.watchAllProjects().first;
    } catch (e) {
      debugPrint('Error getting projects: $e');
      return [];
    }
  }

  Future<void> loadProjectCommand(int projectId) async {
    await _projectService.loadProject(projectId);
    // ProjectService now handles loading assets internally
  }

  Future<void> addTrackCommand({required String type}) async {
    await _projectService.addTrack(type: type);
  }

  Future<void> saveProjectCommand() async {
    // Check using the notifier directly
    if (_projectService.currentProjectNotifier.value != null) {
      await _projectService.saveProject();
    } else {
      print("ProjectViewModel: No project loaded to save.");
    }
  }

  // Update command to use ProjectService
  Future<void> importMediaAssetCommand(String filePath) async {
    if (!isProjectLoaded) {
      throw StateError("Cannot import media: No project loaded.");
    }
    // TODO: Get actual duration and type detection
    final newAsset = ProjectAsset(
      name: p.basename(filePath), // Use path package for filename
      type: ClipType.video, // Placeholder: Detect type
      sourcePath: filePath,
      durationMs: 5000, // Placeholder: Get actual duration
    );

    // Call ProjectService to persist the asset
    await _projectService.addProjectAsset(newAsset);

    // No longer need to update local notifier, service watcher handles it
    // projectAssetsNotifier.value = [...projectAssetsNotifier.value, newAsset];
  }

  @override
  void onDispose() {
    // currentProjectNotifier.removeListener(_onProjectChanged); // Remove if listener removed
    // isProjectLoadedNotifier.removeListener(_onLoadStatusChanged);
    currentProjectNotifier.removeListener(_onProjectChanged); // Remove listener for project changes
    isProjectLoadedNotifier.dispose();
    // projectAssetsNotifier is owned by ProjectService, so don't dispose here
    // projectAssetsNotifier.dispose();
  }
}
