import 'package:drift/drift.dart';

// This table definition is for the per-project database structure
class Clips extends Table {
  // Primary key for the clip
  IntColumn get id => integer().autoIncrement()();
  
  // Foreign key to the track this clip belongs to
  IntColumn get trackId => integer()();
  
  // Clip properties
  TextColumn get name => text().withDefault(const Constant('Untitled Clip'))();
  TextColumn get type => text().withDefault(const Constant('video'))(); // Corresponds to ClipType enum
  TextColumn get sourcePath => text()();
  
  // Timing information
  IntColumn get startTimeInSourceMs => integer()();
  IntColumn get endTimeInSourceMs => integer()();
  IntColumn get startTimeOnTrackMs => integer().withDefault(const Constant(0))();
  
  // Optional metadata as JSON string (can be null)
  TextColumn get metadataJson => text().nullable()();
  
  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
} 