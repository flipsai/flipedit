import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class AddTrackCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final String name;
  final String type;
  int? _newTrackId;
  int? get newTrackId => _newTrackId;

  AddTrackCommand({required this.vm, required this.name, required this.type});

  @override
  Future<void> execute() async {
    logger.logInfo(
      'Executing AddTrackCommand: name="$name", type="$type"',
      runtimeType.toString(),
    );
    try {
      _newTrackId = await vm.projectDatabaseService.addTrack(
        name: name,
        type: type,
      );
      if (_newTrackId == null) {
        logger.logError('Failed to add track to DB.', runtimeType.toString());
      } else {
        logger.logInfo(
          'Track added with ID: $_newTrackId',
          runtimeType.toString(),
        );
      }
    } catch (e) {
      logger.logError(
        'Error executing AddTrackCommand: $e',
        runtimeType.toString(),
      );
      _newTrackId = null; // Clear ID on error
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    if (_newTrackId == null) {
      logger.logWarning(
        'Cannot undo AddTrackCommand: new track ID not available.',
        runtimeType.toString(),
      );
      return;
    }
    logger.logInfo(
      'Undoing AddTrackCommand: deleting track $_newTrackId',
      runtimeType.toString(),
    );
    try {
      final success = await vm.projectDatabaseService.deleteTrack(_newTrackId!);
      if (!success) {
        logger.logError(
          'Failed to undo add track by deleting track $_newTrackId',
          runtimeType.toString(),
        );
      }
    } catch (e) {
      logger.logError(
        'Error undoing AddTrackCommand: $e',
        runtimeType.toString(),
      );
      rethrow;
    }
  }
}
