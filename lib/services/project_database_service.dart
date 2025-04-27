import 'dart:async';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'package:flipedit/persistence/dao/project_database_asset_dao.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/dao/project_database_track_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart'
    hide ProjectAsset;
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
  ProjectDatabase? currentDatabase;

  // The current active DAOs
  ProjectDatabaseTrackDao? _trackDao;
  ProjectDatabaseClipDao? _clipDao;
  ProjectDatabaseAssetDao? _assetDao;

  // Value notifiers for reactive UI
  final ValueNotifier<List<Track>> tracksNotifier = ValueNotifier<List<Track>>(
    [],
  );
  final ValueNotifier<List<model.ProjectAsset>> assetsNotifier =
      ValueNotifier<List<model.ProjectAsset>>([]);

  // Stream subscriptions
  StreamSubscription<List<Track>>? _tracksSubscription;
  StreamSubscription<List<model.ProjectAsset>>? _assetsSubscription;

  /// Load a project by its ID and initialize all necessary DAOs and subscriptions
  Future<bool> loadProject(int projectId) async {
    try {
      // First close any open project
      await closeCurrentProject();

      // Get the current project metadata from the metadata service
      final currentMetadata =
          _metadataService.currentProjectMetadataNotifier.value;

      // Verify the metadata is for the requested project ID
      if (currentMetadata == null || currentMetadata.id != projectId) {
        logError(
          _logTag,
          "Metadata mismatch: Cannot load database for project $projectId. Expected metadata for this ID.",
        );
        // Optionally, try to fetch the metadata again, but LoadProjectCommand should have set it.
        // For now, fail the load.
        return false;
      }

      // Get the database path from the metadata
      final databasePath = currentMetadata.databasePath;
      logInfo(
        _logTag,
        "Opening project database at path: $databasePath for ID: $projectId",
      );

      // Open the database connection
      currentDatabase = ProjectDatabase(databasePath);

      // Initialize DAOs with the new database connection
      _trackDao = ProjectDatabaseTrackDao(currentDatabase!);
      _clipDao = ProjectDatabaseClipDao(currentDatabase!);
      _assetDao = ProjectDatabaseAssetDao(currentDatabase!);

      // Start watching tracks
      _tracksSubscription = _trackDao!.watchAllTracks().listen(
        (updatedTracks) {
          // Log the received tracks, including the name of the first track if available
          final firstTrackName =
              updatedTracks.isNotEmpty ? updatedTracks.first.name : 'N/A';
          logInfo(
            _logTag,
            "🔔 Tracks Stream Update Received: ${updatedTracks.length} tracks. First track name: '$firstTrackName'",
          );

          // Check if the update is different from the current value to avoid unnecessary updates
          if (!listEquals(tracksNotifier.value, updatedTracks)) {
            tracksNotifier.value = updatedTracks;
            logInfo(_logTag, "✅ tracksNotifier updated.");
          } else {
            logInfo(
              _logTag,
              "ℹ️ Tracks Stream Update Received, but data is identical to current state. Notifier not updated.",
            );
          }
        },
        onError: (error) {
          logError(_logTag, "❌ Error watching tracks stream: $error");
        },
      );

      // Start watching assets
      _assetsSubscription = _assetDao!.watchAllAssets().listen(
        (assets) {
          assetsNotifier.value = assets;
          logInfo(_logTag, "Updated assets: ${assets.length} assets");
        },
        onError: (error) {
          logError(_logTag, "Error watching assets: $error");
        },
      );

      logInfo(
        _logTag,
        "Successfully loaded project database for ID: $projectId",
      );
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
    if (currentDatabase != null) {
      await currentDatabase!.closeConnection();
      currentDatabase = null;
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
    if (_trackDao == null || currentDatabase == null) {
      logError(_logTag, "Cannot add track: No project loaded");
      return null;
    }

    try {
      final currentTracks = tracksNotifier.value;
      final nextOrder =
          order ??
          (currentTracks.isNotEmpty ? currentTracks.last.order + 1 : 0);

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
    if (_assetDao == null || currentDatabase == null) {
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

      // Manually refresh the assets notifier after successful import
      final updatedAssets =
          await _assetDao!.getAllAssets(); // Fetch the updated list
      assetsNotifier.value = updatedAssets; // Update the notifier
      logInfo(
        _logTag,
        "Imported asset with ID: $assetId and refreshed notifier.",
      );

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
        logWarning(
          _logTag,
          "Asset with ID $assetId not found or already deleted",
        );
        return false;
      }
    } catch (e) {
      logError(_logTag, "Error deleting asset: $e");
      return false;
    }
  }

  /// Delete a track by ID and its associated clips
  Future<bool> deleteTrack(int trackId) async {
    if (_trackDao == null || _clipDao == null || currentDatabase == null) {
      logError(_logTag, "Cannot delete track: No project loaded or DAOs not initialized");
      return false;
    }

    try {
      // Perform deletion within a transaction for data integrity
      await currentDatabase!.transaction(() async {
        // Delete all clips associated with this track
        final clipsDeletedCount = await _clipDao!.deleteClipsForTrack(trackId); // Corrected method name
        logInfo(_logTag, "Deleted $clipsDeletedCount clips for track ID: $trackId");

        // Delete the track itself
        final trackDeletedCount = await _trackDao!.deleteTrack(trackId);
        if (trackDeletedCount > 0) {
          logInfo(_logTag, "Deleted track with ID: $trackId");
        } else {
           logWarning(
            _logTag,
            "Track with ID $trackId not found or already deleted during transaction",
          );
        }
      });

      // After successful transaction, explicitly refresh the tracks and assets notifiers
      // This is important because the TimelineViewModel relies on these to update its state.
      final updatedTracks = await _trackDao!.getAllTracks();
      tracksNotifier.value = updatedTracks;
      logInfo(_logTag, "Refreshed tracksNotifier after deleting track $trackId.");

      // Although assets are not directly deleted with a track, refreshing them here
      // might be part of a broader update sequence or just safe practice.
      // However, the core fix is tracks and clips. Assets should not change on track delete.
      // Let's omit assets refresh for now, focus on tracks and clips.
      // final updatedAssets = await _assetDao!.getAllAssets();
      // assetsNotifier.value = updatedAssets;

      // Check if the track is actually gone from the in-memory list after deletion
      if (!tracksNotifier.value.any((t) => t.id == trackId)) {
           logInfo(_logTag, "Track $trackId successfully removed from tracksNotifier.");
      } else {
           logWarning(_logTag, "Track $trackId is still present in tracksNotifier after deletion attempt.");
      }


      // The tracksNotifier stream will eventually cause the TimelineViewModel to reload/re-evaluate clips.
      // Explicitly checking if any clips for the deleted track are *still* in the clip DAO after the transaction
      // could be another diagnostic step, but the transaction *should* handle it.

      // Assuming successful transaction means deletion happened.
      // The boolean return value is a bit ambiguous with transaction.
      // Let's return true if the track is no longer in the notifier after refresh.
       return !tracksNotifier.value.any((t) => t.id == trackId);

    } catch (e) {
      logError(_logTag, "Error deleting track $trackId and associated clips: $e");
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

      // DAO's updateTrack now returns Future<int> (rows affected)
      final affectedRows = await _trackDao!.updateTrack(companion);

      // Consider the update successful if 1 or more rows were affected
      if (affectedRows > 0) {
        logInfo(
          _logTag,
          "Renamed track $trackId to '$newName' ($affectedRows row(s) affected)",
        );
        return true; // Return true if successful
      } else {
        logWarning(
          _logTag,
          "Failed to rename track $trackId (0 rows affected)",
        );
        return false; // Return false if no rows were affected
      }
    } catch (e) {
      logError(_logTag, "Error renaming track: $e");
      return false;
    }
  }

  /// Update the order of tracks in the database
  Future<bool> updateTrackOrder(List<Track> reorderedTracks) async {
    if (_trackDao == null || currentDatabase == null) {
      logError(_logTag, "Cannot update track order: No project loaded");
      return false;
    }

    // Calculate the final track order, but DON'T update the notifier optimistically yet.
    final updatedTracksWithOrder = List<Track>.generate(
      reorderedTracks.length,
      (index) => reorderedTracks[index].copyWith(order: index),
    );
    // tracksNotifier.value = updatedTracks; // REMOVED: Avoid optimistic update causing race condition
    
    // Now update the database in the background
    logInfo(
      _logTag,
      "Starting database transaction for updating order of ${updatedTracksWithOrder.length} tracks",
    );
      
    try {
      // Attempt the update using the transaction-wrapped DAO method
      // Pass the list with the correct order calculated
      await _trackDao!.updateTrackOrders(updatedTracksWithOrder);
      logInfo(
        _logTag,
        "Successfully updated track order in database via transaction. UI will update via stream.",
      );
      // The tracksNotifier will be updated automatically by the watchAllTracks stream listener
      // once the transaction is committed.
      return true;
    } catch (dbError) {
      // If the transaction fails (e.g., due to existing lock), log the error.
      logError(
        _logTag,
        "Database transaction for updating track order failed: $dbError. UI state remains unchanged.",
      );
      return false; 
    }
  }

  /// Fetches all clips from all tracks and maps them to ClipModel.
  Future<List<ClipModel>> getAllTimelineClips() async {
    if (clipDao == null || currentDatabase == null) {
      logWarning(
        _logTag,
        'Clip DAO or database not available, cannot fetch all timeline clips.',
      );
      return [];
    }

    logInfo(_logTag, 'Fetching all timeline clips from database...');

    final tracks = tracksNotifier.value; // Use the current tracks from the notifier
    List<ClipModel> allClips = [];

    try {
      for (final track in tracks.where((t) => t.id != null)) {
        final dbClips = await clipDao!.getClipsForTrack(track.id!);
        allClips.addAll(dbClips.map((dbClip) {
          // Estimate source duration if missing from DB data
          final sourceDuration = dbClip.sourceDurationMs ??
              (dbClip.endTimeInSourceMs - dbClip.startTimeInSourceMs)
                  .clamp(0, 1 << 30);
          // Use the factory constructor from ClipModel
          return ClipModel.fromDbData(
            dbClip,
            sourceDurationMs: sourceDuration,
          );
        }));
      }
       logInfo(_logTag, 'Successfully fetched ${allClips.length} clips.');
      return allClips;
    } catch (e) {
      logError(_logTag, "Error fetching all timeline clips: $e");
      return []; // Return empty list on error
    }
  }

  // Add public getters to access the DAOs
  ProjectDatabaseTrackDao? get trackDao => _trackDao;
  ProjectDatabaseClipDao? get clipDao => _clipDao;
  ProjectDatabaseAssetDao? get assetDao => _assetDao;

  /// DAO for reading change logs
  ChangeLogDao get changeLogDao {
    if (currentDatabase == null) {
      throw StateError('No project loaded');
    }
    return ChangeLogDao(currentDatabase!);
  }
}
