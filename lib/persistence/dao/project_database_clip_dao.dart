import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/utils/logger.dart';

part 'project_database_clip_dao.g.dart';

@DriftAccessor(tables: [Clips])
class ProjectDatabaseClipDao extends DatabaseAccessor<ProjectDatabase> with _$ProjectDatabaseClipDaoMixin {
  ProjectDatabaseClipDao(super.db);

  String get _logTag => 'ProjectDatabaseClipDao';

  // Watch all clips for a specific track
  Stream<List<Clip>> watchClipsForTrack(int trackId) {
    logInfo(_logTag, "Watching clips for track ID: $trackId");
    return (select(clips)
          ..where((c) => c.trackId.equals(trackId))
          ..orderBy([
            (c) => OrderingTerm(expression: c.startTimeOnTrackMs, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  // Get all clips for a specific track
  Future<List<Clip>> getClipsForTrack(int trackId) {
    logInfo(_logTag, "Getting clips for track ID: $trackId");
    return (select(clips)
          ..where((c) => c.trackId.equals(trackId))
          ..orderBy([
            (c) => OrderingTerm(expression: c.startTimeOnTrackMs, mode: OrderingMode.asc),
          ]))
        .get();
  }

  // Insert a new clip
  Future<int> insertClip(ClipsCompanion clip) {
    logInfo(_logTag, "Inserting new clip");
    // In project-specific database, projectId is not needed
    // since each project has its own database
    return into(clips).insert(clip);
  }

  // Get a clip by ID
  Future<Clip?> getClipById(int id) {
    logInfo(_logTag, "Getting clip by ID: $id");
    return (select(clips)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  // Update a clip
  Future<bool> updateClip(ClipsCompanion clip) {
    logInfo(_logTag, "Updating clip ID: ${clip.id.value}");
    return update(clips).replace(clip);
  }

  // Delete a clip by ID
  Future<int> deleteClip(int id) {
    logInfo(_logTag, "Deleting clip ID: $id");
    return (delete(clips)..where((c) => c.id.equals(id))).go();
  }

  // Delete all clips for a track
  Future<int> deleteClipsForTrack(int trackId) {
    logInfo(_logTag, "Deleting all clips for track ID: $trackId");
    return (delete(clips)..where((c) => c.trackId.equals(trackId))).go();
  }
} 