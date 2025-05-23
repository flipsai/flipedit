import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/persistence/change_log_mixin.dart';

part 'project_database_clip_dao.g.dart';

@DriftAccessor(tables: [Clips])
class ProjectDatabaseClipDao extends DatabaseAccessor<ProjectDatabase>
    with _$ProjectDatabaseClipDaoMixin, ChangeLogMixin {
  ProjectDatabaseClipDao(super.db);

  String get _logTag => 'ProjectDatabaseClipDao';

  // Watch all clips for a specific track
  Stream<List<Clip>> watchClipsForTrack(int trackId) {
    logInfo(_logTag, "Watching clips for track ID: $trackId");
    return (select(clips)
          ..where((c) => c.trackId.equals(trackId))
          ..orderBy([
            (c) => OrderingTerm(
              expression: c.startTimeOnTrackMs,
              mode: OrderingMode.asc,
            ),
          ]))
        .watch();
  }

  // Get all clips for a specific track
  Future<List<Clip>> getClipsForTrack(int trackId) {
    logInfo(_logTag, "Getting clips for track ID: $trackId");
    return (select(clips)
          ..where((c) => c.trackId.equals(trackId))
          ..orderBy([
            (c) => OrderingTerm(
              expression: c.startTimeOnTrackMs,
              mode: OrderingMode.asc,
            ),
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
        trackId: clip.trackId.value,
        name: clip.name.value,
        type: clip.type.value,
        sourcePath: clip.sourcePath.value,
        startTimeInSourceMs: clip.startTimeInSourceMs.value,
        endTimeInSourceMs: clip.endTimeInSourceMs.value,
        startTimeOnTrackMs: clip.startTimeOnTrackMs.value,
        previewPositionX: clip.previewPositionX.value,
        previewPositionY: clip.previewPositionY.value,
        previewWidth: clip.previewWidth.value,
        previewHeight: clip.previewHeight.value,
        metadata: clip.metadata.present ? clip.metadata.value : null,
        createdAt:
            clip.createdAt.present ? clip.createdAt.value : DateTime.now(),
        updatedAt:
            clip.updatedAt.present ? clip.updatedAt.value : DateTime.now(),
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
  Future<bool> updateClipFields(
    int clipId,
    Map<String, dynamic> fields, {
    bool log = true,
  }) async {
    if (log) {
      logInfo(
        _logTag,
        "Updating specific fields for clip ID: $clipId - Fields: ${fields.keys.join(', ')}",
      );
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
        sourceDurationMs:
            oldRow.sourceDurationMs == null
                ? const Value.absent()
                : Value(oldRow.sourceDurationMs!),
        startTimeInSourceMs: Value(oldRow.startTimeInSourceMs),
        endTimeInSourceMs: Value(oldRow.endTimeInSourceMs),
        startTimeOnTrackMs: Value(oldRow.startTimeOnTrackMs),
        endTimeOnTrackMs:
            oldRow.endTimeOnTrackMs == null
                ? const Value.absent()
                : Value(oldRow.endTimeOnTrackMs!),
        metadata:
            oldRow.metadata == null
                ? const Value.absent()
                : Value(oldRow.metadata!),
        previewPositionX: Value(oldRow.previewPositionX),
        previewPositionY: Value(oldRow.previewPositionY),
        previewWidth: Value(oldRow.previewWidth),
        previewHeight: Value(oldRow.previewHeight),
        createdAt:
            oldRow.createdAt != null
                ? Value(oldRow.createdAt)
                : Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      );

      final updatedCompanion = _applyFieldUpdates(companion, fields);

      final success = await update(clips).replace(updatedCompanion);
      if (success && log) {
        final newRow = Clip(
          id: clipId,
          trackId: updatedCompanion.trackId.value,
          name: updatedCompanion.name.value,
          type: updatedCompanion.type.value,
          sourcePath: updatedCompanion.sourcePath.value,
          startTimeInSourceMs: updatedCompanion.startTimeInSourceMs.value,
          endTimeInSourceMs: updatedCompanion.endTimeInSourceMs.value,
          startTimeOnTrackMs: updatedCompanion.startTimeOnTrackMs.value,
          endTimeOnTrackMs:
              updatedCompanion.endTimeOnTrackMs.present
                  ? updatedCompanion.endTimeOnTrackMs.value
                  : null,
          metadata:
              updatedCompanion.metadata.present
                  ? updatedCompanion.metadata.value
                  : null,
          previewPositionX: updatedCompanion.previewPositionX.value,
          previewPositionY: updatedCompanion.previewPositionY.value,
          previewWidth: updatedCompanion.previewWidth.value,
          previewHeight: updatedCompanion.previewHeight.value,
          createdAt:
              updatedCompanion.createdAt.present
                  ? updatedCompanion.createdAt.value
                  : DateTime.now(),
          updatedAt:
              updatedCompanion.updatedAt.present
                  ? updatedCompanion.updatedAt.value
                  : DateTime.now(),
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
  ClipsCompanion _applyFieldUpdates(
    ClipsCompanion base,
    Map<String, dynamic> updates,
  ) {
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
        case 'sourceDurationMs':
          result = result.copyWith(sourceDurationMs: Value(value as int?));
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
        case 'endTimeOnTrackMs':
          result = result.copyWith(endTimeOnTrackMs: Value(value as int?));
          break;
        case 'metadata':
          final metadataValue = value as String?;
          result = result.copyWith(
            metadata:
                metadataValue == null
                    ? const Value.absent()
                    : Value(metadataValue),
          );
          break;
        case 'previewPositionX':
          result = result.copyWith(previewPositionX: Value(value as double));
          break;
        case 'previewPositionY':
          result = result.copyWith(previewPositionY: Value(value as double));
          break;
        case 'previewWidth':
          result = result.copyWith(previewWidth: Value(value as double));
          break;
        case 'previewHeight':
          result = result.copyWith(previewHeight: Value(value as double));
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

  // Delete all clips with a specific source path
  Future<int> deleteClipsBySourcePath(String sourcePath) {
    logInfo(_logTag, "Deleting all clips with source path: $sourcePath");
    return (delete(clips)..where((c) => c.sourcePath.equals(sourcePath))).go();
  }

  // Get all clips with a specific source path
  Future<List<Clip>> getClipsBySourcePath(String sourcePath) {
    logInfo(_logTag, "Getting clips with source path: $sourcePath");
    return (select(clips)..where((c) => c.sourcePath.equals(sourcePath))).get();
  }
}
