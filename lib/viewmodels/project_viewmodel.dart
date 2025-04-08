import 'package:flutter/foundation.dart';
import 'package:flipedit/models/project.dart';

class ProjectViewModel {
  final ValueNotifier<Project?> currentProjectNotifier = ValueNotifier<Project?>(null);
  Project? get currentProject => currentProjectNotifier.value;
  set currentProject(Project? value) {
    if (currentProjectNotifier.value == value) return;
    currentProjectNotifier.value = value;
  }
  
  bool get hasProject => currentProject != null;
  
  final ValueNotifier<List<Project>> recentProjectsNotifier = ValueNotifier<List<Project>>([]);
  List<Project> get recentProjects => List.unmodifiable(recentProjectsNotifier.value);
  set recentProjects(List<Project> value) {
    if (recentProjectsNotifier.value == value) return;
    recentProjectsNotifier.value = value;
  }
  
  void createNewProject(String name, String path) {
    if (name.isEmpty || path.isEmpty) return;
    
    currentProject = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      path: path,
      createdAt: DateTime.now(),
      lastModifiedAt: DateTime.now(),
    );
    
    // In a real application, we would save this to a database using Drift
  }
  
  void openProject(Project project) {
    currentProject = project;
    // Load project data from disk
  }
  
  void closeProject() {
    currentProject = null;
  }
  
  void saveProject() {
    if (currentProject == null) return;
    
    currentProject = currentProject!.copyWith(
      lastModifiedAt: DateTime.now(),
    );
    
    // In a real application, we would save to disk
  }
  
  void loadRecentProjects() {
    // In a real application, load from Drift database
    recentProjects = [];
  }
}
