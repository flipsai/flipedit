import 'dart:async';

import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

const _logTag = 'LoadProjectCommand';
const _lastProjectIdKey = 'last_opened_project_id';

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

  Future<void> execute(int projectId) async {
    logInfo(_logTag, "Executing LoadProjectCommand for ID: $projectId");
    try {
      final ProjectMetadata? projectMetadata = await _projectMetadataDao
          .getProjectMetadataById(projectId);

      if (projectMetadata == null) {
        logWarning(
          _logTag,
          "LoadProjectCommand failed: Metadata not found for ID $projectId",
        );
        await _metadataService.closeProject();
        return;
      }

      _metadataService.currentProjectMetadataNotifier.value = projectMetadata;
      logInfo(
        _logTag,
        "Updated metadata notifier for project: ${projectMetadata.name}",
      );

      await _databaseService.loadProject(projectId);

      if (_metadataService.currentProjectMetadataNotifier.value?.id ==
          projectId) {
        await _prefs.setInt(_lastProjectIdKey, projectId);
        logInfo(_logTag, "Saved project ID $projectId to SharedPreferences");

        try {
          await _undoRedoService.init();
          logInfo(
            _logTag,
            'UndoRedoService initialized for project $projectId',
          );
        } catch (e) {
          logError(_logTag, 'Error initializing UndoRedoService: $e');
        }
        logInfo(_logTag, "LoadProjectCommand successful for ID: $projectId");
      } else {
        logWarning(
          _logTag,
          "LoadProjectCommand completed, but metadata notifier ID doesn't match $projectId after data load attempt.",
        );
      }
    } catch (e) {
      logError(_logTag, "Error executing LoadProjectCommand: $e");
      await _metadataService.closeProject();
      rethrow;
    }
  }
}
