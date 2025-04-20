import 'package:drift/drift.dart';

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant('Untitled Track'))();
  IntColumn get order => integer().withDefault(const Constant(0))(); // For track ordering
  TextColumn get type => text().withDefault(const Constant('video'))(); // e.g., 'video', 'audio', 'text'

  // No foreign key to Projects table needed - each database is for a single project

  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)(); // Consider adding auto-update trigger if needed
} 