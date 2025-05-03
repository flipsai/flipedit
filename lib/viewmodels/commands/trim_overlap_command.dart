import '../timeline_viewmodel.dart'; // Keep for vm reference? Review if needed.
import '../timeline_state_viewmodel.dart'; // Import State VM
import '../commands/timeline_command.dart';
import '../../models/clip.dart';
import '../../services/timeline_logic_service.dart'; // Import the logic service
import '../../services/project_database_service.dart'; // Import the database service
import 'package:watch_it/watch_it.dart'; // Import for di

class TrimOverlapCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel newClip;
  late List<ClipModel> _beforeNeighbors;

  // Dependencies
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>(); // Get State VM
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>(); // Get DB Service

  TrimOverlapCommand(this.vm, this.newClip); // Keep vm for now, might be needed for placeClipOnTrack

  // For testing: allow setting _beforeNeighbors
  void setBeforeNeighbors(List<ClipModel> neighbors) {
    _beforeNeighbors = neighbors;
  }

  @override
  Future<void> execute() async {
    // Save current state of overlapping neighbors for undo
    // Get clips from State VM
    _beforeNeighbors = _timelineLogicService.getOverlappingClips(
      _stateViewModel.clips,
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
    // await vm.refreshClips(); // REPLACED
    await _stateViewModel.refreshClips(); // Refresh State VM
  }

  @override
  Future<void> undo() async {
    // Restore each neighbor to its previous state using injected DB service
    for (final clip in _beforeNeighbors) {
      if (_databaseService.clipDao == null) continue; // Add null check
      await _databaseService.clipDao!.updateClipFields(
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
    // await vm.refreshClips(); // REPLACED
    await _stateViewModel.refreshClips(); // Refresh State VM
  }
}
