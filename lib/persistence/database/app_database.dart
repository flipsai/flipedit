import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/dao/clip_dao.dart';
import 'package:flipedit/persistence/dao/project_asset_dao.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';
import 'package:flipedit/persistence/tables/projects.dart';
import 'package:flipedit/persistence/tables/tracks.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// DEPRECATED: This database structure will be replaced by per-project databases
// New projects should use ProjectMetadataDatabase instead
@DriftDatabase(
  tables: [Projects, Tracks, Clips, ProjectAssets],
  daos: [ProjectDao, TrackDao, ClipDao, ProjectAssetDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  static const String _logTag = 'AppDatabase';

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        logWarning(_logTag, "Creating AppDatabase tables, but this structure is deprecated");
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Assuming version 1 already had createdAt, as the error is "duplicate column"
          // await m.addColumn(projects, projects.createdAt); // Remove this line
        }

        if (from < 3) {
          await m.createTable(tracks); // Create the Tracks table
        }

        if (from < 4) {
          await m.createTable(clips); // Create the Clips table
        }

        if (from < 5) {
          // Add name and type columns to Clips table if upgrading from < 5
          await m.addColumn(clips, clips.name);
          await m.addColumn(clips, clips.type);
        }

        if (from < 6) {
          await m.createTable(projectAssets);
        }

        if (from < 7) {
          // Migration to mark the database as deprecated
          // No schema changes needed, this is just a marker for the new architecture
          logWarning(_logTag, "AppDatabase upgraded to version 7 (marked as deprecated)");
          logInfo(_logTag, "New projects will use the ProjectMetadataDatabase instead");
        }
      },
      beforeOpen: (details) async {
        if (details.wasCreated) {
          // Log a warning if someone is creating this database after deprecation
          logWarning(_logTag, "Creating a new AppDatabase instance, but this structure is deprecated");
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  // the LazyDatabase util lets us find the right location for the file async.
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'flipedit_db.sqlite'));
    return NativeDatabase.createInBackground(file, logStatements: true);
  });
} 