import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';
import 'package:flipedit/utils/logger.dart';

part 'project_asset_dao.g.dart';

@DriftAccessor(tables: [ProjectAssets])
class ProjectAssetDao extends DatabaseAccessor<AppDatabase> with _$ProjectAssetDaoMixin {
  ProjectAssetDao(AppDatabase db) : super(db);
  
  String get _logTag => 'ProjectAssetDao';

  // Get all assets for a specific project
  Future<List<ProjectAssetEntry>> getAssetsForProject(int projectId) {
    logInfo(_logTag, "Getting assets for project $projectId (legacy method)");
    try {
      // For backward compatibility with the legacy database
      return customSelect(
        'SELECT * FROM project_assets WHERE project_id = ?',
        variables: [Variable.withInt(projectId)],
      ).map((row) => ProjectAssetEntry.fromJson(row.data)).get();
    } catch (e) {
      logError(_logTag, "Error getting assets: $e");
      return Future.value([]);
    }
  }

  // Watch all assets for a specific project (returns a stream)
  Stream<List<ProjectAssetEntry>> watchAssetsForProject(int projectId) {
    logInfo(_logTag, "Watching assets for project $projectId (legacy method)");
    try {
      // For backward compatibility with the legacy database
      return customSelect(
        'SELECT * FROM project_assets WHERE project_id = ?',
        variables: [Variable.withInt(projectId)],
        readsFrom: {projectAssets}, // Tell drift which tables we're reading
      ).watch().map((rows) {
        return rows.map((row) => ProjectAssetEntry.fromJson(row.data)).toList();
      });
    } catch (e) {
      logError(_logTag, "Error watching assets: $e");
      // Return an empty stream if there's an error
      return Stream.value([]);
    }
  }

  // Add a new asset to a project
  Future<int> addAsset(ProjectAssetsCompanion entry) {
    return into(projectAssets).insert(entry);
  }

  // Delete an asset by ID
  Future<int> deleteAsset(int assetId) {
    return (delete(projectAssets)..where((tbl) => tbl.id.equals(assetId))).go();
  }
  
  // Delete all assets for a specific project
  Future<int> deleteAssetsForProject(int projectId) {
    logWarning(_logTag, "deleteAssetsForProject is deprecated in the new database structure");
    try {
      // For backward compatibility with the legacy database
      return customUpdate(
        'DELETE FROM project_assets WHERE project_id = ?',
        variables: [Variable.withInt(projectId)],
      );
    } catch (e) {
      logError(_logTag, "Error deleting assets for project: $e");
      return Future.value(0);
    }
  }

  // Potential future methods:
  // Future<void> updateAsset(ProjectAssetsCompanion entry) { ... }
  // Future<ProjectAssetEntry> getAssetById(int assetId) { ... }
}