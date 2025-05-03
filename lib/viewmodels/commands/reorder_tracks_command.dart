import 'package:flipedit/persistence/database/project_database.dart' show Track;
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/utils/logger.dart' as logger;

class ReorderTracksCommand extends TimelineCommand {
  final TimelineViewModel vm;
  final List<Track> originalTracks;
  final int oldIndex;
  final int newIndex;
  List<Track>? _originalOrderForUndo;

  ReorderTracksCommand({
    required this.vm,
    required this.originalTracks,
    required this.oldIndex,
    required this.newIndex,
  });

  @override
  Future<void> execute() async {
    logger.logInfo(
      'Executing ReorderTracksCommand: $oldIndex -> $newIndex',
      runtimeType.toString(),
    );
    final currentTracks = List<Track>.from(originalTracks);

    if (oldIndex < 0 ||
        oldIndex >= currentTracks.length ||
        newIndex < 0 ||
        newIndex >= currentTracks.length ||
        oldIndex == newIndex) {
      logger.logWarning(
        'Invalid indices for ReorderTracksCommand based on original list. Aborting. Indices: $oldIndex -> $newIndex, Count: ${currentTracks.length}',
        runtimeType.toString(),
      );
      return;
    }

    _originalOrderForUndo = List<Track>.from(currentTracks);

    final reorderedTracks = List<Track>.from(currentTracks);
    final trackToMove = reorderedTracks.removeAt(oldIndex);
    reorderedTracks.insert(newIndex, trackToMove);

    try {
      final success = await vm.projectDatabaseService.updateTrackOrder(
        reorderedTracks,
      );
      if (!success) {
        logger.logError(
          'Failed to update track order in DB.',
          runtimeType.toString(),
        );
        _originalOrderForUndo = null;
      }
    } catch (e) {
      logger.logError(
        'Error executing ReorderTracksCommand: $e',
        runtimeType.toString(),
      );
      _originalOrderForUndo = null;
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    if (_originalOrderForUndo == null) {
      logger.logWarning(
        'Cannot undo ReorderTracksCommand: original order not available.',
        runtimeType.toString(),
      );
      return;
    }
    logger.logInfo(
      'Undoing ReorderTracksCommand to restore original order',
      runtimeType.toString(),
    );

    try {
      final success = await vm.projectDatabaseService.updateTrackOrder(
        _originalOrderForUndo!,
      );
      if (!success) {
        logger.logError(
          'Failed to undo track reorder in DB.',
          runtimeType.toString(),
        );
      }
    } catch (e) {
      logger.logError(
        'Error undoing ReorderTracksCommand: $e',
        runtimeType.toString(),
      );
      rethrow;
    }
  }
}
