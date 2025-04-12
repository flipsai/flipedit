import 'dart:async';

import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/services/project_service.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

class ProjectViewModel extends ChangeNotifier implements Disposable {
  final ProjectService _projectService = di<ProjectService>();

  late final ValueNotifier<Project?> currentProjectNotifier;
  late final ValueNotifier<bool> isProjectLoadedNotifier;

  StreamSubscription? _projectSubscription;

  ProjectViewModel() {
    currentProjectNotifier = _projectService.currentProjectNotifier;
    isProjectLoadedNotifier = ValueNotifier(currentProjectNotifier.value != null);

    currentProjectNotifier.addListener(_onProjectChanged);
    _projectSubscription = null;
  }

  void _onProjectChanged() {
    isProjectLoadedNotifier.value = currentProjectNotifier.value != null;
  }

  Project? get currentProject => currentProjectNotifier.value;
  bool get isProjectLoaded => isProjectLoadedNotifier.value;

  Future<int> createNewProjectCommand(String name) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Project name cannot be empty.');
    }
    final newProjectId = await _projectService.createNewProject(name: name.trim());
    await _projectService.loadProject(newProjectId);
    return newProjectId;
  }

  Future<List<Project>> getAllProjects() async {
    return _projectService.watchAllProjects().first;
  }

  Future<void> loadProjectCommand(int projectId) async {
    await _projectService.loadProject(projectId);
  }

  Future<void> addTrackCommand({required String type}) async {
    await _projectService.addTrack(type: type);
  }

  Future<void> saveProjectCommand() async {
    if (isProjectLoaded) {
      await _projectService.saveProject();
    } else {
      print("ProjectViewModel: No project loaded to save.");
    }
  }

  @override
  void onDispose() {
    currentProjectNotifier.removeListener(_onProjectChanged);
    isProjectLoadedNotifier.dispose();
    super.dispose();
  }
}
