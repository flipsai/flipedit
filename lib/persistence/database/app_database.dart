import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/tables/projects.dart';
import 'package:flipedit/persistence/tables/tracks.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart'; // Reverted filename

@DriftDatabase(tables: [Projects, Tracks], daos: [ProjectDao, TrackDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3; // Incremented version to 3

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Assuming version 1 already had createdAt, as the error is "duplicate column"
          // await m.addColumn(projects, projects.createdAt); // Remove this line
          // If you also had 'last_modified_at' previously and removed it,
          // you might need 'await m.addColumn(projects, projects.lastModifiedAt);' here too,
          // but let's start with just createdAt as per the current table definition.
        }

        if (from < 3) {
          await m.createTable(tracks); // Create the Tracks table
        }

        // Add further migrations for future schema versions here using 'if (from < X)' blocks
      },
    );
  }
}

LazyDatabase _openConnection() {
  // the LazyDatabase util lets us find the right location for the file async.
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'flipedit_db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
} 