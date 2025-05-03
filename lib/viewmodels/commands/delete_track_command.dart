import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class DeleteTrackCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final int trackId;

  DeleteTrackCommand({required this.vm, required this.trackId});

  @override
  Future<void> execute() async {
    logger.logInfo(
      'Executing DeleteTrackCommand for track $trackId',
      runtimeType.toString(),
    );
    try {
      await vm.projectDatabaseService.deleteTrack(trackId);
    } catch (e) {
      logger.logError(
        'Error executing DeleteTrackCommand for track $trackId: $e',
        runtimeType.toString(),
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logWarning(
      'Undo for DeleteTrackCommand not implemented yet.',
      runtimeType.toString(),
    );
  }
}
