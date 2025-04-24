import 'dart:async';

import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart'; // For di

const _logTag = 'LoadProjectCommand';
const _lastProjectIdKey = 'last_opened_project_id'; // Key for SharedPreferences

class LoadProjectCommand {
  final ProjectMetadataService _metadataService;
  final ProjectDatabaseService _databaseService;
  final SharedPreferences _prefs;
  final UndoRedoService _undoRedoService;
  final ProjectMetadataDao _projectMetadataDao;

  LoadProjectCommand(
    this._metadataService,
    this._databaseService,
    this._prefs,
    this._undoRedoService,
  ) : _projectMetadataDao = di<ProjectMetadataDao>();

  /// Loads project metadata and data, updates state, and initializes services.
  Future<void> execute(int projectId) async {
    logInfo(_logTag, "Executing LoadProjectCommand for ID: $projectId");
    try {
      // 1. Get Project Metadata from DAO
      final ProjectMetadata? projectMetadata = 
          await _projectMetadataDao.getProjectMetadataById(projectId);

      if (projectMetadata == null) {
        logWarning(_logTag, "LoadProjectCommand failed: Metadata not found for ID $projectId");
        // Clear the metadata notifier if metadata isn't found
        await _metadataService.closeProject(); // Clears notifier
        return; // Stop execution if metadata doesn't exist
      }
      
      // 2. Update Metadata Notifier
      _metadataService.currentProjectMetadataNotifier.value = projectMetadata;
      logInfo(_logTag, "Updated metadata notifier for project: ${projectMetadata.name}");

      // 3. Load Project Data via Database Service
      // This service loads data based on the *currently set* metadata
      // It should internally get the path from the metadata service's notifier
      await _databaseService.loadProject(projectId);

      // 4. Save Project ID to Preferences and Init Undo/Redo
      // Check notifier *after* attempting to load data
      if (_metadataService.currentProjectMetadataNotifier.value?.id == projectId) {
        await _prefs.setInt(_lastProjectIdKey, projectId);
        logInfo(_logTag, "Saved project ID $projectId to SharedPreferences");

        try {
          await _undoRedoService.init();
          logInfo(_logTag, 'UndoRedoService initialized for project $projectId');
        } catch (e) {
          logError(_logTag, 'Error initializing UndoRedoService: $e');
        }
         logInfo(_logTag, "LoadProjectCommand successful for ID: $projectId");
      } else {
        // This might happen if _databaseService.loadProject fails and resets the notifier
        logWarning(_logTag, "LoadProjectCommand completed, but metadata notifier ID doesn't match $projectId after data load attempt.");
      }

    } catch (e) {
      logError(_logTag, "Error executing LoadProjectCommand: $e");
      await _metadataService.closeProject(); // Ensure notifier is cleared on error
      rethrow;
    }
  }
} 