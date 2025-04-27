import 'package:flipedit/persistence/database/project_database.dart' show Track;
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class ReorderTracksCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final int oldIndex;
  final int newIndex;
  List<Track>? _originalOrder; // To store original order for undo

  ReorderTracksCommand({
    required this.vm,
    required this.oldIndex,
    required this.newIndex,
  });

  @override
  Future<void> execute() async {
    logger.logInfo('Executing ReorderTracksCommand: $oldIndex -> $newIndex', runtimeType.toString());
    final currentTracks = List<Track>.from(vm.tracksNotifierForView.value);

    // Validate indices
    if (oldIndex < 0 || oldIndex >= currentTracks.length ||
        newIndex < 0 || newIndex >= currentTracks.length ||
        oldIndex == newIndex) {
      logger.logWarning('Invalid indices for ReorderTracksCommand. Aborting.', runtimeType.toString());
      return;
    }

    _originalOrder = List<Track>.from(currentTracks); // Store for undo

    final reorderedTracks = List<Track>.from(currentTracks);
    final trackToMove = reorderedTracks.removeAt(oldIndex);
    reorderedTracks.insert(newIndex, trackToMove);

    try {
      final success = await vm.projectDatabaseService.updateTrackOrder(reorderedTracks);
      if (!success) {
         logger.logError('Failed to update track order in DB.', runtimeType.toString());
        _originalOrder = null; // Clear undo state if persistence failed
      }
       // Refreshing is handled by ViewModel listeners on ProjectDatabaseService changes
    } catch (e) {
       logger.logError('Error executing ReorderTracksCommand: $e', runtimeType.toString());
       _originalOrder = null; // Clear undo state on error
       rethrow;
    }
  }

  @override
  Future<void> undo() async {
    if (_originalOrder == null) {
      logger.logWarning('Cannot undo ReorderTracksCommand: original order not available.', runtimeType.toString());
      return;
    }
    logger.logInfo('Undoing ReorderTracksCommand to restore original order', runtimeType.toString());

    try {
      final success = await vm.projectDatabaseService.updateTrackOrder(_originalOrder!);
       if (!success) {
         logger.logError('Failed to undo track reorder in DB.', runtimeType.toString());
      }
      // Refreshing is handled by ViewModel listeners on ProjectDatabaseService changes
    } catch (e) {
      logger.logError('Error undoing ReorderTracksCommand: $e', runtimeType.toString());
       rethrow;
    }
  }
}