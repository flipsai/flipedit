import 'package:drift/drift.dart';

// This table definition is for the per-project database structure
class Tracks extends Table {
  // Primary key for the track
  IntColumn get id => integer().autoIncrement()();

  // Track properties
  TextColumn get name => text().withDefault(const Constant('Untitled Track'))();
  TextColumn get type =>
      text().withDefault(const Constant('video'))(); // video, audio, text, etc.
  IntColumn get order => integer()(); // For ordering tracks in the timeline

  // Visual/editor settings
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();

  // Optional metadata as JSON string (can be null)
  TextColumn get metadataJson => text().nullable()();

  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
