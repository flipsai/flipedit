import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/persistence/tables/projects.dart';

part 'project_dao.g.dart'; // Drift will generate this file

@DriftAccessor(tables: [Projects])
class ProjectDao extends DatabaseAccessor<AppDatabase> with _$ProjectDaoMixin {
  // The constructor is required for the generated mixin - RE-ADDING THIS
  ProjectDao(super.db);

  // Watch all projects, ordered by creation date descending
  Stream<List<Project>> watchAllProjects() {
    return (select(projects)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  // Insert a new project
  Future<int> insertProject(ProjectsCompanion project) {
    return into(projects).insert(project);
  }

  // Get a single project by ID (useful for loading a specific project)
  Future<Project?> getProjectById(int id) {
    return (select(projects)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  // Update a project
  Future<bool> updateProject(ProjectsCompanion project) {
    return update(projects).replace(project);
  }

  // Delete a project
  Future<int> deleteProject(int id) {
    return (delete(projects)..where((t) => t.id.equals(id))).go();
  }
} 