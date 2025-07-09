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
    
    // Apply the old transform values to the timeline player
    await _applyTransformToTimelinePlayer(
      oldPositionX,
      oldPositionY,
      oldWidth,
      oldHeight,
    );
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
    await _applyTransformToTimelinePlayer(
      newPositionX,
      newPositionY,
      newWidth,
      newHeight,
    );
  }

  /// Apply transform values to the timeline player
  Future<void> _applyTransformToTimelinePlayer(
    double positionX,
    double positionY,
    double width,
    double height,
  ) async {
    try {
      final videoPlayerService = di<VideoPlayerService>();
      if (videoPlayerService.activePlayer is! GesTimelinePlayer) {
        logger.logInfo('No active timeline player to refresh.', 'Command');
        return;
      }

      final timelinePlayer = videoPlayerService.activePlayer as GesTimelinePlayer;
      
      // Use the new updateClipTransform method instead of reloading the entire timeline
      // This method now handles on-demand frame rendering internally
      await timelinePlayer.updateClipTransform(
        clipId: clipId,
        previewPositionX: positionX,
        previewPositionY: positionY,
        previewWidth: width,
        previewHeight: height,
      );
      
      
      logger.logInfo('Timeline player updated clip $clipId transform: pos=($positionX,$positionY), size=($width,$height)', 'Command');
    } catch (e) {
      logger.logError('Failed to update clip transform: $e', 'Command');
    }
  }
}
