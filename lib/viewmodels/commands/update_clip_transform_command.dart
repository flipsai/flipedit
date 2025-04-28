// lib/viewmodels/commands/update_clip_transform_command.dart
import 'package:fluent_ui/fluent_ui.dart'; // For Rect
import 'package:flutter_box_transform/flutter_box_transform.dart'; // For Flip

import 'package:flipedit/services/project_database_service.dart';
// import 'package:flipedit/services/undo_redo_service.dart'; // Not needed directly
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'timeline_command.dart'; // Import the base class


/// Command to update the preview transform (Rect and Flip) of a clip.
/// Changes are logged automatically by the DAO via ChangeLogMixin.
class UpdateClipTransformCommand extends TimelineCommand { // Extend TimelineCommand
  final int clipId;
  final Rect newRect;
  final Flip newFlip;
  final Rect oldRect;
  final Flip oldFlip;

  // Dependencies needed by this command
  final ProjectDatabaseService projectDatabaseService;
  final TimelineViewModel timelineViewModel; // Add TimelineViewModel field

  UpdateClipTransformCommand({
    // Remove vm parameter
    required this.timelineViewModel, // Add timelineViewModel param
    required this.projectDatabaseService, // Add projectDatabaseService param
    required this.clipId,
    required this.newRect,
    required this.newFlip,
    required this.oldRect,
    required this.oldFlip,
  }) { // Removed super call
          logger.logInfo('UpdateClipTransformCommand created for clip $clipId', 'Command');
        }

  // String get actionDescription => 'Update Clip Transform'; // Optional: Keep if needed by TimelineViewModel


  @override // Add override since it's defined in TimelineCommand
  Future<void> execute() async {
    logger.logInfo('Executing UpdateClipTransformCommand for clip $clipId', 'Command');
    await _updateTransform(newRect, newFlip);
    await timelineViewModel.refreshClips(); // Use timelineViewModel field
  }

  // Method called by TimelineViewModel.undo/redo (if it uses command objects for that)
  // OR called by UndoRedoService logic if it were command-based.
  // Since UndoRedoService uses DB logs, this method might only be needed
  // if TimelineViewModel keeps its own command stack for some reason.
  // Let's keep it for now, assuming TimelineViewModel might use it.
  @override // Add override since it's defined in TimelineCommand
  Future<void> undo() async {
     logger.logInfo('Undoing UpdateClipTransformCommand for clip $clipId (via command object)', 'Command');
    await _updateTransform(oldRect, oldFlip);
    await timelineViewModel.refreshClips(); // Use timelineViewModel field
  }

  Future<void> _updateTransform(Rect rectToApply, Flip flipToApply) async {
    final clip = timelineViewModel.clips.firstWhere((c) => c.databaseId == clipId, orElse: () { // Use timelineViewModel field
       logger.logError('Clip $clipId not found during transform update.', 'Command');
       // Return a dummy clip or throw? For safety, return null and handle below.
       // This requires ClipModel? return type, let's adjust the logic.
       // For now, assume it's found for simplicity.
       throw StateError('Clip $clipId not found');
    });


    // Create the updated clip model with new metadata
    final updatedClip = clip
        .copyWithPreviewRect(rectToApply)
        .copyWithPreviewFlip(flipToApply);

    try {
       // Use the clipDao from the service to update the clip
      if (projectDatabaseService.clipDao == null) {
        throw StateError('ClipDao is not initialized in ProjectDatabaseService.');
      }
      await projectDatabaseService.clipDao!.updateClip(updatedClip.toDbCompanion());
       logger.logInfo('Clip $clipId transform updated in DB: Rect=$rectToApply, Flip=$flipToApply', 'Command');
    } catch (e) {
       logger.logError('Failed to update clip $clipId transform in DB: $e', 'Command');
       // Rethrow or handle? Rethrowing might be better for UndoRedoService.
       rethrow;
    }
  }
}