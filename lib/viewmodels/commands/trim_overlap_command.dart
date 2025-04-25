import '../timeline_viewmodel.dart';
import '../commands/timeline_command.dart';
import '../../models/clip.dart';
import '../../services/timeline_logic_service.dart'; // Import the new service
import 'package:watch_it/watch_it.dart'; // Import for di

class TrimOverlapCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel newClip;
  late List<ClipModel> _beforeNeighbors;

  // Add dependency on TimelineLogicService
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();

  TrimOverlapCommand(this.vm, this.newClip);

  // For testing: allow setting _beforeNeighbors
  void setBeforeNeighbors(List<ClipModel> neighbors) {
    _beforeNeighbors = neighbors;
  }

  @override
  Future<void> execute() async {
    // Save current state of overlapping neighbors for undo
    _beforeNeighbors = _timelineLogicService.getOverlappingClips( // Use the new service
      vm.clips,
      newClip.trackId,
      newClip.startTimeOnTrackMs,
      newClip.endTimeOnTrackMs, // Use explicit end time on track
    ).map((c) => c.copyWith()).toList();
    // Apply trim logic (reuse placeClipOnTrack logic)
    // This call will now use the correct parameters to resolve overlaps
    await vm.placeClipOnTrack(
      clipId: newClip.databaseId,
      trackId: newClip.trackId,
      type: newClip.type,
      sourcePath: newClip.sourcePath,
      sourceDurationMs: newClip.sourceDurationMs, // Pass source duration
      startTimeOnTrackMs: newClip.startTimeOnTrackMs,
      endTimeOnTrackMs: newClip.endTimeOnTrackMs, // Pass end time on track
      startTimeInSourceMs: newClip.startTimeInSourceMs,
      endTimeInSourceMs: newClip.endTimeInSourceMs,
    );
    await vm.refreshClips();
  }

  @override
  Future<void> undo() async {
    // Restore each neighbor to its previous state
    for (final clip in _beforeNeighbors) {
      await vm.projectDatabaseService.clipDao!.updateClipFields(
        clip.databaseId!,
        {
          'startTimeInSourceMs': clip.startTimeInSourceMs,
          'endTimeInSourceMs': clip.endTimeInSourceMs,
          'startTimeOnTrackMs': clip.startTimeOnTrackMs,
        },
      );
    }
    // Optionally remove the new clip if it was added
    // (You may want to add logic to track if this was a new insert)
    await vm.refreshClips();
  }
}
