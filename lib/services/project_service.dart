import 'package:drift/drift.dart';
import 'package:flipedit/models/project_asset.dart';
import 'package:flipedit/persistence/dao/project_asset_dao.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async'; // Import for StreamSubscription

import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

class ProjectService {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final ProjectDao _projectDao = di<ProjectDao>();
  final TrackDao _trackDao = di<TrackDao>();
  final ProjectAssetDao _projectAssetDao = di<ProjectAssetDao>();
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();

  /// Notifier for the currently loaded project.
  /// Other services/viewmodels can watch this.
  final ValueNotifier<Project?> currentProjectNotifier = ValueNotifier(null);

  /// Notifier for the tracks of the currently loaded project.
  final ValueNotifier<List<Track>> currentProjectTracksNotifier = ValueNotifier([]);

  final ValueNotifier<List<ProjectAsset>> currentProjectAssetsNotifier =
      ValueNotifier([]);

  StreamSubscription<List<Track>>? _tracksSubscription;
  StreamSubscription<List<ProjectAssetEntry>>? _assetsSubscription;

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
    await _tracksSubscription?.cancel(); // Cancel previous subscription if any
    await _assetsSubscription?.cancel(); // Cancel asset subscription
    currentProjectTracksNotifier.value = []; // Clear old tracks immediately
    currentProjectAssetsNotifier.value = []; // Clear old assets immediately

    final project = await _projectDao.getProjectById(projectId);
    currentProjectNotifier.value = project;

    if (project != null) {
      logInfo(
          _logTag, "Loaded project: ${project.name}"); // Use top-level function with tag
      windowManager.setTitle('${project.name} - FlipEdit');

      // Watch tracks for the loaded project
      _tracksSubscription = _trackDao
          .watchTracksForProject(projectId)
          .listen((tracks) {
        currentProjectTracksNotifier.value = tracks;
        logInfo(_logTag,
            "Updated tracks for project ${project.id}: ${tracks.length} tracks"); // Use top-level function with tag

        // TODO: Decide if clips should reload every time tracks change, or just on initial load.
        // For now, let's load clips *after* tracks are loaded.
        // _timelineViewModel.loadClipsForProject(projectId);
      }, onError: (error) {
        logError(
            _logTag,
            "Error watching tracks for project $projectId: $error"); // Use top-level function with tag
        // Handle error appropriately
      });

      // Watch assets for the loaded project
      _assetsSubscription = _projectAssetDao
          .watchAssetsForProject(projectId)
          .listen((assetEntries) {
        // Map Database entries to Domain models
        final assets = assetEntries
            .map((entry) => ProjectAsset(
                  databaseId: entry.id,
                  name: entry.name,
                  type: entry.type,
                  sourcePath: entry.sourcePath,
                  durationMs: entry.durationMs,
                ))
            .toList();
        currentProjectAssetsNotifier.value = assets;
        logInfo(_logTag,
            "Updated assets for project ${project.id}: ${assets.length} assets");
      }, onError: (error) {
        logError(
            _logTag,
            "Error watching assets for project $projectId: $error");
      });

      // --- Load Clips using TimelineViewModel --- 
      // Call this *after* setting the project notifier and confirming project is not null.
      await _timelineViewModel.loadClipsForProject(projectId);
    } else {
      logWarning(
          _logTag,
          "Failed to load project with ID: $projectId"); // Use top-level function with tag
      windowManager.setTitle('FlipEdit');
      _tracksSubscription = null; // Ensure no lingering subscription
      _assetsSubscription = null; // Ensure no lingering asset subscription
    }
  }

  /// Clears the currently loaded project and its tracks.
  Future<void> closeProject() async { // Made async to await cancel
    await _tracksSubscription?.cancel(); // Cancel subscription
    await _assetsSubscription?.cancel(); // Cancel asset subscription
    _tracksSubscription = null;
    _assetsSubscription = null;
    currentProjectNotifier.value = null;
    currentProjectTracksNotifier.value = []; // Clear tracks
    currentProjectAssetsNotifier.value = []; // Clear assets
    logInfo(
        _logTag,
        "Closed current project and cleared tracks/assets."); // Use top-level function with tag
    windowManager.setTitle('FlipEdit');
  }

  // --- Methods for managing tracks ---

  /// Adds a new track to the currently loaded project.
  Future<void> addTrack({required String type}) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(
          _logTag,
          "Cannot add track: No project loaded."); // Use top-level function with tag
      return;
    }

    // Determine the order for the new track
    final currentTracks = currentProjectTracksNotifier.value;
    final nextOrder =
        currentTracks.isNotEmpty ? currentTracks.last.order + 1 : 0;

    final companion = TracksCompanion(
      projectId: Value(currentProjectId),
      type: Value(type),
      order: Value(nextOrder), // Set order based on existing tracks
      // name can use default
    );

    try {
      final trackId = await _trackDao.insertTrack(companion);
      logInfo(
          _logTag,
          "Added new '$type' track with ID: $trackId to project $currentProjectId"); // Use top-level function with tag
    } catch (e) {
      logError(_logTag, "Error adding track: $e"); // Use top-level function with tag
      // Handle error (e.g., show a message to the user)
    }
  }

  /// Removes a track by its ID.
  Future<void> removeTrack(int trackId) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(
          _logTag,
          "Cannot remove track: No project loaded."); // Use top-level function with tag
      return;
    }

    // Optional: Check if the track actually belongs to the current project (for safety)
    // final track = await _trackDao.getTrackById(trackId); // Assuming getTrackById exists
    // if (track == null || track.projectId != currentProjectId) {
    //   print("Track $trackId does not belong to project $currentProjectId or does not exist.");
    //   return;
    // }

    try {
      final deletedCount = await _trackDao.deleteTrack(trackId);
      if (deletedCount > 0) {
        logInfo(
            _logTag,
            "Removed track with ID: $trackId"); // Use top-level function with tag
        // Note: The watcher (`currentProjectTracksNotifier`) will automatically update the list.
      } else {
        logWarning(
            _logTag,
            "Could not remove track with ID: $trackId (maybe it was already deleted?)"); // Use top-level function with tag
      }
    } catch (e) {
      logError(
          _logTag,
          "Error removing track $trackId: $e"); // Use top-level function with tag
      // Handle error
    }
  }

  /// Updates the name of a specific track.
  Future<void> updateTrackName(int trackId, String newName) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(
          _logTag,
          "Cannot update track name: No project loaded.");
      return;
    }

    // Optional: Verify track belongs to the current project before updating
    // final track = await _trackDao.getTrackById(trackId); // Requires getTrackById in DAO
    // if (track == null || track.projectId != currentProjectId) {
    //   logWarning(_logTag, "Track $trackId does not belong to project $currentProjectId or does not exist.");
    //   return;
    // }

    final companion = TracksCompanion(
      id: Value(trackId),
      name: Value(newName),
    );

    try {
      final success = await _trackDao.updateTrack(companion);
      if (success) {
        logInfo(
            _logTag,
            "Updated name for track $trackId to '$newName'");
        // The watcher (`currentProjectTracksNotifier`) will automatically update the UI.
      } else {
        logWarning(
            _logTag,
            "Could not update name for track $trackId (track not found?).");
      }
    } catch (e) {
      logError(
          _logTag,
          "Error updating name for track $trackId: $e");
      // Handle error
    }
  }

  /// Renames a specific track.
  Future<void> renameTrack(int trackId, String newName) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(_logTag, "Cannot rename track: No project loaded.");
      return;
    }

    if (newName.trim().isEmpty) {
      logWarning(_logTag, "Cannot rename track $trackId: New name cannot be empty.");
      // Optionally provide user feedback here
      return;
    }

    // Optional: Verify track belongs to the current project before updating
    // This requires a `getTrackById` method in your DAO
    // final track = await _trackDao.getTrackById(trackId);
    // if (track == null || track.projectId != currentProjectId) {
    //   logWarning(_logTag, "Track $trackId does not belong to project $currentProjectId or does not exist.");
    //   return;
    // }

    final companion = TracksCompanion(
      id: Value(trackId), // Specify the ID of the track to update
      projectId: Value(currentProjectId), // Add projectId
      name: Value(newName), // Set the new name
    );

    try {
      // Assuming trackDao.updateTrack returns a boolean indicating success
      final success = await _trackDao.updateTrack(companion);
      if (success) {
        logInfo(_logTag, "Renamed track $trackId to '$newName'");
        // The watcher (`currentProjectTracksNotifier`) should automatically update the UI
        // because the underlying data stream from Drift will emit the updated track list.
      } else {
        logWarning(_logTag, "Could not rename track $trackId (track not found or update failed).");
      }
    } catch (e) {
      logError(_logTag, "Error renaming track $trackId: $e");
      // Handle error (e.g., show a message to the user)
    }
  }

  // --- Method for saving the current project ---
  Future<void> saveProject() async {
    final currentProject = currentProjectNotifier.value;
    if (currentProject == null) {
      logWarning(
          _logTag,
          "Cannot save: No project loaded."); // Use top-level function with tag
      return;
    }

    try {
      // Removed the attempt to update lastModifiedAt as it's not needed/
      // causing issues for now.

      // Placeholder for actual save logic:
      logInfo(
          _logTag,
          "Project ${currentProject.id} save action triggered (no data saved yet)."); // Use top-level function with tag

      // Example: If you needed to update the project name (assuming DAO supports it)
      // final updateCompanion = ProjectsCompanion(id: Value(currentProject.id), name: Value("New Name"));
      // final success = await _projectDao.updateProject(updateCompanion);
      // if (success) { ... } else { ... }

      // TODO: Implement saving of tracks, clips, effects, etc., when needed.
      // For now, we simulate success.
      bool success = true; // Assume success for now

      if (success) {
         // If other data were saved and the project object needed updating in memory,
         // you might fetch it again or update the notifier manually here.
         // For now, no changes to the in-memory project object.
      } else {
        logError(
            _logTag,
            "Failed to save project ${currentProject.id} (simulated or actual failure)."); // Use top-level function with tag
      }
    } catch (e) {
      logError(
          _logTag,
          "Error during save project ${currentProject.id}: $e"); // Use top-level function with tag
      // Handle error
    }
  }

  // --- Add methods for managing project assets ---
  Future<void> addProjectAsset(ProjectAsset asset) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(_logTag, "Cannot add asset: No project loaded.");
      return;
    }

    final companion = ProjectAssetsCompanion(
      projectId: Value(currentProjectId),
      name: Value(asset.name),
      type: Value(asset.type),
      sourcePath: Value(asset.sourcePath),
      durationMs: Value(asset.durationMs),
    );

    try {
      final assetId = await _projectAssetDao.addAsset(companion);
      logInfo(_logTag, "Added asset '$assetId' to project $currentProjectId");
    } catch (e) {
      logError(_logTag, "Error adding project asset: $e");
    }
  }

  Future<void> removeProjectAsset(int assetId) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      logWarning(_logTag, "Cannot remove asset: No project loaded.");
      return;
    }
    // Optional: Verify asset belongs to project before deleting?
    try {
      final deletedCount = await _projectAssetDao.deleteAsset(assetId);
      if (deletedCount > 0) {
        logInfo(_logTag, "Removed asset $assetId from project $currentProjectId");
      } else {
        logWarning(
            _logTag, "Could not remove asset $assetId (maybe already deleted?)");
      }
    } catch (e) {
      logError(_logTag, "Error removing project asset $assetId: $e");
    }
  }
} 