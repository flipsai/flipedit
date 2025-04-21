import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/tracks.dart';

part 'project_database_track_dao.g.dart';

@DriftAccessor(tables: [Tracks])
class ProjectDatabaseTrackDao extends DatabaseAccessor<ProjectDatabase> with _$ProjectDatabaseTrackDaoMixin {
  ProjectDatabaseTrackDao(super.db);

  // Watch all tracks, ordered by their order value
  Stream<List<Track>> watchAllTracks() {
    return (select(tracks)
          ..orderBy([
            (t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  // Insert a new track
  Future<int> insertTrack(TracksCompanion track) {
    // For project-specific databases, we don't need projectId
    // since each project has its own database
    return into(tracks).insert(track);
  }

  // Get a track by ID
  Future<Track?> getTrackById(int id) {
    return (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  // Update a track
  Future<bool> updateTrack(TracksCompanion track) {
    return update(tracks).replace(track);
  }

  // Delete a track by ID
  Future<int> deleteTrack(int id) {
    return (delete(tracks)..where((t) => t.id.equals(id))).go();
  }
} 