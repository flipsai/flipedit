import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:watch_it/watch_it.dart';

/// Service for managing project metadata and individual project databases
class ProjectMetadataService {
  String get _logTag => runtimeType.toString();
  
  final ProjectMetadataDao _projectMetadataDao = di<ProjectMetadataDao>();
  
  /// Notifier for the current project metadata
  final ValueNotifier<ProjectMetadata?> currentProjectMetadataNotifier = ValueNotifier(null);
  
  /// Stream of all project metadata
  Stream<List<ProjectMetadata>> watchAllProjectsMetadata() {
    return _projectMetadataDao.watchAllProjects();
  }
  
  /// Creates a new project metadata entry with its own database file
  Future<int> createNewProject({required String name}) async {
    try {
      // Generate a unique database path for this project
      final String databasePath = await _generateProjectDatabasePath(name);
      
      final companion = ProjectMetadataTableCompanion(
        name: Value(name),
        databasePath: Value(databasePath),
      );
      
      final projectId = await _projectMetadataDao.insertProjectMetadata(companion);
      logInfo(_logTag, "Created new project metadata: '$name' with ID: $projectId");
      
      // Create the physical database file for this project
      await _createProjectDatabase(databasePath);
      
      return projectId;
    } catch (e) {
      logError(_logTag, "Error creating new project: $e");
      rethrow;
    }
  }
  
  /// Generates a unique path for a project database
  Future<String> _generateProjectDatabasePath(String projectName) async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final sanitizedName = projectName.replaceAll(RegExp(r'[^\w\s]'), '_').replaceAll(' ', '_').toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(dbFolder.path, 'flipedit_project_${sanitizedName}_$timestamp.sqlite');
  }
  
  /// Creates a new empty project database file at the specified path
  Future<void> _createProjectDatabase(String databasePath) async {
    try {
      // For now, just create an empty file
      final file = File(databasePath);
      if (!await file.exists()) {
        await file.create(recursive: true);
        logInfo(_logTag, "Created new project database file at: $databasePath");
      }
    } catch (e) {
      logError(_logTag, "Error creating project database file: $e");
      rethrow;
    }
  }
  
  /// Loads a project metadata by ID
  Future<void> loadProjectMetadata(int projectId) async {
    try {
      final projectMetadata = await _projectMetadataDao.getProjectMetadataById(projectId);
      currentProjectMetadataNotifier.value = projectMetadata;
      
      if (projectMetadata != null) {
        logInfo(_logTag, "Loaded project metadata: ${projectMetadata.name}");
      } else {
        logWarning(_logTag, "Failed to load project metadata with ID: $projectId");
      }
    } catch (e) {
      logError(_logTag, "Error loading project metadata: $e");
      currentProjectMetadataNotifier.value = null;
    }
  }
  
  /// Deletes a project metadata and its database file
  Future<void> deleteProject(int projectId) async {
    try {
      // First, get the project metadata to retrieve the database path
      final projectMetadata = await _projectMetadataDao.getProjectMetadataById(projectId);
      if (projectMetadata == null) {
        logWarning(_logTag, "Cannot delete project: Project metadata not found for ID: $projectId");
        return;
      }
      
      // Delete the database file
      final databaseFile = File(projectMetadata.databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
        logInfo(_logTag, "Deleted project database file: ${projectMetadata.databasePath}");
      }
      
      // Delete the metadata record
      final deletedCount = await _projectMetadataDao.deleteProjectMetadata(projectId);
      if (deletedCount > 0) {
        logInfo(_logTag, "Deleted project metadata for ID: $projectId");
      } else {
        logWarning(_logTag, "Could not delete project metadata for ID: $projectId");
      }
      
      // Clear current if it's the same project
      if (currentProjectMetadataNotifier.value?.id == projectId) {
        currentProjectMetadataNotifier.value = null;
      }
    } catch (e) {
      logError(_logTag, "Error deleting project: $e");
      rethrow;
    }
  }
  
  /// Updates a project metadata name
  Future<void> updateProjectName(int projectId, String newName) async {
    try {
      final projectMetadata = await _projectMetadataDao.getProjectMetadataById(projectId);
      if (projectMetadata == null) {
        logWarning(_logTag, "Cannot update project name: Project metadata not found for ID: $projectId");
        return;
      }
      
      final companion = ProjectMetadataTableCompanion(
        id: Value(projectId),
        name: Value(newName),
        lastModifiedAt: Value(DateTime.now()),
      );
      
      final success = await _projectMetadataDao.updateProjectMetadata(companion);
      
      if (success) {
        logInfo(_logTag, "Updated project name to '$newName' for ID: $projectId");
        
        // Update current project metadata if it's the same project
        if (currentProjectMetadataNotifier.value?.id == projectId) {
          loadProjectMetadata(projectId);
        }
      } else {
        logWarning(_logTag, "Could not update project name for ID: $projectId");
      }
    } catch (e) {
      logError(_logTag, "Error updating project name: $e");
    }
  }
} 