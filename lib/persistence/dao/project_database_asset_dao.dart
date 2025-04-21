import 'package:drift/drift.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:path/path.dart' as p;

part 'project_database_asset_dao.g.dart';

@DriftAccessor(tables: [ProjectAssets])
class ProjectDatabaseAssetDao extends DatabaseAccessor<ProjectDatabase> with _$ProjectDatabaseAssetDaoMixin {
  ProjectDatabaseAssetDao(super.db);

  String get _logTag => 'ProjectDatabaseAssetDao';

  // Watch all assets in the project
  Stream<List<model.ProjectAsset>> watchAllAssets() {
    logInfo(_logTag, "Watching all project assets");
    return (select(projectAssets)
          ..orderBy([
            (a) => OrderingTerm(expression: a.name),
          ]))
        .watch()
        .map((rows) => rows.map(_mapToModel).toList());
  }

  // Get all assets in the project
  Future<List<model.ProjectAsset>> getAllAssets() {
    logInfo(_logTag, "Getting all project assets");
    return (select(projectAssets)
          ..orderBy([
            (a) => OrderingTerm(expression: a.name),
          ]))
        .get()
        .then((rows) => rows.map(_mapToModel).toList());
  }

  // Map database entity to domain model
  model.ProjectAsset _mapToModel(ProjectAsset asset) {
    return model.ProjectAsset(
      databaseId: asset.id,
      name: asset.name,
      type: _mapTypeStringToEnum(asset.type),
      sourcePath: asset.sourcePath,
      durationMs: asset.durationMs ?? 0,
    );
  }

  // Helper to convert string type to enum
  ClipType _mapTypeStringToEnum(String typeStr) {
    switch (typeStr.toLowerCase()) {
      case 'video':
        return ClipType.video;
      case 'audio':
        return ClipType.audio;
      case 'image':
        return ClipType.image;
      case 'text':
        return ClipType.text;
      default:
        return ClipType.video; // Default fallback
    }
  }

  // Helper to convert enum type to string
  String _mapEnumTypeToString(ClipType type) {
    return type.toString().split('.').last.toLowerCase();
  }

  // Import a new asset
  Future<int> importAsset({
    required String filePath,
    required ClipType type,
    required int durationMs,
    int? width,
    int? height,
    double? fileSize,
    String? thumbnailPath,
  }) async {
    logInfo(_logTag, "Importing asset: $filePath");
    
    final fileName = p.basename(filePath);
    
    try {
      // Create the companion object with all fields
      final companion = ProjectAssetsCompanion.insert(
        name: fileName,
        sourcePath: filePath,  // Now using sourcePath which matches the DB column
        type: _mapEnumTypeToString(type),
        durationMs: Value(durationMs),
        width: width != null ? Value(width) : const Value.absent(),
        height: height != null ? Value(height) : const Value.absent(),
        fileSize: fileSize != null ? Value(fileSize) : const Value.absent(),
        thumbnailPath: thumbnailPath != null ? Value(thumbnailPath) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );
      
      // Let drift handle the insert with proper column mappings
      return await into(projectAssets).insert(companion);
    } catch (e) {
      logError(_logTag, "Error importing asset: $e");
      rethrow;
    }
  }

  // Get an asset by ID
  Future<model.ProjectAsset?> getAssetById(int id) async {
    logInfo(_logTag, "Getting asset by ID: $id");
    final result = await (select(projectAssets)..where((a) => a.id.equals(id))).getSingleOrNull();
    return result != null ? _mapToModel(result) : null;
  }

  // Delete an asset by ID
  Future<int> deleteAsset(int id) {
    logInfo(_logTag, "Deleting asset ID: $id");
    return (delete(projectAssets)..where((a) => a.id.equals(id))).go();
  }

  // Update an asset's metadata
  Future<bool> updateAsset(ProjectAssetsCompanion asset) {
    logInfo(_logTag, "Updating asset ID: ${asset.id.value}");
    return update(projectAssets).replace(asset);
  }
} 