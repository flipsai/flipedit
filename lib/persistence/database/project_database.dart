import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/dao/project_database_track_dao.dart';
import 'package:flipedit/persistence/dao/project_database_asset_dao.dart';
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/persistence/tables/project_assets.dart';
import 'package:flipedit/persistence/tables/tracks.dart';
import 'package:flipedit/persistence/tables/change_logs.dart';
import 'package:flipedit/persistence/dao/change_log_dao.dart';
import 'package:flipedit/utils/logger.dart';

part 'project_database.g.dart';

/// ProjectDatabase represents a database for a single project
/// Each project will have its own database file with this schema
@DriftDatabase(
  tables: [Tracks, Clips, ProjectAssets, ChangeLogs],
  daos: [
    ProjectDatabaseTrackDao,
    ProjectDatabaseClipDao,
    ProjectDatabaseAssetDao,
    ChangeLogDao,
  ],
)
class ProjectDatabase extends _$ProjectDatabase {
  ProjectDatabase(String databasePath) : super(_openConnection(databasePath));

  /// Named constructor for creating an in-memory database for testing.
  ProjectDatabase.forTesting(super.executor);

  static const String _logTag = 'ProjectDatabase';

  @override
  int get schemaVersion => 3; // Incremented schema version for new transform columns

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        logInfo(_logTag, "Creating tables for new project database");
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        logInfo(_logTag, "Upgrading project database schema from $from to $to");
        if (from == 1 && to == 2) {
          // Migration from version 1 to 2:
          // The 'metadata_json' column in the 'clips' table was renamed to 'metadata'.
          // Note: Drift table and column names are converted to snake_case in SQL.
          // So, 'metadataJson' in Dart becomes 'metadata_json' in SQL.
          try {
            await m.renameColumn(clips, 'metadata_json', clips.metadata);
            logInfo(_logTag, "Successfully renamed column 'metadata_json' to 'metadata' in 'clips' table.");
          } catch (e) {
            logError(_logTag, "Error renaming column 'metadata_json' to 'metadata': $e. Attempting add/drop fallback.");
            // Fallback: Add new column, copy data, drop old column.
            // This is more complex and error-prone, m.renameColumn should be preferred.
            // If renameColumn fails, it might be due to SQLite version or other constraints.
            // A more robust fallback would be:
            // 1. Add the new 'metadata' column.
            // 2. Copy data from 'metadata_json' to 'metadata'.
            // 3. Remove the 'metadata_json' column.
            // However, m.renameColumn is generally the way to go.
            // If this also fails, the database might need to be rebuilt or a more specific migration written.
            // For now, we'll log the error. The user might need to clear app data if this persists.
            // A common issue is if 'metadata_json' didn't exist, in which case we just add 'metadata'.
            // Let's try adding the column if rename fails, assuming it might not have existed.
            try {
              await m.addColumn(clips, clips.metadata);
              logInfo(_logTag, "Added column 'metadata' to 'clips' table as rename failed.");
            } catch (e2) {
              logError(_logTag, "Also failed to add 'metadata' column: $e2");
            }
          }
        } else if (from == 2 && to == 3) {
          // Migration from version 2 to 3:
          // - Add new preview_position_x, preview_position_y, preview_width, preview_height columns
          // - Remove old preview_flip_x, preview_flip_y, preview_scale, preview_rotation columns
          
          // Add new columns (Drift handles NOT NULL DEFAULT from table definition)
          await m.addColumn(clips, clips.previewPositionX);
          await m.addColumn(clips, clips.previewPositionY);
          await m.addColumn(clips, clips.previewWidth);
          await m.addColumn(clips, clips.previewHeight);
          logInfo(_logTag, "Added new transform columns (positionX, positionY, width, height) to 'clips' table.");

          // Drop old columns
          // Note: SQLite added DROP COLUMN in 3.35.0.
          // The actual SQL column names are snake_case.
          const oldColumnsToDrop = [
            'preview_flip_x',
            'preview_flip_y',
            'preview_scale',
            'preview_rotation'
          ];

          for (final colName in oldColumnsToDrop) {
            try {
              // We attempt to drop. If the column doesn't exist, SQLite might throw an error.
              // It's generally safe to try dropping; if it's not there, the DB state doesn't change.
              // However, to be more robust, one might check sqlite_master or catch specific errors.
              // For simplicity, we'll just attempt the drop.
              await m.database.customStatement('ALTER TABLE clips DROP COLUMN $colName;', []);
              logInfo(_logTag, "Attempted to drop column '$colName' from 'clips' table. If it existed, it was dropped.");
            } catch (e) {
              // Log if dropping failed for reasons other than "no such column"
              // SqliteException(1) with "no such column" is expected if already removed.
              if (e is SqliteException && e.message.contains('no such column')) {
                 logInfo(_logTag, "Column '$colName' not found in 'clips' table (already dropped or never existed).");
              } else {
                 logWarning(_logTag, "Failed to drop column '$colName' from 'clips' table: $e. It might not exist or another error occurred.");
              }
            }
          }
        }
        // Add more 'if (from == X && to == Y)' blocks for future migrations.
      },
    );
  }

  // Close the database connection
  Future<void> closeConnection() async {
    logInfo(_logTag, "Closing project database connection");
    await close();
  }

  // Static log helper
  static void _logInfo(String tag, String message) {
    logInfo(message, tag);
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
    // Use createInBackground for potentially better performance,
    // and add setup to enable WAL mode.
    return NativeDatabase.createInBackground(
      file,
      logStatements: true, // Keep logging enabled
      setup: (database) {
        // Enable WAL mode for better concurrency. This is crucial!
        database.execute('pragma journal_mode = WAL;');
        ProjectDatabase._logInfo(
          'ProjectDatabase', // Pass tag explicitly as it's static context
          'Enabled WAL journal mode for database: $databasePath',
        );
      },
      // Optional: Consider isolateSetup if specific native libs need loading
      // isolateSetup: () { ... }
      // Optional: Consider readPool if high read concurrency is needed
      // readPool: 4,
    );
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

  static ProjectDatabaseAssetDao createAssetDao(ProjectDatabase db) {
    return ProjectDatabaseAssetDao(db);
  }
}
