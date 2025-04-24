import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/tables/change_logs.dart';

part 'change_log_dao.g.dart';

@DriftAccessor(tables: [ChangeLogs])
class ChangeLogDao extends DatabaseAccessor<ProjectDatabase> with _$ChangeLogDaoMixin {
  ChangeLogDao(ProjectDatabase db) : super(db);

  Future<int> insertChange(ChangeLogsCompanion entry) {
    return into(changeLogs).insert(entry);
  }

  Future<List<ChangeLog>> getAllLogs() {
    return select(changeLogs).get();
  }
}
