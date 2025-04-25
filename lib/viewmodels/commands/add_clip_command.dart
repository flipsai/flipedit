import 'package:drift/drift.dart' show Value; // Import the Value class
import 'package:drift/drift.dart' as drift;
import 'package:flipedit/persistence/database/project_database.dart' as project_db;
import 'package:flipedit/utils/logger.dart' as logger;

import '../timeline_viewmodel.dart';
import '../commands/timeline_command.dart';
import '../../models/clip.dart';
import '../../services/timeline_logic_service.dart'; // Import the new service
import 'package:watch_it/watch_it.dart'; // Import for di

/// Command to add a clip to the timeline at a specific position.
/// Handles both the persistence mutation (via DAOs) and state mutation (via ViewModel).
class AddClipCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel clipData;
  final int trackId;
  // Add dependency on TimelineLogicService
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final int startTimeOnTrackMs; // The target start time on the track
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;
  final double? localPositionX;
  final double? scrollOffsetX;
  int? _insertedClipId;

  static const _logTag = "AddClipCommand";

  AddClipCommand({
    required this.vm,
    required this.clipData,
    required this.trackId,
    required this.startTimeOnTrackMs,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    this.localPositionX,
    this.scrollOffsetX,
  });

  @override
  Future<void> execute() async {
    final databaseService = vm.projectDatabaseService;
    if (databaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return;
    }

    // 1. Calculate placement using ViewModel's logic (no database operations)
    final placement = _timelineLogicService.prepareClipPlacement(
      clips: vm.clips, // Pass the current clips from ViewModel
      clipId: null,
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      // Pass the target start time on the track
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
    );

    if (!placement['success']) {
      logger.logError('Failed to calculate clip placement', _logTag);
      return;
    }

    // 2. Handle persistence operations
    
    // 2.1 Apply updates to overlapping clips
    for (final update in placement['clipUpdates']) {
      await databaseService.clipDao!.updateClipFields(
        update['id'],
        update['fields'],
        log: false,
      );
    }
    
    // 2.2 Remove fully overlapped clips
    for (final id in placement['clipsToRemove']) {
      await databaseService.clipDao!.deleteClip(id);
    }
    
    // 2.3 Insert the new clip using the calculated placement
    final newClipData = placement['newClipData'];
    _insertedClipId = await databaseService.clipDao!.insertClip(
      project_db.ClipsCompanion(
        trackId: drift.Value(trackId),
        type: drift.Value(clipData.type.name),
        sourcePath: drift.Value(clipData.sourcePath),
        // Use the calculated start time from placement
        startTimeOnTrackMs: drift.Value(newClipData['startTimeOnTrackMs']),
        startTimeInSourceMs: drift.Value(newClipData['startTimeInSourceMs']),
        endTimeInSourceMs: drift.Value(newClipData['endTimeInSourceMs']),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    
    // 3. Update UI state with the real clip ID
    List<ClipModel> updatedClips = placement['updatedClips'];
    
    // Replace the temporary clip with one having the real database ID
    final tempIndex = updatedClips.indexWhere((c) => c.databaseId == -1);
    if (tempIndex != -1 && _insertedClipId != null) { // Check if _insertedClipId is not null
      // Wrap the ID in a Value object for the copyWith method
      updatedClips[tempIndex] = updatedClips[tempIndex].copyWith(
        databaseId: Value(_insertedClipId),
      );
    } else if (tempIndex != -1) {
       // Handle case where _insertedClipId might be null unexpectedly
       logger.logWarning('Inserted clip ID is null, cannot update temporary clip model.', _logTag);
       // Optionally remove the temporary clip if insertion failed
       updatedClips.removeAt(tempIndex);
    }
    
    // Update the UI through the ViewModel
    vm.updateClipsAfterPlacement(updatedClips);
    
    logger.logInfo('Added new clip with ID $_insertedClipId', _logTag);
  }

  @override
  Future<void> undo() async {
    if (_insertedClipId == null) {
      logger.logWarning('Cannot undo: No clip was inserted', _logTag);
      return;
    }
    
    final databaseService = vm.projectDatabaseService;
    if (databaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return;
    }
    
    // Delete the inserted clip
    await databaseService.clipDao!.deleteClip(_insertedClipId!);
    
    // Refresh clips to update UI
    await vm.refreshClips();
    
    logger.logInfo('Undid clip addition: removed clip $_insertedClipId', _logTag);
  }
}
