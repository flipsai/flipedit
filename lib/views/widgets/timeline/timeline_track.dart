import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'components/track_label_widget.dart';
import 'components/track_content_widget.dart';

class TimelineTrack extends StatefulWidget with WatchItStatefulWidgetMixin {
  final Track track;
  final VoidCallback onDelete;
  final double trackLabelWidth;
  final double scrollOffset;

  const TimelineTrack({
    super.key,
    required this.track,
    required this.onDelete,
    required this.trackLabelWidth,
    required this.scrollOffset,
  });

  @override
  State<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends State<TimelineTrack> {
  late TimelineViewModel _timelineViewModel;
  late TimelineNavigationViewModel _timelineNavigationViewModel;

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();

    // Force a refresh of clips when mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineViewModel.refreshClips();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleTrackSelection() {
    _timelineViewModel.selectedTrackId = widget.track.id;
  }

  void _handleTrackRename(String newName) {
    _timelineViewModel.updateTrackName(widget.track.id, newName);
  }

  @override
  Widget build(BuildContext context) {
    final double zoom = watchValue((TimelineNavigationViewModel vm) => vm.zoomNotifier);
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier)
        .where((clip) => clip.trackId == widget.track.id)
        .toList();
    final selectedTrackId = watchValue((TimelineViewModel vm) => vm.selectedTrackIdNotifier);
    final isSelected = selectedTrackId == widget.track.id;

    const trackHeight = 65.0;

    return GestureDetector(
      onTap: _handleTrackSelection,
      child: SizedBox(
        height: trackHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TrackLabelWidget(
              track: widget.track,
              isSelected: isSelected,
              width: widget.trackLabelWidth,
              onDelete: widget.onDelete,
              onRename: _handleTrackRename,
              onSelect: _handleTrackSelection,
            ),
            TrackContentWidget(
              trackId: widget.track.id,
              isSelected: isSelected,
              zoom: zoom,
              scrollOffset: widget.scrollOffset,
              clips: clips,
              timelineViewModel: _timelineViewModel,
              timelineNavigationViewModel: _timelineNavigationViewModel,
            ),
          ],
        ),
      ),
    );
  }
}
