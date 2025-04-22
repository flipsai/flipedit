import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/persistence/change_log_mixin.dart';

part 'project_database_clip_dao.g.dart';

@DriftAccessor(tables: [Clips])
class ProjectDatabaseClipDao extends DatabaseAccessor<ProjectDatabase> with _$ProjectDatabaseClipDaoMixin, ChangeLogMixin {
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
  Future<int> insertClip(ClipsCompanion clip) async {
    logInfo(_logTag, "Inserting new clip");
    final id = await into(clips).insert(clip);
    final newRow = await getClipById(id);
    await logChange(
      tableName: 'clips',
      primaryKey: id.toString(),
      action: 'insert',
      oldRow: null,
      newRow: newRow,
    );
    return id;
  }

  // Get a clip by ID
  Future<Clip?> getClipById(int id) {
    logInfo(_logTag, "Getting clip by ID: $id");
    return (select(clips)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  // Update a clip
  Future<bool> updateClip(ClipsCompanion clip) async {
    final id = clip.id.value;
    logInfo(_logTag, "Updating clip ID: $id");
    final oldRow = await getClipById(id);
    final success = await update(clips).replace(clip);
    if (success && oldRow != null) {
      final newRow = Clip(
        id: id,
        trackId: clip.trackId.value!,
        name: clip.name.value!,
        type: clip.type.value!,
        sourcePath: clip.sourcePath.value!,
        startTimeInSourceMs: clip.startTimeInSourceMs.value!,
        endTimeInSourceMs: clip.endTimeInSourceMs.value!,
        startTimeOnTrackMs: clip.startTimeOnTrackMs.value!,
        metadataJson: clip.metadataJson.present ? clip.metadataJson.value : null,
        createdAt: clip.createdAt.value!,
        updatedAt: clip.updatedAt.value!,
      );
      await logChange(
        tableName: 'clips',
        primaryKey: id.toString(),
        action: 'update',
        oldRow: oldRow,
        newRow: newRow,
      );
    }
    return success;
  }

  // Update only specific fields of a clip
  Future<bool> updateClipFields(int clipId, Map<String, dynamic> fields, {bool log = true}) async {
    if (log) {
      logInfo(_logTag, "Updating specific fields for clip ID: $clipId - Fields: ${fields.keys.join(', ')}");
    }
    
    try {
      final oldRow = await getClipById(clipId);
      if (oldRow == null) {
        if (log) {
          logError(_logTag, "Cannot update clip $clipId - clip not found");
        }
        return false;
      }
      
      final companion = ClipsCompanion(
        id: Value(clipId),
        trackId: Value(oldRow.trackId),
        name: Value(oldRow.name),
        type: Value(oldRow.type),
        sourcePath: Value(oldRow.sourcePath),
        startTimeInSourceMs: Value(oldRow.startTimeInSourceMs),
        endTimeInSourceMs: Value(oldRow.endTimeInSourceMs),
        startTimeOnTrackMs: Value(oldRow.startTimeOnTrackMs),
        metadataJson: oldRow.metadataJson == null ? const Value.absent() : Value(oldRow.metadataJson!),
        createdAt: Value(oldRow.createdAt),
        updatedAt: Value(DateTime.now()), // Always update the updatedAt timestamp
      );
      
      final updatedCompanion = _applyFieldUpdates(companion, fields);
      
      final success = await update(clips).replace(updatedCompanion);
      if (success && log) {
        final newRow = Clip(
          id: clipId,
          trackId: updatedCompanion.trackId.value!,
          name: updatedCompanion.name.value!,
          type: updatedCompanion.type.value!,
          sourcePath: updatedCompanion.sourcePath.value!,
          startTimeInSourceMs: updatedCompanion.startTimeInSourceMs.value!,
          endTimeInSourceMs: updatedCompanion.endTimeInSourceMs.value!,
          startTimeOnTrackMs: updatedCompanion.startTimeOnTrackMs.value!,
          metadataJson: updatedCompanion.metadataJson.present ? updatedCompanion.metadataJson.value : null,
          createdAt: updatedCompanion.createdAt.value!,
          updatedAt: updatedCompanion.updatedAt.value!,
        );
        await logChange(
          tableName: 'clips',
          primaryKey: clipId.toString(),
          action: 'update',
          oldRow: oldRow,
          newRow: newRow,
        );
      }
      return success;
    } catch (e) {
      if (log) {
        logError(_logTag, "Error updating clip fields: $e");
      }
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
  Future<int> deleteClip(int id) async {
    logInfo(_logTag, "Deleting clip ID: $id");
    final oldRow = await getClipById(id);
    final deleted = await (delete(clips)..where((c) => c.id.equals(id))).go();
    if (oldRow != null) {
      await logChange(
        tableName: 'clips',
        primaryKey: id.toString(),
        action: 'delete',
        oldRow: oldRow,
        newRow: null,
      );
    }
    return deleted;
  }

  // Delete all clips for a track
  Future<int> deleteClipsForTrack(int trackId) {
    logInfo(_logTag, "Deleting all clips for track ID: $trackId");
    return (delete(clips)..where((c) => c.trackId.equals(trackId))).go();
  }
} 