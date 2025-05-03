import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/tracks.dart';

part 'project_database_track_dao.g.dart';

@DriftAccessor(tables: [Tracks])
class ProjectDatabaseTrackDao extends DatabaseAccessor<ProjectDatabase>
    with _$ProjectDatabaseTrackDaoMixin {
  ProjectDatabaseTrackDao(super.db);

  // Watch all tracks, ordered by their order value
  Stream<List<Track>> watchAllTracks() {
    return (select(tracks)..orderBy([
      (t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc),
    ])).watch();
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

  // Update specific fields of a track (e.g., name, updatedAt)
  // Returns the number of rows affected (usually 1 if successful, 0 if not found)
  Future<int> updateTrack(TracksCompanion track) {
    // Use update().write() to only update the fields present in the companion
    // Ensure the companion has the primary key (id) set for the where clause
    if (track.id == const Value.absent()) {
      // Use Value directly from drift import
      throw ArgumentError(
        'Track ID must be provided in the companion for update',
      );
    }
    return (update(tracks)..where(
      (t) => t.id.equals(track.id.value),
    )).write(track); // Returns Future<int>
  }

  // Delete a track by ID
  Future<int> deleteTrack(int id) {
    return (delete(tracks)..where((t) => t.id.equals(id))).go();
  }

  // Get all tracks as a Future, ordered by their order value
  Future<List<Track>> getAllTracks() {
    return (select(tracks)..orderBy([
      (t) => OrderingTerm(expression: t.order, mode: OrderingMode.asc),
    ])).get();
  }

  // Update the order of multiple tracks using a batch operation for efficiency
  Future<void> updateTrackOrders(List<Track> reorderedTracks) async {
    await db.batch((batch) {
      // Construct the update operations within the batch
      for (int i = 0; i < reorderedTracks.length; i++) {
        final track = reorderedTracks[i];

        // Log the planned update for debugging
        print('Planning update in batch: Track ${track.id} to order $i');

        // Use batch.update to stage the update operation
        batch.update(
          tracks, // Specify the table
          TracksCompanion(
            // Only specify the fields to update
            order: Value(i),
            updatedAt: Value(DateTime.now()),
          ),
          // Specify the WHERE clause for this specific update
          where: (t) => t.id.equals(track.id),
        );
      }

      print('All track updates planned in batch. Executing batch...');
      // The batch is automatically executed when the callback completes.
    });

    // Optional: Verification after batch execution
    try {
      final updatedTracks = await getAllTracks(); // Use existing getter
      print('Verification after batch:');
      for (final track in updatedTracks) {
        print('  Track ${track.id}, order: ${track.order}');
      }
    } catch (e) {
      print('Error verifying tracks after batch update: $e');
      // Decide if this error should be rethrown or just logged
    }
  }
}
