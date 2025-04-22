import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/persistence/dao/change_log_dao.dart';

mixin ChangeLogMixin on DatabaseAccessor<ProjectDatabase> {
  ChangeLogDao get changeLogDao => ChangeLogDao(db);

  Future<void> logChange<T extends DataClass>({
    required String tableName,
    required String primaryKey,
    required String action,
    T? oldRow,
    T? newRow,
  }) {
    return changeLogDao.insertChange(
      ChangeLogsCompanion.insert(
        entity: tableName,
        entityId: primaryKey,
        action: action,
        oldData: Value(oldRow != null ? jsonEncode(oldRow.toJson()) : null),
        newData: Value(newRow != null ? jsonEncode(newRow.toJson()) : null),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
