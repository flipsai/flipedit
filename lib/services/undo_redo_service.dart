import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/persistence/dao/change_log_dao.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:drift/drift.dart';

class UndoRedoService {
  final ProjectDatabaseService _projectDatabaseService;
  ProjectDatabaseClipDao? get clipDao => _projectDatabaseService.clipDao;
  ChangeLogDao get changeLogDao => _projectDatabaseService.changeLogDao;

  final List<ChangeLog> _undoStack = [];
  final List<ChangeLog> _redoStack = [];
  final ValueNotifier<bool> canUndo = ValueNotifier(false);
  final ValueNotifier<bool> canRedo = ValueNotifier(false);

  UndoRedoService({required ProjectDatabaseService projectDatabaseService})
      : _projectDatabaseService = projectDatabaseService;

  /// Load all existing logs into undo stack (most recent last)
  Future<void> init() async {
    final logs = await changeLogDao.getAllLogs();
    _undoStack.clear();
    _undoStack.addAll(logs);
    _redoStack.clear();
    _updateNotifiers();
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    await _applyInverse(entry);
    _redoStack.add(entry);
    _updateNotifiers();
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    await _apply(entry);
    _undoStack.add(entry);
    _updateNotifiers();
  }

  void _updateNotifiers() {
    canUndo.value = _undoStack.isNotEmpty;
    canRedo.value = _redoStack.isNotEmpty;
  }

  Future<void> _apply(ChangeLog entry) async {
    final data = jsonDecode(entry.newData!) as Map<String, dynamic>;
    await _applyAction(entry.action, entry.entityId, data);
  }

  Future<void> _applyInverse(ChangeLog entry) async {
    if (entry.action == 'insert') {
      await clipDao?.deleteClip(int.parse(entry.entityId));
    } else if (entry.action == 'delete') {
      final data = jsonDecode(entry.oldData!) as Map<String, dynamic>;
      final comp = _companionFromJson(data);
      await clipDao?.insertClip(comp);
    } else if (entry.action == 'update') {
      final data = jsonDecode(entry.oldData!) as Map<String, dynamic>;
      final comp = _companionFromJson(data);
      await clipDao?.updateClip(comp);
    }
  }

  Future<void> _applyAction(String action, String id, Map<String, dynamic> data) async {
    if (action == 'insert') {
      final comp = _companionFromJson(data);
      await clipDao?.insertClip(comp);
    } else if (action == 'delete') {
      await clipDao?.deleteClip(int.parse(id));
    } else if (action == 'update') {
      final comp = _companionFromJson(data);
      await clipDao?.updateClip(comp);
    }
  }

  ClipsCompanion _companionFromJson(Map<String, dynamic> json) {
    return ClipsCompanion(
      id: Value(json['id'] as int),
      trackId: Value(json['trackId'] as int),
      name: Value(json['name'] as String),
      type: Value(json['type'] as String),
      sourcePath: Value(json['sourcePath'] as String),
      startTimeInSourceMs: Value(json['startTimeInSourceMs'] as int),
      endTimeInSourceMs: Value(json['endTimeInSourceMs'] as int),
      startTimeOnTrackMs: Value(json['startTimeOnTrackMs'] as int),
      metadataJson: json['metadataJson'] != null
          ? Value(json['metadataJson'] as String)
          : const Value.absent(),
      createdAt: Value(
        json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.parse(json['createdAt'] as String)
      ),
      updatedAt: Value(
        json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : DateTime.parse(json['updatedAt'] as String)
      ),
    );
  }
}
