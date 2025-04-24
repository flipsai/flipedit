import 'dart:async';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/utils/logger.dart';

const _logTag = 'CreateProjectCommand';

class CreateProjectCommand {
  final ProjectMetadataService _metadataService;

  CreateProjectCommand(this._metadataService);

  /// Creates a new project metadata entry and its database.
  /// Returns the ID of the newly created project.
  Future<int> execute({required String name}) async {
    if (name.trim().isEmpty) {
      logWarning(_logTag, "Project name cannot be empty.");
      // Consider throwing an ArgumentError or returning a specific result object
      // For now, rethrow the error similar to original ViewModel logic
      throw ArgumentError('Project name cannot be empty.');
    }

    logInfo(_logTag, "Executing CreateProjectCommand for name: '$name'");
    try {
      // Delegate the actual creation logic to the service
      final projectId = await _metadataService.createNewProject(name: name.trim());
      logInfo(_logTag, "CreateProjectCommand successful, Project ID: $projectId");
      return projectId;
    } catch (e) {
      logError(_logTag, "Error executing CreateProjectCommand: $e");
      rethrow; // Rethrow the exception to be handled by the caller
    }
  }
} 