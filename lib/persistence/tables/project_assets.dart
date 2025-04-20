import 'package:drift/drift.dart';

// This table definition is for the per-project database structure
class ProjectAssets extends Table {
  // Primary key for the asset
  IntColumn get id => integer().autoIncrement()();
  
  // Asset properties
  TextColumn get name => text()();
  TextColumn get path => text()(); // Path to the asset file
  TextColumn get type => text()(); // video, audio, image, etc.
  TextColumn get mimeType => text().nullable()(); // For web/preview compatibility
  
  // Asset metadata
  IntColumn get durationMs => integer().nullable()(); // For time-based assets like video/audio
  IntColumn get width => integer().nullable()(); // For visual assets
  IntColumn get height => integer().nullable()(); // For visual assets
  RealColumn get fileSize => real().nullable()(); // Size in bytes
  
  // Additional metadata as JSON string (can be null)
  TextColumn get metadataJson => text().nullable()();
  
  // Thumbnails, previews, etc.
  TextColumn get thumbnailPath => text().nullable()(); // Path to thumbnail file
  
  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
} 