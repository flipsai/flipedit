import 'package:drift/drift.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async'; // Import for StreamSubscription

import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

class ProjectService {
  final ProjectDao _projectDao = di<ProjectDao>();
  final TrackDao _trackDao = di<TrackDao>();
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();

  /// Notifier for the currently loaded project.
  /// Other services/viewmodels can watch this.
  final ValueNotifier<Project?> currentProjectNotifier = ValueNotifier(null);

  /// Notifier for the tracks of the currently loaded project.
  final ValueNotifier<List<Track>> currentProjectTracksNotifier = ValueNotifier([]);

  StreamSubscription<List<Track>>? _tracksSubscription; // To manage the stream subscription

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
    currentProjectTracksNotifier.value = []; // Clear old tracks immediately

    final project = await _projectDao.getProjectById(projectId);
    currentProjectNotifier.value = project;

    if (project != null) {
      print("Loaded project: ${project.name}");
      windowManager.setTitle('${project.name} - FlipEdit');

      // Watch tracks for the loaded project
      _tracksSubscription = _trackDao.watchTracksForProject(projectId).listen((tracks) {
        currentProjectTracksNotifier.value = tracks;
        print("Updated tracks for project ${project.id}: ${tracks.length} tracks");
        
        // TODO: Decide if clips should reload every time tracks change, or just on initial load.
        // For now, let's load clips *after* tracks are loaded.
        // _timelineViewModel.loadClipsForProject(projectId); 
        
      }, onError: (error) {
        print("Error watching tracks for project $projectId: $error");
        // Handle error appropriately
      });

      // --- Load Clips using TimelineViewModel --- 
      // Call this *after* setting the project notifier and confirming project is not null.
      await _timelineViewModel.loadClipsForProject(projectId);

      // Watch tracks for the loaded project
      _tracksSubscription = _trackDao.watchTracksForProject(projectId).listen((tracks) {
        currentProjectTracksNotifier.value = tracks;
        print("Updated tracks for project ${project.id}: ${tracks.length} tracks");
      }, onError: (error) {
        print("Error watching tracks for project $projectId: $error");
        // Handle error appropriately
      });
    } else {
      print("Failed to load project with ID: $projectId");
      windowManager.setTitle('FlipEdit');
      _tracksSubscription = null; // Ensure no lingering subscription
    }
  }

  /// Clears the currently loaded project and its tracks.
  Future<void> closeProject() async { // Made async to await cancel
    await _tracksSubscription?.cancel(); // Cancel subscription
    _tracksSubscription = null;
    currentProjectNotifier.value = null;
    currentProjectTracksNotifier.value = []; // Clear tracks
    print("Closed current project and cleared tracks.");
    windowManager.setTitle('FlipEdit');
  }

  // --- Methods for managing tracks ---

  /// Adds a new track to the currently loaded project.
  Future<void> addTrack({required String type}) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      print("Cannot add track: No project loaded.");
      return;
    }

    // Determine the order for the new track
    final currentTracks = currentProjectTracksNotifier.value;
    final nextOrder = currentTracks.isNotEmpty ? currentTracks.last.order + 1 : 0;

    final companion = TracksCompanion(
      projectId: Value(currentProjectId),
      type: Value(type),
      order: Value(nextOrder), // Set order based on existing tracks
      // name can use default
    );

    try {
      final trackId = await _trackDao.insertTrack(companion);
      print("Added new '$type' track with ID: $trackId to project $currentProjectId");
    } catch (e) {
      print("Error adding track: $e");
      // Handle error (e.g., show a message to the user)
    }
  }

  /// Removes a track by its ID.
  Future<void> removeTrack(int trackId) async {
    final currentProjectId = currentProjectNotifier.value?.id;
    if (currentProjectId == null) {
      print("Cannot remove track: No project loaded.");
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
        print("Removed track with ID: $trackId");
        // Note: The watcher (`currentProjectTracksNotifier`) will automatically update the list.
      } else {
        print("Could not remove track with ID: $trackId (maybe it was already deleted?)");
      }
    } catch (e) {
      print("Error removing track $trackId: $e");
      // Handle error
    }
  }

  // --- Method for saving the current project ---
  Future<void> saveProject() async {
    final currentProject = currentProjectNotifier.value;
    if (currentProject == null) {
      print("Cannot save: No project loaded.");
      return;
    }

    try {
      // Removed the attempt to update lastModifiedAt as it's not needed/
      // causing issues for now.

      // Placeholder for actual save logic:
      print("Project ${currentProject.id} save action triggered (no data saved yet).");

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
        print("Failed to save project ${currentProject.id} (simulated or actual failure).");
      }
    } catch (e) {
      print("Error during save project ${currentProject.id}: $e");
      // Handle error
    }
  }

  // --- Add methods for managing clips/tracks associated with the current project later ---
} 