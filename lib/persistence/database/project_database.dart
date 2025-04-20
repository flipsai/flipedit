import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/dao/project_database_track_dao.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';
import 'package:flipedit/persistence/tables/tracks.dart';
import 'package:flipedit/utils/logger.dart';

part 'project_database.g.dart';

/// ProjectDatabase represents a database for a single project
/// Each project will have its own database file with this schema
@DriftDatabase(
  tables: [Tracks, Clips, ProjectAssets],
  daos: [ProjectDatabaseTrackDao, ProjectDatabaseClipDao],
)
class ProjectDatabase extends _$ProjectDatabase {
  ProjectDatabase(String databasePath) : super(_openConnection(databasePath));

  static const String _logTag = 'ProjectDatabase';

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        logInfo(_logTag, "Creating tables for new project database");
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Add migration strategies for future schema versions
        logInfo(_logTag, "Upgrading project database schema from $from to $to");
      },
    );
  }
  
  // Close the database connection
  Future<void> closeConnection() async {
    logInfo(_logTag, "Closing project database connection");
    await close();
  }
}

// Create a connection to the project-specific database
LazyDatabase _openConnection(String databasePath) {
  return LazyDatabase(() async {
    final file = File(databasePath);
    // Ensure the directory exists
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return NativeDatabase.createInBackground(file, logStatements: true);
  });
}

/// Factory to create DAO objects for a ProjectDatabase instance
class ProjectDatabaseFactory {
  static ProjectDatabaseTrackDao createTrackDao(ProjectDatabase db) {
    return ProjectDatabaseTrackDao(db);
  }
  
  static ProjectDatabaseClipDao createClipDao(ProjectDatabase db) {
    return ProjectDatabaseClipDao(db);
  }
} 