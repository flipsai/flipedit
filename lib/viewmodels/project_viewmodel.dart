import 'package:flutter/foundation.dart';
import 'package:flipedit/models/project.dart';

class ProjectViewModel extends ChangeNotifier {
  Project? _currentProject;
  Project? get currentProject => _currentProject;
  
  bool get hasProject => _currentProject != null;
  
  List<Project> _recentProjects = [];
  List<Project> get recentProjects => _recentProjects;
  
  void createNewProject(String name, String path) {
    _currentProject = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      path: path,
      createdAt: DateTime.now(),
      lastModifiedAt: DateTime.now(),
    );
    
    // In a real application, we would save this to a database using Drift
    
    notifyListeners();
  }
  
  void openProject(Project project) {
    _currentProject = project;
    // Load project data from disk
    notifyListeners();
  }
  
  void closeProject() {
    _currentProject = null;
    notifyListeners();
  }
  
  void saveProject() {
    if (_currentProject != null) {
      _currentProject = _currentProject!.copyWith(
        lastModifiedAt: DateTime.now(),
      );
      
      // In a real application, we would save to disk
      
      notifyListeners();
    }
  }
  
  void loadRecentProjects() {
    // In a real application, load from Drift database
    _recentProjects = [];
    notifyListeners();
  }
}
