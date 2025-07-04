import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class PlayPauseCommand extends TimelineCommand {
  final TimelineNavigationViewModel vm;
  bool _wasPlaying = false;

  PlayPauseCommand({required this.vm});

  @override
  Future<void> execute() async {
    logger.logInfo(
      'Executing PlayPauseCommand: current state isPlaying=${vm.isPlaying}',
      runtimeType.toString(),
    );
    
    try {
      _wasPlaying = vm.isPlaying;
      
      if (_wasPlaying) {
        vm.stopPlayback();
        logger.logInfo('Playback stopped', runtimeType.toString());
      } else {
        await vm.startPlayback();
        logger.logInfo('Playback started', runtimeType.toString());
      }
    } catch (e) {
      logger.logError(
        'Error executing PlayPauseCommand: $e',
        runtimeType.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      'Undoing PlayPauseCommand: restoring state to isPlaying=$_wasPlaying',
      runtimeType.toString(),
    );
    
    try {
      if (_wasPlaying) {
        await vm.startPlayback();
        logger.logInfo('Playback restored to playing state', runtimeType.toString());
      } else {
        vm.stopPlayback();
        logger.logInfo('Playback restored to stopped state', runtimeType.toString());
      }
    } catch (e) {
      logger.logError(
        'Error undoing PlayPauseCommand: $e',
        runtimeType.toString(),
      );
      rethrow;
    }
  }
}