import '../timeline_viewmodel.dart';
import '../timeline_state_viewmodel.dart';
import '../commands/timeline_command.dart';
import '../../models/clip.dart';
import '../../services/timeline_logic_service.dart';
import '../../services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';

class TrimOverlapCommand implements TimelineCommand {
  final TimelineViewModel vm;
  final ClipModel newClip;
  late List<ClipModel> _beforeNeighbors;

  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  final TimelineStateViewModel _stateViewModel = di<TimelineStateViewModel>();
  final ProjectDatabaseService _databaseService = di<ProjectDatabaseService>();

  TrimOverlapCommand(this.vm, this.newClip);

  void setBeforeNeighbors(List<ClipModel> neighbors) {
    _beforeNeighbors = neighbors;
  }

  @override
  Future<void> execute() async {
    _beforeNeighbors =
        _timelineLogicService
            .getOverlappingClips(
              _stateViewModel.clips,
              newClip.trackId,
              newClip.startTimeOnTrackMs,
              newClip.endTimeOnTrackMs,
            )
            .map((c) => c.copyWith())
            .toList();
    await vm.placeClipOnTrack(
      clipId: newClip.databaseId,
      trackId: newClip.trackId,
      type: newClip.type,
      sourcePath: newClip.sourcePath,
      sourceDurationMs: newClip.sourceDurationMs,
      startTimeOnTrackMs: newClip.startTimeOnTrackMs,
      endTimeOnTrackMs: newClip.endTimeOnTrackMs,
      startTimeInSourceMs: newClip.startTimeInSourceMs,
      endTimeInSourceMs: newClip.endTimeInSourceMs,
    );
    await _stateViewModel.refreshClips();
  }

  @override
  Future<void> undo() async {
    for (final clip in _beforeNeighbors) {
      if (_databaseService.clipDao == null) continue;
      await _databaseService.clipDao!.updateClipFields(clip.databaseId!, {
        'startTimeInSourceMs': clip.startTimeInSourceMs,
        'endTimeInSourceMs': clip.endTimeInSourceMs,
        'startTimeOnTrackMs': clip.startTimeOnTrackMs,
      });
    }
    await _stateViewModel.refreshClips();
  }
}
