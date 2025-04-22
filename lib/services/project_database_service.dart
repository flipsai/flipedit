import 'dart:async';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/persistence/dao/project_database_asset_dao.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/dao/project_database_track_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart' hide ProjectAsset;
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:drift/drift.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/dao/change_log_dao.dart';

/// Service for working with per-project databases
class ProjectDatabaseService {
  final String _logTag = 'ProjectDatabaseService';
  
  final ProjectMetadataService _metadataService = di<ProjectMetadataService>();
  
  // The current active project database
  ProjectDatabase? _currentDatabase;
  
  // The current active DAOs
  ProjectDatabaseTrackDao? _trackDao;
  ProjectDatabaseClipDao? _clipDao;
  ProjectDatabaseAssetDao? _assetDao;
  
  // Value notifiers for reactive UI
  final ValueNotifier<List<Track>> tracksNotifier = ValueNotifier<List<Track>>([]);
  final ValueNotifier<List<model.ProjectAsset>> assetsNotifier = ValueNotifier<List<model.ProjectAsset>>([]);
  
  // Stream subscriptions
  StreamSubscription<List<Track>>? _tracksSubscription;
  StreamSubscription<List<model.ProjectAsset>>? _assetsSubscription;
  
  /// Load a project by its ID and initialize all necessary DAOs and subscriptions
  Future<bool> loadProject(int projectId) async {
    try {
      // First close any open project
      await closeCurrentProject();
      
      // Get the current project metadata from the metadata service
      final currentMetadata = _metadataService.currentProjectMetadataNotifier.value;
      
      // Verify the metadata is for the requested project ID
      if (currentMetadata == null || currentMetadata.id != projectId) {
        logError(_logTag, "Metadata mismatch: Cannot load database for project $projectId. Expected metadata for this ID.");
        // Optionally, try to fetch the metadata again, but LoadProjectCommand should have set it.
        // For now, fail the load.
        return false;
      }
      
      // Get the database path from the metadata
      final databasePath = currentMetadata.databasePath;
      logInfo(_logTag, "Opening project database at path: $databasePath for ID: $projectId");
      
      // Open the database connection
      _currentDatabase = ProjectDatabase(databasePath);
      
      // Initialize DAOs with the new database connection
      _trackDao = ProjectDatabaseTrackDao(_currentDatabase!);
      _clipDao = ProjectDatabaseClipDao(_currentDatabase!);
      _assetDao = ProjectDatabaseAssetDao(_currentDatabase!);
      
      // Start watching tracks
      _tracksSubscription = _trackDao!.watchAllTracks().listen((tracks) {
        tracksNotifier.value = tracks;
        logInfo(_logTag, "Updated tracks: ${tracks.length} tracks");
      }, onError: (error) {
        logError(_logTag, "Error watching tracks: $error");
      });
      
      // Start watching assets
      _assetsSubscription = _assetDao!.watchAllAssets().listen((assets) {
        assetsNotifier.value = assets;
        logInfo(_logTag, "Updated assets: ${assets.length} assets");
      }, onError: (error) {
        logError(_logTag, "Error watching assets: $error");
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
    
    await _assetsSubscription?.cancel();
    _assetsSubscription = null;
    
    // Clear data
    tracksNotifier.value = [];
    assetsNotifier.value = [];
    
    // Close database
    if (_currentDatabase != null) {
      await _currentDatabase!.closeConnection();
      _currentDatabase = null;
      _trackDao = null;
      _clipDao = null;
      _assetDao = null;
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
  
  /// Import a media asset to the project
  Future<int?> importAsset({
    required String filePath,
    required ClipType type,
    required int durationMs,
    int? width,
    int? height,
    double? fileSize,
    String? thumbnailPath,
  }) async {
    if (_assetDao == null || _currentDatabase == null) {
      logError(_logTag, "Cannot import asset: No project loaded");
      return null;
    }
    
    try {
      final assetId = await _assetDao!.importAsset(
        filePath: filePath,
        type: type,
        durationMs: durationMs,
        width: width,
        height: height,
        fileSize: fileSize,
        thumbnailPath: thumbnailPath,
      );
      
      logInfo(_logTag, "Imported asset with ID: $assetId");
      return assetId;
    } catch (e) {
      logError(_logTag, "Error importing asset: $e");
      return null;
    }
  }
  
  /// Delete an asset by ID
  Future<bool> deleteAsset(int assetId) async {
    if (_assetDao == null) {
      logError(_logTag, "Cannot delete asset: No project loaded");
      return false;
    }
    
    try {
      final deletedCount = await _assetDao!.deleteAsset(assetId);
      if (deletedCount > 0) {
        logInfo(_logTag, "Deleted asset with ID: $assetId");
        return true;
      } else {
        logWarning(_logTag, "Asset with ID $assetId not found or already deleted");
        return false;
      }
    } catch (e) {
      logError(_logTag, "Error deleting asset: $e");
      return false;
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
  ProjectDatabaseAssetDao? get assetDao => _assetDao;
  
  /// DAO for reading change logs
  ChangeLogDao get changeLogDao {
    if (_currentDatabase == null) {
      throw StateError('No project loaded');
    }
    return ChangeLogDao(_currentDatabase!);
  }
} 