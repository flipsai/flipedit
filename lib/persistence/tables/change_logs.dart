import 'package:drift/drift.dart';

// Table for logging all changes (insert/update/delete) to project data
class ChangeLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()(); // "insert", "update", "delete"
  TextColumn get oldData => text().nullable()(); // JSON of old row
  TextColumn get newData => text().nullable()(); // JSON of new row
  IntColumn get timestamp => integer()(); // milliseconds since epoch
}
