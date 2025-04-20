import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/tracks.dart';
import 'package:flipedit/utils/logger.dart';

part 'track_dao.g.dart'; // Drift will generate this file

@DriftAccessor(tables: [Tracks])
class TrackDao extends DatabaseAccessor<AppDatabase> with _$TrackDaoMixin {
  TrackDao(super.db);
  
  String get _logTag => 'TrackDao';

  // Watch all tracks for a specific project, ordered by their 'order' field
  // Note: In legacy database, this uses projectId to filter
  Stream<List<Track>> watchTracksForProject(int projectId) {
    logInfo(_logTag, "Watching tracks for project $projectId (legacy method)");
    try {
      // Use raw SQL for backward compatibility with the legacy database
      return customSelect(
        'SELECT * FROM tracks WHERE project_id = ? ORDER BY "order" ASC',
        variables: [Variable.withInt(projectId)],
        readsFrom: {tracks}, // Tell drift which tables we're reading
      ).watch().map((rows) {
        return rows.map((row) => Track.fromJson(row.data)).toList();
      });
    } catch (e) {
      logError(_logTag, "Error watching tracks: $e");
      // Return an empty stream if there's an error
      return Stream.value([]);
    }
  }

  // Get all tracks for a specific project, ordered by their 'order' field (non-streaming)
  Future<List<Track>> getTracksForProject(int projectId) {
    logInfo(_logTag, "Getting tracks for project $projectId (legacy method)");
    try {
      // For backward compatibility with the legacy database
      return customSelect(
        'SELECT * FROM tracks WHERE project_id = ? ORDER BY "order" ASC',
        variables: [Variable.withInt(projectId)],
      ).map((row) => Track.fromJson(row.data)).get();
    } catch (e) {
      logError(_logTag, "Error getting tracks: $e");
      return Future.value([]);
    }
  }

  // Insert a new track
  Future<int> insertTrack(TracksCompanion track) {
    return into(tracks).insert(track);
  }

  // Update a track
  Future<bool> updateTrack(TracksCompanion track) {
    return update(tracks).replace(track);
  }

  // Delete a track by ID
  Future<int> deleteTrack(int id) {
    return (delete(tracks)..where((t) => t.id.equals(id))).go();
  }

  // Delete all tracks for a specific project (useful when deleting a project)
  // Note: This is for compatibility with the legacy database
  Future<int> deleteTracksForProject(int projectId) {
    logWarning(_logTag, "deleteTracksForProject is deprecated in the new database structure");
    try {
      // For backward compatibility with the legacy database
      return customUpdate(
        'DELETE FROM tracks WHERE project_id = ?',
        variables: [Variable.withInt(projectId)],
      );
    } catch (e) {
      logError(_logTag, "Error deleting tracks for project: $e");
      return Future.value(0);
    }
  }

  // Reorder tracks (example implementation - might need adjustment based on UI)
  Future<void> reorderTracks(List<Track> orderedTracks) async {
    // This often involves updating the 'order' field of multiple tracks
    // A transaction is recommended for atomicity
    return db.transaction(() async {
      for (int i = 0; i < orderedTracks.length; i++) {
        await (update(tracks)..where((t) => t.id.equals(orderedTracks[i].id)))
            .write(TracksCompanion(order: Value(i)));
      }
    });
  }
} 