import 'package:flutter/foundation.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart';
import 'dart:math';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';

class RollEditCommand implements TimelineCommand {
  final int leftClipId;
  final int rightClipId;
  final int newBoundaryFrame;
  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final ValueNotifier<List<ClipModel>> clipsNotifier;

  ClipModel? _originalLeftClipState;
  ClipModel? _originalRightClipState;

  static const _logTag = "RollEditCommand";

  RollEditCommand({
    required this.leftClipId,
    required this.rightClipId,
    required this.newBoundaryFrame,
    required this.clipsNotifier,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[RollEditCommand] Executing: left=$leftClipId, right=$rightClipId, boundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final currentClips = clipsNotifier.value;
    final left = currentClips.firstWhereOrNull(
      (c) => c.databaseId == leftClipId,
    );
    final right = currentClips.firstWhereOrNull(
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

    _originalLeftClipState = left.copyWith();
    _originalRightClipState = right.copyWith();

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
      clipsNotifier.value = updatedClips;

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
}
