import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/persistence/tables/project_metadata.dart';

part 'project_metadata_dao.g.dart';

@DriftAccessor(tables: [ProjectMetadataTable])
class ProjectMetadataDao extends DatabaseAccessor<ProjectMetadataDatabase>
    with _$ProjectMetadataDaoMixin {
  ProjectMetadataDao(super.db);

  // Watch all project metadata, ordered by creation date descending
  Stream<List<ProjectMetadata>> watchAllProjects() {
    return (select(projectMetadataTable)..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ])).watch();
  }

  // Insert a new project metadata
  Future<int> insertProjectMetadata(
    ProjectMetadataTableCompanion projectMetadata,
  ) {
    return into(projectMetadataTable).insert(projectMetadata);
  }

  // Get a single project metadata by ID
  Future<ProjectMetadata?> getProjectMetadataById(int id) {
    return (select(projectMetadataTable)
      ..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  // Update a project metadata
  Future<bool> updateProjectMetadata(
    ProjectMetadataTableCompanion projectMetadata,
  ) {
    return update(projectMetadataTable).replace(projectMetadata);
  }

  // Delete a project metadata
  Future<int> deleteProjectMetadata(int id) {
    return (delete(projectMetadataTable)..where((t) => t.id.equals(id))).go();
  }
}
