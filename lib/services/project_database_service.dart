import 'dart:async';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/dao/project_database_track_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:drift/drift.dart';

/// Service for working with per-project databases
class ProjectDatabaseService {
  final String _logTag = 'ProjectDatabaseService';
  
  final ProjectMetadataService _metadataService = di<ProjectMetadataService>();
  
  // The current active project database
  ProjectDatabase? _currentDatabase;
  
  // The current active DAOs
  ProjectDatabaseTrackDao? _trackDao;
  ProjectDatabaseClipDao? _clipDao;
  
  // Value notifiers for reactive UI
  final ValueNotifier<List<Track>> tracksNotifier = ValueNotifier<List<Track>>([]);
  
  // Stream subscriptions
  StreamSubscription<List<Track>>? _tracksSubscription;
  
  /// Load a project by its ID and initialize all necessary DAOs and subscriptions
  Future<bool> loadProject(int projectId) async {
    try {
      // First close any open project
      await closeCurrentProject();
      
      // Load the project database using the metadata service
      final database = await _metadataService.loadProject(projectId);
      if (database == null) {
        logError(_logTag, "Failed to load project database for ID: $projectId");
        return false;
      }
      
      _currentDatabase = database;
      
      // Initialize DAOs
      _trackDao = ProjectDatabaseTrackDao(_currentDatabase!);
      _clipDao = ProjectDatabaseClipDao(_currentDatabase!);
      
      // Start watching tracks
      _tracksSubscription = _trackDao!.watchAllTracks().listen((tracks) {
        tracksNotifier.value = tracks;
        logInfo(_logTag, "Updated tracks: ${tracks.length} tracks");
      }, onError: (error) {
        logError(_logTag, "Error watching tracks: $error");
      });
      
      logInfo(_logTag, "Successfully loaded project database for ID: $projectId");
      return true;
    } catch (e) {
      logError(_logTag, "Error loading project database: $e");
      await closeCurrentProject();
      return false;
    }
  }
  
  /// Close the current project and clean up resources
  Future<void> closeCurrentProject() async {
    // Cancel subscriptions
    await _tracksSubscription?.cancel();
    _tracksSubscription = null;
    
    // Clear data
    tracksNotifier.value = [];
    
    // Close database
    if (_currentDatabase != null) {
      await _currentDatabase!.closeConnection();
      _currentDatabase = null;
      _trackDao = null;
      _clipDao = null;
    }
    
    logInfo(_logTag, "Closed current project database");
  }
  
  /// Add a new track to the current project
  Future<int?> addTrack({
    required String type,
    String? name,
    int? order,
  }) async {
    if (_trackDao == null || _currentDatabase == null) {
      logError(_logTag, "Cannot add track: No project loaded");
      return null;
    }
    
    try {
      final currentTracks = tracksNotifier.value;
      final nextOrder = order ?? (currentTracks.isNotEmpty ? currentTracks.last.order + 1 : 0);
      
      final trackCompanion = TracksCompanion(
        type: Value(type),
        order: Value(nextOrder),
        name: name != null ? Value(name) : const Value.absent(),
      );
      
      final trackId = await _trackDao!.insertTrack(trackCompanion);
      logInfo(_logTag, "Added new '$type' track with ID: $trackId");
      return trackId;
    } catch (e) {
      logError(_logTag, "Error adding track: $e");
      return null;
    }
  }
  
  /// Delete a track by ID
  Future<bool> deleteTrack(int trackId) async {
    if (_trackDao == null) {
      logError(_logTag, "Cannot delete track: No project loaded");
      return false;
    }
    
    try {
      final deletedCount = await _trackDao!.deleteTrack(trackId);
      if (deletedCount > 0) {
        logInfo(_logTag, "Deleted track with ID: $trackId");
        return true;
      } else {
        logWarning(_logTag, "Track with ID $trackId not found or already deleted");
        return false;
      }
    } catch (e) {
      logError(_logTag, "Error deleting track: $e");
      return false;
    }
  }
  
  /// Rename a track
  Future<bool> updateTrackName(int trackId, String newName) async {
    if (_trackDao == null) {
      logError(_logTag, "Cannot rename track: No project loaded");
      return false;
    }
    
    try {
      final companion = TracksCompanion(
        id: Value(trackId),
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      );
      
      final success = await _trackDao!.updateTrack(companion);
      if (success) {
        logInfo(_logTag, "Renamed track $trackId to '$newName'");
        return true;
      } else {
        logWarning(_logTag, "Failed to rename track $trackId");
        return false;
      }
    } catch (e) {
      logError(_logTag, "Error renaming track: $e");
      return false;
    }
  }
  
  // Add public getters to access the DAOs
  ProjectDatabaseTrackDao? get trackDao => _trackDao;
  ProjectDatabaseClipDao? get clipDao => _clipDao;
} 