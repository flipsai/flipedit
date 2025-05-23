import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/persistence/dao/change_log_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'package:flipedit/viewmodels/commands/move_clip_command.dart';
import 'package:flipedit/viewmodels/commands/roll_edit_command.dart';
import 'package:flipedit/viewmodels/commands/add_clip_command.dart'; // Import AddClipCommand
import 'package:flipedit/viewmodels/commands/resize_clip_command.dart'; // Import ResizeClipCommand
import 'package:drift/drift.dart';

// Factory function type to deserialize a command from its ChangeLog data.
// It needs access to services (like ProjectDatabaseService) to instantiate commands
// that might depend on DAOs or other services.
typedef CommandFromJsonFactory =
    UndoableCommand Function(
      ProjectDatabaseService projectDatabaseService,
      Map<String, dynamic> jsonData,
    );

class UndoRedoService {
  final ProjectDatabaseService _projectDatabaseService;
  ChangeLogDao get _changeLogDao => _projectDatabaseService.changeLogDao;

  final List<ChangeLog> _undoStack = [];
  final List<ChangeLog> _redoStack = [];
  final ValueNotifier<bool> canUndo = ValueNotifier(false);
  final ValueNotifier<bool> canRedo = ValueNotifier(false);

  // Map to store command deserialization factories
  // Key: command type string (from ChangeLog.action)
  // Value: Factory function to create the command instance
  final Map<String, CommandFromJsonFactory> _commandFactories =
      {}; // Initialize empty

  UndoRedoService({required ProjectDatabaseService projectDatabaseService})
    : _projectDatabaseService = projectDatabaseService {
    // Register command factories here
    registerCommandFactory(
      MoveClipCommand.commandType,
      (dbService, jsonData) => MoveClipCommand.fromJson(dbService, jsonData),
    );
    registerCommandFactory(
      RollEditCommand.commandType,
      (dbService, jsonData) => RollEditCommand.fromJson(dbService, jsonData),
    );
    registerCommandFactory(
      // Register AddClipCommand
      AddClipCommand.commandType,
      (dbService, jsonData) => AddClipCommand.fromJson(dbService, jsonData),
    );
    registerCommandFactory(
      // Register ResizeClipCommand
      ResizeClipCommand.commandType,
      (dbService, jsonData) => ResizeClipCommand.fromJson(dbService, jsonData),
    );
    // Example for other commands:
    // registerCommandFactory(
    //   ResizeClipCommand.commandType,
    //   (dbService, jsonData) => ResizeClipCommand.fromJson(dbService, jsonData)
    // );
  }

  Future<void> init() async {
    final logs = await _changeLogDao.getAllLogs();
    _undoStack.clear();
    _undoStack.addAll(logs);
    _redoStack.clear();
    _updateNotifiers();
    // TODO: Consider if initial state needs to be reconstructed by replaying logs
    // or if the app always loads the latest state from other DAOs.
    // For now, just loading logs for undo history.
  }

  UndoableCommand _deserializeCommand(ChangeLog entry) {
    final factory = _commandFactories[entry.action];
    if (factory == null) {
      throw Exception('Unknown command action type: ${entry.action}');
    }

    final commandData = {
      'newData': jsonDecode(entry.newData!) as Map<String, dynamic>,
      'oldData':
          entry.oldData != null
              ? jsonDecode(entry.oldData!) as Map<String, dynamic>
              : null,
      'entityId': entry.entityId, // Pass entityId too
    };
    return factory(_projectDatabaseService, commandData);
  }

  Future<void> executeCommand(UndoableCommand command, String entityId) async {
    // The command's execute method should internally store the "before" state
    // if it needs it for undo, or it should be passed during construction.
    // The `toChangeLog` method will then use this stored "before" state as `oldData`.
    await command.execute();

    final changeLogDataFromCommand = command.toChangeLog(entityId);

    // Create a companion for insertion, ensuring the ID field is absent for auto-increment.
    final companionForInsert = ChangeLogsCompanion(
      entity: Value(changeLogDataFromCommand.entity),
      entityId: Value(changeLogDataFromCommand.entityId),
      action: Value(changeLogDataFromCommand.action),
      oldData:
          changeLogDataFromCommand.oldData == null
              ? const Value.absent()
              : Value(changeLogDataFromCommand.oldData!),
      newData:
          changeLogDataFromCommand.newData == null
              ? const Value.absent()
              : Value(changeLogDataFromCommand.newData!),
      timestamp: Value(changeLogDataFromCommand.timestamp),
    );

    final int newLogId = await _changeLogDao.insertChange(companionForInsert);
    final ChangeLog insertedLog = changeLogDataFromCommand.copyWith(
      id: newLogId,
    );

    _undoStack.add(insertedLog);
    _redoStack.clear();
    _updateNotifiers();
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;

    final entryToUndo = _undoStack.removeLast();
    final command = _deserializeCommand(entryToUndo);

    await command.undo();

    _redoStack.add(entryToUndo);
    _updateNotifiers();
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;

    final entryToRedo = _redoStack.removeLast();
    final command = _deserializeCommand(entryToRedo);

    await command.execute();

    _undoStack.add(entryToRedo);
    _updateNotifiers();
  }

  void _updateNotifiers() {
    canUndo.value = _undoStack.isNotEmpty;
    canRedo.value = _redoStack.isNotEmpty;
  }

  /// Registers a factory for deserializing a specific command type.
  void registerCommandFactory(
    String actionType,
    CommandFromJsonFactory factory,
  ) {
    if (_commandFactories.containsKey(actionType)) {
      if (kDebugMode) {
        print(
          "Warning: Overwriting command factory for action type '$actionType'",
        );
      }
    }
    _commandFactories[actionType] = factory;
  }

  /// Clears all undo/redo history.
  Future<void> clearHistory() async {
    _undoStack.clear();
    _redoStack.clear();
    // Use the correct Drift way to delete all entries from the table
    await _changeLogDao.delete(_changeLogDao.changeLogs).go();
    _updateNotifiers();
  }
}
