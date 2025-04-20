import 'package:drift/drift.dart';
import 'package:flipedit/models/enums/clip_type.dart';

@DataClassName('ProjectAssetEntry') // Use a different name to avoid conflict with model
class ProjectAssets extends Table {
  IntColumn get id => integer().autoIncrement()();
  // No projectId needed - each database is for a single project
  TextColumn get name => text()();
  IntColumn get type => intEnum<ClipType>()(); // Store enum as integer
  TextColumn get sourcePath => text()();
  IntColumn get durationMs => integer()();

  // Add created_at/updated_at if needed later
} 