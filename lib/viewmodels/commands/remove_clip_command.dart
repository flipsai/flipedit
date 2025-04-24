import '../timeline_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart' as project_db; // For potential undo
import 'package:drift/drift.dart' as drift; // Added Value import

/// Command to remove a clip from the timeline.
class RemoveClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int clipId;

  ClipModel? _removedClipData; // Store data for undo

  static const _logTag = "RemoveClipCommand";

  RemoveClipCommand({
    required this.vm,
    required this.clipId,
  });

  @override
  Future<void> execute() async {
    logger.logInfo('[RemoveClipCommand] Executing: clipId=$clipId', _logTag);
    if (vm.projectDatabaseService.clipDao == null) {
      logger.logError('[RemoveClipCommand] Clip DAO not initialized', _logTag);
      return; // Or throw an error
    }

    try {
      // Store data for undo *before* deleting
      final clipToRemove = vm.clips.firstWhere(
        (c) => c.databaseId == clipId,
        orElse: () => throw Exception('Clip $clipId not found in ViewModel for undo'),
      );
      _removedClipData = clipToRemove; // Store the full model

      await vm.projectDatabaseService.clipDao!.deleteClip(clipId);

      // --- Manually update clipsNotifier ---
      // This logic remains here as it directly affects the ViewModel's state
      // which the command is operating on.
      final currentClips = List<ClipModel>.from(vm.clipsNotifier.value);
      final indexToRemove = currentClips.indexWhere(
        (clip) => clip.databaseId == clipId,
      );

      if (indexToRemove != -1) {
        currentClips.removeAt(indexToRemove);
        vm.clipsNotifier.value = currentClips; // Notify listeners
        vm.recalculateAndUpdateTotalFrames(); // Call public method
        logger.logInfo('[RemoveClipCommand] Removed clip $clipId and updated notifier', _logTag);
      } else {
        logger.logWarning(
          '[RemoveClipCommand] Clip ID $clipId deleted from DB but not found in clipsNotifier',
          _logTag,
        );
        // Fallback: Refresh might be needed if the notifier was out of sync
        // await vm.refreshClips();
      }
      // --- End manual update ---

      logger.logInfo('[RemoveClipCommand] Successfully removed clip $clipId', _logTag);
    } catch (e) {
      logger.logError('[RemoveClipCommand] Error removing clip $clipId: $e', _logTag);
      // Rethrow or handle as appropriate for the application's error strategy
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo('[RemoveClipCommand] Undoing removal of clipId=$clipId', _logTag);
    if (_removedClipData == null) {
      logger.logError('[RemoveClipCommand] Cannot undo: Removed clip data not found', _logTag);
      return;
    }
    if (vm.projectDatabaseService.clipDao == null) {
      logger.logError('[RemoveClipCommand] Clip DAO not initialized for undo', _logTag);
      return;
    }

    try {
      // Re-insert the clip using the stored data
      final clipToRestore = _removedClipData!;
      await vm.projectDatabaseService.clipDao!.insertClip(
        // Use the default constructor and wrap all fields in Value()
        // as seen in the original TimelineViewModel insert logic.
        project_db.ClipsCompanion(
          id: drift.Value(clipToRestore.databaseId!), // Use original ID
          trackId: drift.Value(clipToRestore.trackId),
          type: drift.Value(clipToRestore.type.name),
          sourcePath: drift.Value(clipToRestore.sourcePath),
          startTimeOnTrackMs: drift.Value(clipToRestore.startTimeOnTrackMs),
          startTimeInSourceMs: drift.Value(clipToRestore.startTimeInSourceMs),
          endTimeInSourceMs: drift.Value(clipToRestore.endTimeInSourceMs),
          createdAt: drift.Value(DateTime.now()), // Or original if stored
          updatedAt: drift.Value(DateTime.now()),
          // Add other fields like name, effects, metadata if they were stored
        ),
      );

      // Optimistically update the notifier or rely on refresh/stream
      // Adding back optimistically:
      final currentClips = List<ClipModel>.from(vm.clipsNotifier.value);
      currentClips.add(clipToRestore);
      currentClips.sort((a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs));
      vm.clipsNotifier.value = currentClips;
      vm.recalculateAndUpdateTotalFrames(); // Call public method

      logger.logInfo('[RemoveClipCommand] Successfully restored clip $clipId', _logTag);
      _removedClipData = null; // Clear data after successful undo
    } catch (e) {
      logger.logError('[RemoveClipCommand] Error undoing removal of clip $clipId: $e', _logTag);
      rethrow;
    }
  }
}
