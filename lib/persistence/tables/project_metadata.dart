import 'package:drift/drift.dart';

@DataClassName('ProjectMetadata')
class ProjectMetadataTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  TextColumn get databasePath => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
} 