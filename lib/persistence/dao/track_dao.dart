import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/tracks.dart';

part 'track_dao.g.dart'; // Drift will generate this file

@DriftAccessor(tables: [Tracks])
class TrackDao extends DatabaseAccessor<AppDatabase> with _$TrackDaoMixin {
  TrackDao(super.db);

  // Watch all tracks for a specific project, ordered by their 'order' field
  Stream<List<Track>> watchTracksForProject(int projectId) {
    return (select(tracks)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  // Get all tracks for a specific project, ordered by their 'order' field (non-streaming)
  Future<List<Track>> getTracksForProject(int projectId) {
    return (select(tracks)
      ..where((t) => t.projectId.equals(projectId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc),
      ]))
    .get();
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
  Future<int> deleteTracksForProject(int projectId) {
    return (delete(tracks)..where((t) => t.projectId.equals(projectId))).go();
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