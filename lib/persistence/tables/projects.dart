import 'package:drift/drift.dart';

@DataClassName('Project') // Customize the generated data class name if needed
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
} 