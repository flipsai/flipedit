import 'package:watch_it/watch_it.dart';
import '../timeline_viewmodel.dart';
import '../timeline_state_viewmodel.dart'; // Added for di<TimelineStateViewModel>()
import '../timeline_navigation_viewmodel.dart';
import 'timeline_command.dart';
import '../../models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import 'package:drift/drift.dart' as drift;

class RemoveClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final int clipId;

  ClipModel? _removedClipData;

  static const _logTag = "RemoveClipCommand";

  RemoveClipCommand({required this.vm, required this.clipId});

  @override
  Future<void> execute() async {
    logger.logInfo('[RemoveClipCommand] Executing: clipId=$clipId', _logTag);
    if (vm.projectDatabaseService.clipDao == null) {
      logger.logError('[RemoveClipCommand] Clip DAO not initialized', _logTag);
      return;
    }

    try {
      final clipToRemove = vm.clips.firstWhere(
        (c) => c.databaseId == clipId,
        orElse:
            () =>
                throw Exception('Clip $clipId not found in ViewModel for undo'),
      );
      _removedClipData = clipToRemove;

      await vm.projectDatabaseService.clipDao!.deleteClip(clipId);

      final currentClips = List<ClipModel>.from(vm.clipsNotifier.value);
      final indexToRemove = currentClips.indexWhere(
        (clip) => clip.databaseId == clipId,
      );

      if (indexToRemove != -1) {
        currentClips.removeAt(indexToRemove);
        // vm.clipsNotifier.value = currentClips; // Old way
        // vm.clipsNotifier.value = currentClips; // Original old way
        di<TimelineStateViewModel>().setClips(currentClips); // Corrected new way
        di<TimelineNavigationViewModel>().navigationService
            .recalculateAndUpdateTotalFrames();
        logger.logInfo(
          '[RemoveClipCommand] Removed clip $clipId and updated notifier',
          _logTag,
        );
      } else {
        logger.logWarning(
          '[RemoveClipCommand] Clip ID $clipId deleted from DB but not found in clipsNotifier',
          _logTag,
        );
      }

      logger.logInfo(
        '[RemoveClipCommand] Successfully removed clip $clipId',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        '[RemoveClipCommand] Error removing clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }

  @override
  Future<void> undo() async {
    logger.logInfo(
      '[RemoveClipCommand] Undoing removal of clipId=$clipId',
      _logTag,
    );
    if (_removedClipData == null) {
      logger.logError(
        '[RemoveClipCommand] Cannot undo: Removed clip data not found',
        _logTag,
      );
      return;
    }
    if (vm.projectDatabaseService.clipDao == null) {
      logger.logError(
        '[RemoveClipCommand] Clip DAO not initialized for undo',
        _logTag,
      );
      return;
    }

    try {
      final clipToRestore = _removedClipData!;
      await vm.projectDatabaseService.clipDao!.insertClip(
        project_db.ClipsCompanion(
          id: drift.Value(clipToRestore.databaseId!),
          trackId: drift.Value(clipToRestore.trackId),
          type: drift.Value(clipToRestore.type.name),
          sourcePath: drift.Value(clipToRestore.sourcePath),
          startTimeOnTrackMs: drift.Value(clipToRestore.startTimeOnTrackMs),
          startTimeInSourceMs: drift.Value(clipToRestore.startTimeInSourceMs),
          endTimeInSourceMs: drift.Value(clipToRestore.endTimeInSourceMs),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final currentClips = List<ClipModel>.from(vm.clipsNotifier.value);
      currentClips.add(clipToRestore);
      currentClips.sort(
        (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
      );
      // vm.clipsNotifier.value = currentClips; // Old way
      // vm.clipsNotifier.value = currentClips; // Original old way
      di<TimelineStateViewModel>().setClips(currentClips); // Corrected new way
      di<TimelineNavigationViewModel>().navigationService
          .recalculateAndUpdateTotalFrames();

      logger.logInfo(
        '[RemoveClipCommand] Successfully restored clip $clipId',
        _logTag,
      );
      _removedClipData = null;
    } catch (e) {
      logger.logError(
        '[RemoveClipCommand] Error undoing removal of clip $clipId: $e',
        _logTag,
      );
      rethrow;
    }
  }
}
