import 'package:drift/drift.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:window_manager/window_manager.dart';
class ProjectService {
  final ProjectDao _projectDao = di<ProjectDao>();

  /// Notifier for the currently loaded project.
  /// Other services/viewmodels can watch this.
  final ValueNotifier<Project?> currentProjectNotifier = ValueNotifier(null);

  // Stream of all projects, suitable for displaying a list of projects
  Stream<List<Project>> watchAllProjects() {
    return _projectDao.watchAllProjects();
  }

  // Creates a new project in the database
  Future<int> createNewProject({required String name}) async {
    final companion = ProjectsCompanion(name: Value(name));
    return _projectDao.insertProject(companion);
  }

  /// Loads a project by its ID and updates the [currentProjectNotifier].
  Future<void> loadProject(int projectId) async {
    final project = await _projectDao.getProjectById(projectId);
    currentProjectNotifier.value = project;
    if (project != null) {
      print("Loaded project: ${project.name}");
      windowManager.setTitle('${project.name} - FlipEdit');
      // TODO: Load associated clips, tracks, etc. for this project
    } else {
      print("Failed to load project with ID: $projectId");
      // Handle error: Maybe clear current project or show message
    }
  }

  /// Clears the currently loaded project.
  void closeProject() {
    currentProjectNotifier.value = null;
    print("Closed current project.");
    // TODO: Clear associated data (clips, timeline state, etc.)
  }

  // --- Add methods for saving the current project later ---

  // --- Add methods for managing clips/tracks associated with the current project later ---
} 