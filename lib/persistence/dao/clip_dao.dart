import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/persistence/tables/tracks.dart'; // Needed for join

part 'clip_dao.g.dart'; // Drift will generate this file

@DriftAccessor(tables: [Clips, Tracks]) // Include Tracks if joining
class ClipDao extends DatabaseAccessor<AppDatabase> with _$ClipDaoMixin {
  ClipDao(super.db);

  // Watch all clips for a specific track, ordered by their start time on the track
  Stream<List<Clip>> watchClipsForTrack(int trackId) {
    return (select(clips)
          ..where((c) => c.trackId.equals(trackId))
          ..orderBy([
            (c) => OrderingTerm(expression: c.startTimeOnTrackMs, mode: OrderingMode.asc),
            // Optional: Add secondary sort by 'order' if using that field
          ]))
        .watch();
  }

   // Get all clips for a specific track (non-streaming version)
  Future<List<Clip>> getClipsForTrack(int trackId) {
    return (select(clips)..where((c) => c.trackId.equals(trackId))).get();
  }

  // Insert a new clip
  Future<int> insertClip(ClipsCompanion clip) {
    return into(clips).insert(clip);
  }

  // Update a clip
  Future<bool> updateClip(ClipsCompanion clip) {
    // Ensure updatedAt is updated automatically if needed, or set it manually here
    // final companionWithTimestamp = clip.copyWith(updatedAt: Value(DateTime.now()));
    // return update(clips).replace(companionWithTimestamp);
    return update(clips).replace(clip);
  }

  // Delete a clip by ID
  Future<int> deleteClip(int id) {
    return (delete(clips)..where((c) => c.id.equals(id))).go();
  }

  // Delete all clips for a specific track
  Future<int> deleteClipsForTrack(int trackId) {
    return (delete(clips)..where((c) => c.trackId.equals(trackId))).go();
  }

   // Delete all clips associated with tracks belonging to a specific project
  Future<void> deleteClipsForProject(int projectId) async {
    // 1. Find all track IDs for the project
    // Corrected way to select only IDs
    final trackIdsQuery = select(tracks)
                           ..where((t) => t.projectId.equals(projectId));
    final trackIds = await trackIdsQuery.map((track) => track.id).get();

    // 2. Delete clips associated with those track IDs
    if (trackIds.isNotEmpty) {
       await (delete(clips)..where((c) => c.trackId.isIn(trackIds))).go();
    }
  }

   // --- Specific Update Methods ---

   // Update only the start time on the track (when moving a clip)
   Future<int> updateClipStartTimeOnTrack(int clipId, int newStartTimeMs) {
     return (update(clips)..where((c) => c.id.equals(clipId)))
         .write(ClipsCompanion(startTimeOnTrackMs: Value(newStartTimeMs)));
   }

   // Update trim times (start/end within source)
    Future<int> updateClipTrimTimes(int clipId, int newStartTimeInSourceMs, int newEndTimeInSourceMs) {
     return (update(clips)..where((c) => c.id.equals(clipId)))
         .write(ClipsCompanion(
             startTimeInSourceMs: Value(newStartTimeInSourceMs),
             endTimeInSourceMs: Value(newEndTimeInSourceMs),
         ));
   }
} 