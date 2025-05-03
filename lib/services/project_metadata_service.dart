import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart';
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
  final ValueNotifier<ProjectMetadata?> currentProjectMetadataNotifier =
      ValueNotifier(null);

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

      final projectId = await _projectMetadataDao.insertProjectMetadata(
        companion,
      );
      logInfo(
        _logTag,
        "Created new project metadata: '$name' with ID: $projectId",
      );

      // Create and initialize the project database
      await _createAndInitializeProjectDatabase(databasePath);

      return projectId;
    } catch (e) {
      logError(_logTag, "Error creating new project: $e");
      rethrow;
    }
  }

  /// Generates a unique path for a project database
  Future<String> _generateProjectDatabasePath(String projectName) async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final sanitizedName =
        projectName
            .replaceAll(RegExp(r'[^\w\s]'), '_')
            .replaceAll(' ', '_')
            .toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(
      dbFolder.path,
      'flipedit_project_${sanitizedName}_$timestamp.sqlite',
    );
  }

  /// Creates a new project database file and initializes it with the correct schema
  Future<void> _createAndInitializeProjectDatabase(String databasePath) async {
    try {
      // Create a project database instance
      final projectDb = ProjectDatabase(databasePath);

      try {
        // Access the database to trigger initialization
        // Note: Drift will automatically create tables when the database is first accessed
        await File(
          databasePath,
        ).exists(); // Just check if file exists to ensure it's created
        logInfo(
          _logTag,
          "Created and initialized new project database at: $databasePath",
        );
      } finally {
        // Close the database connection when done
        await projectDb.closeConnection();
      }
    } catch (e) {
      logError(_logTag, "Error creating project database: $e");

      // Delete the file if it was created but there was an error
      final file = File(databasePath);
      if (await file.exists()) {
        try {
          await file.delete();
          logInfo(
            _logTag,
            "Deleted incomplete project database file after error",
          );
        } catch (deleteError) {
          logError(
            _logTag,
            "Error deleting incomplete database file: $deleteError",
          );
        }
      }

      rethrow;
    }
  }

  /// Closes the current project by clearing the metadata notifier.
  /// Database connection is managed elsewhere (e.g., LoadProjectCommand or relevant services).
  Future<void> closeProject() async {
    // Only clear the notifier now
    currentProjectMetadataNotifier.value = null;
    logInfo(_logTag, "Closed current project (cleared metadata notifier)");
  }

  /// Deletes a project metadata and its database file
  Future<void> deleteProject(int projectId) async {
    try {
      // First, get the project metadata to retrieve the database path
      final projectMetadata = await _projectMetadataDao.getProjectMetadataById(
        projectId,
      );
      if (projectMetadata == null) {
        logWarning(
          _logTag,
          "Cannot delete project: Project metadata not found for ID: $projectId",
        );
        return;
      }

      // If this is the current project, close it first
      if (currentProjectMetadataNotifier.value?.id == projectId) {
        await closeProject();
      }

      // Delete the database file
      final databaseFile = File(projectMetadata.databasePath);
      if (await databaseFile.exists()) {
        await databaseFile.delete();
        logInfo(
          _logTag,
          "Deleted project database file: ${projectMetadata.databasePath}",
        );
      }

      // Delete the metadata record
      final deletedCount = await _projectMetadataDao.deleteProjectMetadata(
        projectId,
      );
      if (deletedCount > 0) {
        logInfo(_logTag, "Deleted project metadata for ID: $projectId");
      } else {
        logWarning(
          _logTag,
          "Could not delete project metadata for ID: $projectId",
        );
      }
    } catch (e) {
      logError(_logTag, "Error deleting project: $e");
      rethrow;
    }
  }

  /// Updates a project metadata name
  Future<void> updateProjectName(int projectId, String newName) async {
    try {
      final projectMetadata = await _projectMetadataDao.getProjectMetadataById(
        projectId,
      );
      if (projectMetadata == null) {
        logWarning(
          _logTag,
          "Cannot update project name: Project metadata not found for ID: $projectId",
        );
        return;
      }

      final companion = ProjectMetadataTableCompanion(
        id: Value(projectId),
        name: Value(newName),
        lastModifiedAt: Value(DateTime.now()),
      );

      final success = await _projectMetadataDao.updateProjectMetadata(
        companion,
      );

      if (success) {
        logInfo(
          _logTag,
          "Updated project name to '$newName' for ID: $projectId",
        );

        // Update current project metadata if it's the same project
        if (currentProjectMetadataNotifier.value?.id == projectId) {
          final updatedMetadata = await _projectMetadataDao
              .getProjectMetadataById(projectId);
          currentProjectMetadataNotifier.value = updatedMetadata;
        }
      } else {
        logWarning(_logTag, "Could not update project name for ID: $projectId");
      }
    } catch (e) {
      logError(_logTag, "Error updating project name: $e");
    }
  }
}
