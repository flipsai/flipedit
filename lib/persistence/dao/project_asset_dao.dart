import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';

part 'project_asset_dao.g.dart';

@DriftAccessor(tables: [ProjectAssets])
class ProjectAssetDao extends DatabaseAccessor<AppDatabase> with _$ProjectAssetDaoMixin {
  ProjectAssetDao(AppDatabase db) : super(db);

  // Get all assets for a specific project
  Future<List<ProjectAssetEntry>> getAssetsForProject(int projectId) {
    return (select(projectAssets)..where((tbl) => tbl.projectId.equals(projectId))).get();
  }

  // Watch all assets for a specific project (returns a stream)
  Stream<List<ProjectAssetEntry>> watchAssetsForProject(int projectId) {
    return (select(projectAssets)..where((tbl) => tbl.projectId.equals(projectId))).watch();
  }

  // Add a new asset to a project
  Future<int> addAsset(ProjectAssetsCompanion entry) {
    return into(projectAssets).insert(entry);
  }

  // Delete an asset by ID
  Future<int> deleteAsset(int assetId) {
    return (delete(projectAssets)..where((tbl) => tbl.id.equals(assetId))).go();
  }

  // Potential future methods:
  // Future<void> updateAsset(ProjectAssetsCompanion entry) { ... }
  // Future<ProjectAssetEntry> getAssetById(int assetId) { ... }
}