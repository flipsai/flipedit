import 'package:flutter/material.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Keep for now
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart'; // Import State VM
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
  late TimelineViewModel _timelineViewModel; // Keep for now
  late TimelineNavigationViewModel _timelineNavigationViewModel;
  late TimelineStateViewModel _timelineStateViewModel; // Add State VM instance

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>(); // Keep for now
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _timelineStateViewModel =
        di<TimelineStateViewModel>(); // Initialize State VM

    // Force a refresh of clips when mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineStateViewModel.refreshClips(); // Use State VM to refresh
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
    final double zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    );
    final clips =
        watchValue(
          (TimelineStateViewModel vm) => vm.clipsNotifier,
        ) // Watch State VM
        .where((clip) => clip.trackId == widget.track.id).toList();
    final selectedTrackId = watchValue(
      (TimelineStateViewModel vm) => vm.selectedTrackIdNotifier,
    ); // Watch State VM
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
