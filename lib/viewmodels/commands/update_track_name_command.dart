import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class UpdateTrackNameCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final int trackId;
  final String newName;
  String? _oldName; // To store the old name for undo

  UpdateTrackNameCommand({
    required this.vm,
    required this.trackId,
    required this.newName,
  });

  @override
  Future<void> execute() async {
    logger.logInfo('Executing UpdateTrackNameCommand for track $trackId to "$newName"', runtimeType.toString());
    try {
      // Store the old name before updating
      final track = vm.tracksNotifierForView.value.firstWhere((t) => t.id == trackId);
      _oldName = track.name;

      final success = await vm.projectDatabaseService.updateTrackName(trackId, newName);
      if (!success) {
        logger.logError('Failed to update track name in DB for track $trackId', runtimeType.toString());
        _oldName = null; // Clear old name if update failed
      }
      // Refreshing is handled by ViewModel listeners on ProjectDatabaseService changes
    } catch (e) {
      logger.logError('Error executing UpdateTrackNameCommand for track $trackId: $e', runtimeType.toString());
      _oldName = null; // Clear old name on error
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    if (_oldName == null) {
       logger.logWarning('Cannot undo UpdateTrackNameCommand for track $trackId: old name not available.', runtimeType.toString());
      return;
    }
    logger.logInfo('Undoing UpdateTrackNameCommand for track $trackId to "$_oldName"', runtimeType.toString());
    try {
       final success = await vm.projectDatabaseService.updateTrackName(trackId, _oldName!);
        if (!success) {
        logger.logError('Failed to undo track name update in DB for track $trackId', runtimeType.toString());
      }
      // Refreshing is handled by ViewModel listeners on ProjectDatabaseService changes
    } catch (e) {
      logger.logError('Error undoing UpdateTrackNameCommand for track $trackId: $e', runtimeType.toString());
       rethrow;
    }
  }
}