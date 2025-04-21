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

  // Update only specific fields of a clip
  Future<bool> updateClipFields(int clipId, Map<String, dynamic> fields) async {
    logInfo(_logTag, "Updating specific fields for clip ID: $clipId - Fields: ${fields.keys.join(', ')}");
    
    try {
      // First, get the current clip
      final currentClip = await getClipById(clipId);
      if (currentClip == null) {
        logError(_logTag, "Cannot update clip $clipId - clip not found");
        return false;
      }
      
      // Create a companion with all the current values as a base
      final companion = ClipsCompanion(
        id: Value(clipId),
        trackId: Value(currentClip.trackId),
        name: Value(currentClip.name),
        type: Value(currentClip.type),
        sourcePath: Value(currentClip.sourcePath),
        startTimeInSourceMs: Value(currentClip.startTimeInSourceMs),
        endTimeInSourceMs: Value(currentClip.endTimeInSourceMs),
        startTimeOnTrackMs: Value(currentClip.startTimeOnTrackMs),
        metadataJson: currentClip.metadataJson == null ? const Value.absent() : Value(currentClip.metadataJson!),
        createdAt: Value(currentClip.createdAt),
        updatedAt: Value(DateTime.now()), // Always update the updatedAt timestamp
      );
      
      // Create a new companion with updated fields
      final updatedCompanion = _applyFieldUpdates(companion, fields);
      
      // Perform the update
      return update(clips).replace(updatedCompanion);
    } catch (e) {
      logError(_logTag, "Error updating clip fields: $e");
      return false;
    }
  }
  
  // Helper to apply field updates to a companion
  ClipsCompanion _applyFieldUpdates(ClipsCompanion base, Map<String, dynamic> updates) {
    // Create a new companion with the same values as the base
    var result = base;
    
    // Apply each update by field name
    for (final entry in updates.entries) {
      final field = entry.key;
      final value = entry.value;
      
      switch (field) {
        case 'trackId':
          result = result.copyWith(trackId: Value(value as int));
          break;
        case 'name':
          result = result.copyWith(name: Value(value as String));
          break;
        case 'type':
          result = result.copyWith(type: Value(value as String));
          break;
        case 'sourcePath':
          result = result.copyWith(sourcePath: Value(value as String));
          break;
        case 'startTimeInSourceMs':
          result = result.copyWith(startTimeInSourceMs: Value(value as int));
          break;
        case 'endTimeInSourceMs':
          result = result.copyWith(endTimeInSourceMs: Value(value as int));
          break;
        case 'startTimeOnTrackMs':
          result = result.copyWith(startTimeOnTrackMs: Value(value as int));
          break;
        case 'metadataJson':
          final metadataValue = value as String?;
          result = result.copyWith(
            metadataJson: metadataValue == null ? const Value.absent() : Value(metadataValue)
          );
          break;
      }
    }
    
    return result;
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