import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class DeleteTrackCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final int trackId;

  DeleteTrackCommand({required this.vm, required this.trackId});

  @override
  Future<void> execute() async {
    logger.logInfo('Executing DeleteTrackCommand for track $trackId', runtimeType.toString());
    try {
      // Access the service through the passed ViewModel instance
      await vm.projectDatabaseService.deleteTrack(trackId);
      // Refreshing is handled by ViewModel listeners on ProjectDatabaseService changes
    } catch (e) {
      logger.logError('Error executing DeleteTrackCommand for track $trackId: $e', runtimeType.toString());
      // Re-throw or handle as needed
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logWarning('Undo for DeleteTrackCommand not implemented yet.', runtimeType.toString());
    // TODO: Implement undo logic (e.g., restore track and its clips)
  }
}