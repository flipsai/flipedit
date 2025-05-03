import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flipedit/persistence/tables/project_metadata.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Forward declaration of the DAO
import 'package:flipedit/persistence/dao/project_metadata_dao.dart'
    show ProjectMetadataDao;

part 'project_metadata_database.g.dart';

@DriftDatabase(tables: [ProjectMetadataTable], daos: [ProjectMetadataDao])
class ProjectMetadataDatabase extends _$ProjectMetadataDatabase {
  ProjectMetadataDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Add migration strategies when schema is updated
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(dbFolder.path, 'flipedit_projects_metadata.sqlite'),
    );
    return NativeDatabase.createInBackground(file, logStatements: true);
  });
}
