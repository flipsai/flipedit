import 'package:flipedit/persistence/database/project_database.dart';

abstract class UndoableCommand {
  /// Executes the command.
  Future<void> execute();

  /// Undoes the command.
  Future<void> undo();

  /// Serializes the command's state for persistence.
  /// 'actionType' should be a unique string identifying the command type.
  /// 'oldData' should contain the necessary information to undo the command.
  /// 'newData' should contain the necessary information to redo/execute the command.
  Map<String, dynamic> toJson();

  /// Creates a ChangeLog entry representing this command.
  /// The entityId is a general identifier for the primary entity affected by the command.
  ChangeLog toChangeLog(String entityId);
}

/// Factory function type to deserialize a command from JSON.
typedef CommandFromJson =
    UndoableCommand Function(Map<String, dynamic> jsonData);
