import '../timeline_viewmodel.dart';
import '../commands/timeline_command.dart';
import '../../models/clip.dart';

class TrimOverlapCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel newClip;
  late List<ClipModel> _beforeNeighbors;

  TrimOverlapCommand(this.vm, this.newClip);

  // For testing: allow setting _beforeNeighbors
  void setBeforeNeighbors(List<ClipModel> neighbors) {
    _beforeNeighbors = neighbors;
  }

  @override
  Future<void> execute() async {
    // Save current state of overlapping neighbors for undo
    _beforeNeighbors = vm.getOverlappingClips(
      newClip.trackId,
      newClip.startTimeOnTrackMs,
      newClip.startTimeOnTrackMs + newClip.durationMs,
    ).map((c) => c.copyWith()).toList();
    // Apply trim logic (reuse placeClipOnTrack logic)
    await vm.placeClipOnTrack(
      clipId: newClip.databaseId,
      trackId: newClip.trackId,
      type: newClip.type,
      sourcePath: newClip.sourcePath,
      startTimeOnTrackMs: newClip.startTimeOnTrackMs,
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
