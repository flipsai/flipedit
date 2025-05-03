import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';

import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'timeline_command.dart';
import 'package:watch_it/watch_it.dart';

class UpdateClipTransformCommand extends TimelineCommand {
  final int clipId;
  final Rect newRect;
  final Flip newFlip;
  final Rect oldRect;
  final Flip oldFlip;

  final ProjectDatabaseService projectDatabaseService;
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  UpdateClipTransformCommand({
    required this.projectDatabaseService,
    required this.clipId,
    required this.newRect,
    required this.newFlip,
    required this.oldRect,
    required this.oldFlip,
  }) {
    logger.logInfo(
      'UpdateClipTransformCommand created for clip $clipId',
      'Command',
    );
  }

  @override
  Future<void> execute() async {
    logger.logInfo(
      'Executing UpdateClipTransformCommand for clip $clipId',
      'Command',
    );
    await _updateTransform(newRect, newFlip);
    await _stateViewModel.refreshClips();
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      'Undoing UpdateClipTransformCommand for clip $clipId (via command object)',
      'Command',
    );
    await _updateTransform(oldRect, oldFlip);
    await _stateViewModel.refreshClips();
  }

  Future<void> _updateTransform(Rect rectToApply, Flip flipToApply) async {
    final clip = _stateViewModel.clips.firstWhere(
      (c) => c.databaseId == clipId,
      orElse: () {
        logger.logError(
          'Clip $clipId not found during transform update.',
          'Command',
        );
        throw StateError('Clip $clipId not found');
      },
    );

    final updatedClip = clip
        .copyWithPreviewRect(rectToApply)
        .copyWithPreviewFlip(flipToApply);

    try {
      if (projectDatabaseService.clipDao == null) {
        throw StateError(
          'ClipDao is not initialized in ProjectDatabaseService.',
        );
      }
      await projectDatabaseService.clipDao!.updateClip(
        updatedClip.toDbCompanion(),
      );
      logger.logInfo(
        'Clip $clipId transform updated in DB: Rect=$rectToApply, Flip=$flipToApply',
        'Command',
      );
    } catch (e) {
      logger.logError(
        'Failed to update clip $clipId transform in DB: $e',
        'Command',
      );
      rethrow;
    }
  }
}
