import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'dart:math'; // For max/min

/// Command to perform a roll edit between two adjacent clips.
class RollEditCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int leftClipId;
  final int rightClipId;
  final int newBoundaryFrame;

  // Store original state for undo
  ClipModel? _originalLeftClipState;
  ClipModel? _originalRightClipState;

  static const _logTag = "RollEditCommand";

  RollEditCommand({
    required this.vm,
    required this.leftClipId,
    required this.rightClipId,
    required this.newBoundaryFrame,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      '[RollEditCommand] Executing: left=$leftClipId, right=$rightClipId, boundaryFrame=$newBoundaryFrame',
      _logTag,
    );

    final left = vm.clips.firstWhereOrNull((c) => c.databaseId == leftClipId);
    final right = vm.clips.firstWhereOrNull((c) => c.databaseId == rightClipId);

    if (left == null || right == null) {
      logger.logError('[RollEditCommand] Left ($leftClipId) or Right ($rightClipId) clip not found', _logTag);
      throw Exception('Clips for roll edit not found');
    }

    // --- Store state for Undo ---
    _originalLeftClipState = left.copyWith();
    _originalRightClipState = right.copyWith();
    // --- End Store state ---


    // Validation: Must be on same track and adjacent
    if (left.trackId != right.trackId) {
       logger.logWarning('[RollEditCommand] Clips are not on the same track.', _logTag);
       return; // Or throw error
    }
    // Use frame calculation for adjacency check
    if (left.endFrame != right.startFrame) {
       logger.logWarning('[RollEditCommand] Clips are not adjacent (left end frame ${left.endFrame} != right start frame ${right.startFrame}).', _logTag);
       return; // Or throw error
    }


    // Compute valid range for the boundary (logic from original method)
    final leftMinBoundaryFrame = left.startFrame + 1; // Cannot roll before the start of left + 1 frame
    final leftMaxBoundaryFrame = left.startFrame + (left.endFrameInSource - left.startFrameInSource); // Limited by source duration

    final rightMinBoundaryFrame = right.endFrame - (right.endFrameInSource - right.startFrameInSource); // Limited by source duration
    final rightMaxBoundaryFrame = right.endFrame - 1; // Cannot roll past the end of right - 1 frame

    // The valid range is the intersection of the constraints imposed by both clips' source material
    final minValidBoundaryFrame = max(leftMinBoundaryFrame, rightMinBoundaryFrame);
    final maxValidBoundaryFrame = min(leftMaxBoundaryFrame, rightMaxBoundaryFrame);

    final clampedBoundaryFrame = newBoundaryFrame.clamp(minValidBoundaryFrame, maxValidBoundaryFrame);

    // Additional check: Ensure the clamped boundary is actually between the original start/end frames
    if (clampedBoundaryFrame <= left.startFrame || clampedBoundaryFrame >= right.endFrame) {
       logger.logWarning('[RollEditCommand] Clamped boundary $clampedBoundaryFrame is outside valid range (${left.startFrame + 1} - ${right.endFrame - 1}). No change applied.', _logTag);
       return; // No valid edit possible within constraints
    }


    // Compute new times based on the clamped boundary frame
    final newBoundaryMs = ClipModel.framesToMs(clampedBoundaryFrame);

    // Left clip's end time changes (on track and in source)
    final newLeftEndMsOnTrack = newBoundaryMs;
    final newLeftEndInSourceMs = left.startTimeInSourceMs + (newLeftEndMsOnTrack - left.startTimeOnTrackMs);

    // Right clip's start time changes (on track and in source)
    final newRightStartMsOnTrack = newBoundaryMs;
    final newRightStartInSourceMs = right.startTimeInSourceMs + (newRightStartMsOnTrack - right.startTimeOnTrackMs);


    try {
      // Update left clip's end time in source
      await vm.projectDatabaseService.clipDao!.updateClipFields(left.databaseId!, {
        'endTimeInSourceMs': newLeftEndInSourceMs,
        // Note: startTimeOnTrackMs for left clip does NOT change in a roll edit
      });

      // Update right clip's start time on track AND in source
      await vm.projectDatabaseService.clipDao!.updateClipFields(right.databaseId!, {
        'startTimeOnTrackMs': newRightStartMsOnTrack,
        'startTimeInSourceMs': newRightStartInSourceMs,
        // Note: endTimeInSourceMs for right clip does NOT change in a roll edit
      });

      logger.logInfo('[RollEditCommand] Successfully performed roll edit.', _logTag);
      // await vm.refreshClips(); // Rely on stream/notifier updates

    } catch (e) {
      logger.logError('[RollEditCommand] Error performing roll edit: $e', _logTag);
      // Attempt to revert if one update failed? Or rely on undo stack.
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[RollEditCommand] Undoing roll edit for left=$leftClipId, right=$rightClipId', _logTag);
    if (_originalLeftClipState == null || _originalRightClipState == null) {
      logger.logError('[RollEditCommand] Cannot undo: Original state not saved', _logTag);
      return;
    }

    try {
      // Restore left clip's original end time in source
      await vm.projectDatabaseService.clipDao!.updateClipFields(_originalLeftClipState!.databaseId!, {
        'endTimeInSourceMs': _originalLeftClipState!.endTimeInSourceMs,
      });

      // Restore right clip's original start time on track and in source
      await vm.projectDatabaseService.clipDao!.updateClipFields(_originalRightClipState!.databaseId!, {
        'startTimeOnTrackMs': _originalRightClipState!.startTimeOnTrackMs,
        'startTimeInSourceMs': _originalRightClipState!.startTimeInSourceMs,
      });

      logger.logInfo('[RollEditCommand] Successfully undone roll edit.', _logTag);
      // await vm.refreshClips(); // Rely on stream/notifier updates

      // Clear state
      _originalLeftClipState = null;
      _originalRightClipState = null;

    } catch (e) {
      logger.logError('[RollEditCommand] Error undoing roll edit: $e', _logTag);
      rethrow;
    }
  }
}