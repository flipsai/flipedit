import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'timeline_command.dart';
import 'package:watch_it/watch_it.dart';
import '../timeline_viewmodel.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/src/rust/api/simple.dart';

class UpdateClipTransformCommand extends TimelineCommand {
  final int clipId;

  // New state properties
  final double newPositionX;
  final double newPositionY;
  final double newWidth;
  final double newHeight;

  // Old state properties for undo
  final double oldPositionX;
  final double oldPositionY;
  final double oldWidth;
  final double oldHeight;

  final ProjectDatabaseService projectDatabaseService;
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();

  UpdateClipTransformCommand({
    required this.projectDatabaseService,
    required this.clipId,
    required this.newPositionX,
    required this.newPositionY,
    required this.newWidth,
    required this.newHeight,
    required this.oldPositionX,
    required this.oldPositionY,
    required this.oldWidth,
    required this.oldHeight,
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
    await _applyPropertiesToDb(
      posX: newPositionX,
      posY: newPositionY,
      width: newWidth,
      height: newHeight,
    );
    await _stateViewModel.refreshClips();
    
    // Refresh the timeline player to apply new transforms
    await _refreshTimelinePlayer(); 
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      'Undoing UpdateClipTransformCommand for clip $clipId',
      'Command',
    );
    await _applyPropertiesToDb(
      posX: oldPositionX,
      posY: oldPositionY,
      width: oldWidth,
      height: oldHeight,
    );
    await _stateViewModel.refreshClips();
    
    // Refresh the timeline player to apply old transforms
    await _refreshTimelinePlayer();
  }

  Future<void> _applyPropertiesToDb({
    required double posX,
    required double posY,
    required double width,
    required double height,
  }) async {
    final originalClipState = _stateViewModel.clips.firstWhere(
      (c) => c.databaseId == clipId,
      orElse: () {
        final errorMsg = 'Clip $clipId not found during transform update.';
        logger.logError(errorMsg, 'Command');
        throw StateError(errorMsg);
      },
    );

    final updatedClip = originalClipState.copyWith(
      previewPositionX: posX,
      previewPositionY: posY,
      previewWidth: width,
      previewHeight: height,
    );

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
        'Clip $clipId transform updated in DB: Pos=($posX,$posY), Width=$width, Height=$height',
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

  /// Refresh the timeline player to apply transform changes
  Future<void> _refreshTimelinePlayer() async {
    try {
      final videoPlayerService = di<VideoPlayerService>();
      if (videoPlayerService.activePlayer is! GesTimelinePlayer) {
        logger.logInfo('No active timeline player to refresh.', 'Command');
        return;
      }

      final timelineViewModel = di<TimelineViewModel>();
      final timelineData = await timelineViewModel.buildTimelineData();
      
      final timelinePlayer = videoPlayerService.activePlayer as GesTimelinePlayer;
      await timelinePlayer.loadTimeline(timelineData: timelineData);
      
      logger.logInfo('Timeline player refreshed with updated transform values.', 'Command');
    } catch (e) {
      logger.logError('Failed to refresh timeline player: $e', 'Command');
    }
  }
}
