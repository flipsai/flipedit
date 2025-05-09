import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/commands/undoable_command.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/persistence/database/project_database.dart' show ChangeLog;
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import 'dart:math';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

class RollEditCommand implements TimelineCommand, UndoableCommand {
  final int leftClipId;
  final int rightClipId;
  final int newBoundaryFrame;
  
  // Dependencies
  final ProjectDatabaseService _projectDatabaseService;
  final ValueNotifier<List<ClipModel>> _clipsNotifier; // Made private

  // State for undo/redo and serialization
  ClipModel? _originalLeftClipState;
  ClipModel? _originalRightClipState;
  ClipModel? _newLeftClipStateAfterExecute;
  ClipModel? _newRightClipStateAfterExecute;

  static const String commandType = 'rollEdit'; // Added commandType
  static const _logTag = "RollEditCommand";

  RollEditCommand({
    required this.leftClipId,
    required this.rightClipId,
    required this.newBoundaryFrame,
    // Dependencies
    required ProjectDatabaseService projectDatabaseService,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    // Optional for deserialization
    ClipModel? originalLeftClipState,
    ClipModel? originalRightClipState,
  })  : _projectDatabaseService = projectDatabaseService,
        _clipsNotifier = clipsNotifier,
        _originalLeftClipState = originalLeftClipState,
        _originalRightClipState = originalRightClipState;

  @override
  Future<void> execute() async {
    final bool isRedo = _originalLeftClipState != null && _originalRightClipState != null;

    logger.logInfo(
      '[RollEditCommand] Executing: left=$leftClipId, right=$rightClipId, boundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final currentClips = _clipsNotifier.value; // Use private notifier
    ClipModel? left = currentClips.firstWhereOrNull(
      (c) => c.databaseId == leftClipId,
    );
    ClipModel? right = currentClips.firstWhereOrNull(
      (c) => c.databaseId == rightClipId,
    );

    if (left == null || right == null) {
      logger.logError(
        '[RollEditCommand] Left ($leftClipId) or Right ($rightClipId) clip not found',
        _logTag,
      );
      throw Exception('Clips for roll edit not found');
    }

    if (_projectDatabaseService.clipDao == null) {
      logger.logError('[RollEditCommand] Clip DAO not initialized', _logTag);
      throw Exception('Clip DAO not initialized');
    }

    if (!isRedo) {
      _originalLeftClipState = left.copyWith();
      _originalRightClipState = right.copyWith();
    }
    // else, original states are already populated from fromJson or previous execute.

    // Clear "after execute" states
    _newLeftClipStateAfterExecute = null;
    _newRightClipStateAfterExecute = null;

    if (left.trackId != right.trackId) {
      logger.logWarning(
        '[RollEditCommand] Clips are not on the same track.',
        _logTag,
      );
      return;
    }
    if (left.endFrame != right.startFrame) {
      logger.logWarning(
        '[RollEditCommand] Clips are not adjacent (left end frame ${left.endFrame} != right start frame ${right.startFrame}).',
        _logTag,
      );
      return;
    }

    final leftMinBoundaryFrame = left.startFrame + 1;
    final leftMaxBoundaryFrame =
        left.startFrame + (left.endFrameInSource - left.startFrameInSource);

    final rightMinBoundaryFrame =
        right.endFrame - (right.endFrameInSource - right.startFrameInSource);
    final rightMaxBoundaryFrame = right.endFrame - 1;

    final minValidBoundaryFrame = max(
      leftMinBoundaryFrame,
      rightMinBoundaryFrame,
    );
    final maxValidBoundaryFrame = min(
      leftMaxBoundaryFrame,
      rightMaxBoundaryFrame,
    );

    final clampedBoundaryFrame = newBoundaryFrame.clamp(
      minValidBoundaryFrame,
      maxValidBoundaryFrame,
    );

    if (clampedBoundaryFrame <= left.startFrame ||
        clampedBoundaryFrame >= right.endFrame) {
      logger.logWarning(
        '[RollEditCommand] Clamped boundary $clampedBoundaryFrame is outside valid range (${left.startFrame + 1} - ${right.endFrame - 1}). No change applied.',
        _logTag,
      );
      return;
    }

    final newBoundaryMs = ClipModel.framesToMs(clampedBoundaryFrame);

    final newLeftEndMsOnTrack = newBoundaryMs;
    final newLeftEndInSourceMs =
        left.startTimeInSourceMs +
        (newLeftEndMsOnTrack - left.startTimeOnTrackMs);

    final newRightStartMsOnTrack = newBoundaryMs;
    final newRightStartInSourceMs =
        right.startTimeInSourceMs +
        (newRightStartMsOnTrack - right.startTimeOnTrackMs);

    try {
      await _projectDatabaseService.clipDao!
          .updateClipFields(left.databaseId!, {
            'endTimeOnTrackMs': newLeftEndMsOnTrack,
            'endTimeInSourceMs': newLeftEndInSourceMs,
          }, log: false);

      await _projectDatabaseService.clipDao!
          .updateClipFields(right.databaseId!, {
            'startTimeOnTrackMs': newRightStartMsOnTrack,
            'startTimeInSourceMs': newRightStartInSourceMs,
          }, log: true);

      logger.logDebug('[RollEditCommand] Updating ViewModel state...', _logTag);
      final updatedClips = List<ClipModel>.from(currentClips);
      final leftIndex = updatedClips.indexWhere(
        (c) => c.databaseId == leftClipId,
      );
      final rightIndex = updatedClips.indexWhere(
        (c) => c.databaseId == rightClipId,
      );

      if (leftIndex != -1) {
        updatedClips[leftIndex] = updatedClips[leftIndex].copyWith(
          endTimeOnTrackMs: newLeftEndMsOnTrack,
          endTimeInSourceMs: newLeftEndInSourceMs,
        );
      }
      if (rightIndex != -1) {
        updatedClips[rightIndex] = updatedClips[rightIndex].copyWith(
          startTimeOnTrackMs: newRightStartMsOnTrack,
          startTimeInSourceMs: newRightStartInSourceMs,
        );
      }
      _clipsNotifier.value = updatedClips; // Update UI

      // Capture the state of the clips *after* the operation for redo/serialization
      _newLeftClipStateAfterExecute = updatedClips.firstWhereOrNull((c) => c.databaseId == leftClipId)?.copyWith();
      _newRightClipStateAfterExecute = updatedClips.firstWhereOrNull((c) => c.databaseId == rightClipId)?.copyWith();
      
      logger.logInfo(
        '[RollEditCommand] Successfully performed roll edit.',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        '[RollEditCommand] Error performing roll edit: $e',
        _logTag,
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      '[RollEditCommand] Undoing roll edit for left=$leftClipId, right=$rightClipId',
      _logTag,
    );
    if (_originalLeftClipState == null || _originalRightClipState == null) {
      logger.logError(
        '[RollEditCommand] Cannot undo: Original state not saved',
        _logTag,
      );
      return;
    }
    if (_projectDatabaseService.clipDao == null) {
      logger.logError(
        '[RollEditCommand] Clip DAO not initialized for undo',
        _logTag,
      );
      throw Exception('Clip DAO not initialized for undo');
    }

    try {
      await _projectDatabaseService.clipDao!
          .updateClipFields(_originalLeftClipState!.databaseId!, {
            'endTimeOnTrackMs': _originalLeftClipState!.endTimeOnTrackMs,
            'endTimeInSourceMs': _originalLeftClipState!.endTimeInSourceMs,
          }, log: false);

      await _projectDatabaseService.clipDao!
          .updateClipFields(_originalRightClipState!.databaseId!, {
            'startTimeOnTrackMs': _originalRightClipState!.startTimeOnTrackMs,
            'startTimeInSourceMs': _originalRightClipState!.startTimeInSourceMs,
          }, log: true);

      logger.logDebug(
        '[RollEditCommand][Undo] ViewModel state should refresh via listeners.',
        _logTag,
      );
      logger.logInfo(
        '[RollEditCommand] Successfully undone roll edit.',
        _logTag,
      );

      _originalLeftClipState = null;
      _originalRightClipState = null;
    } catch (e) {
      logger.logError('[RollEditCommand] Error undoing roll edit: $e', _logTag);
      rethrow;
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      // No 'commandType' needed here as UndoRedoService.executeCommand adds it to ChangeLog.
      // This toJson is for the 'oldData' and 'newData' fields within the ChangeLog's jsonData.
      'oldData': {
        'originalLeftClipState': _originalLeftClipState?.toJson(),
        'originalRightClipState': _originalRightClipState?.toJson(),
      },
      'newData': {
        // Parameters needed to re-execute or identify the command
        'leftClipId': leftClipId,
        'rightClipId': rightClipId,
        'newBoundaryFrame': newBoundaryFrame,
        // State after execution for potential re-application or inspection
        'newLeftClipStateAfterExecute': _newLeftClipStateAfterExecute?.toJson(),
        'newRightClipStateAfterExecute': _newRightClipStateAfterExecute?.toJson(),
      },
    };
  }

  @override
  ChangeLog toChangeLog(String passedEntityId) {
    // The `toJson()` method provides the structure for `oldData` and `newData`
    // The ChangeLog table itself doesn't have a single 'jsonData' field,
    // but rather 'old_data' and 'new_data' text fields.
    // The UndoRedoService will take the output of `command.toJson()` and
    // store its 'oldData' and 'newData' parts appropriately.
    // The `ChangeLog` object here should represent the command itself.

    final commandState = toJson(); // Gets {'oldData': {...}, 'newData': {...}}

    // The `ChangeLog` data class (from project_database.g.dart, based on tables/change_logs.dart)
    // is used by the DAO. Its constructor will match its fields.
    // The `UndoRedoService` is responsible for creating this `ChangeLog` object
    // using the command's `commandType`, the `entityId` passed to `executeCommand`,
    // and the result of `command.toJson()`.
    // So, this `toChangeLog` method in the command should actually prepare the
    // `ChangeLog` data class instance.

    // The `ChangeLogs` table has: entity, entityId, action, oldData, newData, timestamp
    // `commandType` from the command maps to `action` in ChangeLog for now.
    // `entity` could be 'clip', 'track', etc. For RollEdit, it's 'clip'.
    // `entityId` is `passedEntityId`.
    // `oldData` and `newData` in ChangeLog table store the JSON strings.

    return ChangeLog(
      // id is auto-incremented by the database, so it's not set here
      // when creating a new entry. If ChangeLog is a data class, id might be required.
      // Assuming ChangeLog constructor can handle id being null or a default for inserts.
      // If using ChangeLogsCompanion, it would be:
      // return ChangeLogsCompanion.insert(
      //   entity: 'clip',
      //   entityId: passedEntityId, // This is the leftClipId for RollEdit
      //   action: RollEditCommand.commandType,
      //   oldData: Value(jsonEncode(commandState['oldData'])),
      //   newData: Value(jsonEncode(commandState['newData'])),
      //   timestamp: DateTime.now().millisecondsSinceEpoch,
      // );
      // For simplicity, assuming ChangeLog data class can be constructed directly:
      id: -1, // Placeholder, DB will assign. Or make nullable in data class if not required.
      entity: 'clip', // The primary entity type this command operates on
      entityId: passedEntityId, // The specific ID of the left clip
      action: RollEditCommand.commandType, // Describes the operation
      oldData: jsonEncode(commandState['oldData']), // JSON string
      newData: jsonEncode(commandState['newData']), // JSON string
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory RollEditCommand.fromJson(
      ProjectDatabaseService projectDatabaseService,
      Map<String, dynamic> commandData) { // commandData is the decoded jsonData from ChangeLog

    final oldData = commandData['oldData'] as Map<String, dynamic>?;
    final newData = commandData['newData'] as Map<String, dynamic>;

    ClipModel? originalLeftClipState;
    if (oldData?['originalLeftClipState'] != null) {
      originalLeftClipState = ClipModel.fromJson(oldData!['originalLeftClipState'] as Map<String, dynamic>);
    }
    ClipModel? originalRightClipState;
    if (oldData?['originalRightClipState'] != null) {
      originalRightClipState = ClipModel.fromJson(oldData!['originalRightClipState'] as Map<String, dynamic>);
    }

    final command = RollEditCommand(
      leftClipId: newData['leftClipId'] as int,
      rightClipId: newData['rightClipId'] as int,
      newBoundaryFrame: newData['newBoundaryFrame'] as int,
      projectDatabaseService: projectDatabaseService, // Passed in
      clipsNotifier: di<TimelineViewModel>().clipsNotifier, // Get from di
      originalLeftClipState: originalLeftClipState, // For undo
      originalRightClipState: originalRightClipState, // For undo
    );

    // Restore "after execute" states for redo consistency, if present in newData
    if (newData['newLeftClipStateAfterExecute'] != null) {
      command._newLeftClipStateAfterExecute = ClipModel.fromJson(newData['newLeftClipStateAfterExecute'] as Map<String, dynamic>);
    }
    if (newData['newRightClipStateAfterExecute'] != null) {
      command._newRightClipStateAfterExecute = ClipModel.fromJson(newData['newRightClipStateAfterExecute'] as Map<String, dynamic>);
    }
    
    return command;
  }
}
