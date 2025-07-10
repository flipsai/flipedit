import 'package:flipedit/models/clip.dart';
import 'package:flutter/foundation.dart';
import 'package:flipedit/viewmodels/commands/resize_clip_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/ges_timeline_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';

/// Service to encapsulate timeline clip resize logic.
/// Stateless: all state is passed as parameters and returned as needed.
class TimelineClipResizeService {
  /// Returns a tuple of (resizingDirection, resizeAccumulatedDrag, previewStartFrame, previewEndFrame)
  Map<String, dynamic> handleResizeStart({
    required bool isMoving,
    required String direction,
    required int startFrame,
    required int endFrame,
  }) {
    if (isMoving) return {};
    return {
      'resizingDirection': direction,
      'resizeAccumulatedDrag': 0.0,
      'previewStartFrame': startFrame,
      'previewEndFrame': endFrame,
    };
  }

  /// Returns the new accumulated drag value
  double handleResizeUpdate({
    required String? resizingDirection,
    required double accumulatedPixelDelta,
  }) {
    if (resizingDirection == null) return 0.0;
    return accumulatedPixelDelta;
  }

  /// Handles resize end, issues command if needed, returns a map with reset state.
  Future<void> handleResizeEnd({
    required String? resizingDirection,
    required int? previewStartFrame,
    required int? previewEndFrame,
    required String direction,
    required double finalPixelDelta,
    required ValueNotifier<List<ClipModel>> clipsNotifier,
    required ClipModel clip,
    required double zoom,
    required Future<void> Function(ResizeClipCommand) runCommand,
    required ProjectDatabaseService projectDatabaseService,
    required GESTimelineService gesTimelineService,
    required TimelineNavigationViewModel navigationViewModel,
  }) async {
    if (resizingDirection == null ||
        previewStartFrame == null ||
        previewEndFrame == null) {
      return;
    }
    final double pxPerFrame = (zoom > 0 ? 5.0 * zoom : 5.0);
    if (pxPerFrame <= 0) {
      logger.logWarning(
        'pxPerFrame is zero or negative, cannot commit resize.',
        'TimelineClipResizeService',
      );
      return;
    }
    int minFrameDuration = 1;
    int frameDelta = (finalPixelDelta / pxPerFrame).round();
    int originalBoundaryFrame =
        direction == 'left' ? previewStartFrame : previewEndFrame;
    int newBoundaryFrame;
    if (direction == 'left') {
      newBoundaryFrame = (originalBoundaryFrame + frameDelta).clamp(
        0,
        previewEndFrame - minFrameDuration,
      );
    } else {
      newBoundaryFrame = (originalBoundaryFrame + frameDelta).clamp(
        previewStartFrame + minFrameDuration,
        previewStartFrame + 1000000,
      );
    }
    bool boundaryChanged = newBoundaryFrame != originalBoundaryFrame;
    if (boundaryChanged) {
      final command = ResizeClipCommand(
        clipId: clip.databaseId!,
        direction: direction,
        newBoundaryFrame: newBoundaryFrame,
        initialResolvedClipState: clip, // Pass the existing clip model here
        clipsNotifier: clipsNotifier,
        projectDatabaseService: projectDatabaseService,
        gesTimelineService: gesTimelineService,
      );
      try {
        await runCommand(command);
      } catch (e) {
        logger.logError(
          'Error executing ResizeClipCommand: $e',
          'TimelineClipResizeService',
        );
      }
    }
  }
}
