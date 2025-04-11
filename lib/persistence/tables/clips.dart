import 'package:drift/drift.dart';
import 'package:flipedit/persistence/tables/tracks.dart'; // Import Tracks table for foreign key

class Clips extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Foreign key to the Tracks table
  IntColumn get trackId => integer().references(Tracks, #id)();

  // Clip metadata
  TextColumn get name => text().withDefault(const Constant('Untitled Clip'))(); // Added name
  TextColumn get type => text().withDefault(const Constant('video'))(); // Added type (e.g., 'video', 'audio')

  // Source media information
  TextColumn get sourcePath => text()(); // Path to the original media file
  IntColumn get startTimeInSourceMs => integer().withDefault(const Constant(0))(); // Start time within the source file in milliseconds
  IntColumn get endTimeInSourceMs => integer()(); // End time within the source file in milliseconds

  // Timeline information
  IntColumn get startTimeOnTrackMs => integer().withDefault(const Constant(0))(); // Start time of the clip on the track in milliseconds
  // Duration can be calculated: endTimeInSourceMs - startTimeInSourceMs

  // Optional: order within the track if clips can overlap or have specific sequence needs beyond start time
  // IntColumn get order => integer().withDefault(const Constant(0))();

  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)(); // Consider auto-update trigger if needed
} 