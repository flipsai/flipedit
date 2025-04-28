import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:watch_it/watch_it.dart'; // For di

// Mixin to handle user interactions like drag/drop, reordering, and resizing
mixin TimelineInteractionLogicMixin on State<Timeline> {

  // --- Expected State/Getters from Main Class ---
  TimelineViewModel get timelineViewModel;
  TimelineNavigationViewModel get timelineNavigationViewModel;
  ScrollController get scrollController;
  double get trackLabelWidth;
  Function(double) get setTrackLabelWidth;
  double get viewportWidth;

  // --- Constants ---
  static const double _timeRulerHeight = 25.0;
  static const double _trackItemSpacing = 4.0;
  static const double _framePixelWidth = 5.0;

  // --- Drag and Drop Handling ---

  bool handleTimelineAreaWillAccept(ClipModel data, List<dynamic> tracks) {
    // Accepts if the timeline track list is empty
    final accept = tracks.isEmpty;
    developer.log(
      'TimelineInteraction: onWillAccept: $accept (tracks: ${tracks.length})',
      name: 'Timeline',
    );
    return accept;
  }

  Future<void> handleTimelineAreaAccept(ClipModel draggedClip, DragTargetDetails<ClipModel> details, BuildContext context) async {
    developer.log(
      'TimelineInteraction: onAccept: Drop accepted (tracks were empty)',
      name: 'Timeline',
    );

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;

    final scrollOffsetX = scrollController.hasClients ? scrollController.offset : 0.0;
    final zoom = timelineNavigationViewModel.zoom;

    // Calculate drop position relative to the scrollable track area
    final Offset dropOffsetInContext = renderBox.globalToLocal(details.offset);
    // Adjust for the TimeRuler if it was present (though it isn't when tracks are empty)
    // final double verticalOffset = dropOffsetInContext.dy - _timeRulerHeight - _trackItemSpacing;
    // Adjust for horizontal position relative to the start of the track content area
    final double horizontalOffset = dropOffsetInContext.dx - trackLabelWidth;

    // Calculate frame position based on the horizontal drop point within the scrollable area
    final double positionInScrollable = horizontalOffset + scrollOffsetX;
    final int calculatedFramePosition =
        (positionInScrollable / (_framePixelWidth * zoom)).floor();
    final int framePosition = math.max(0, calculatedFramePosition);
    final double framePositionMs = framePosition * (1000 / 30); // Assuming 30 FPS

    developer.log(
      '📏 Drop Position (Timeline Area): local=$dropOffsetInContext, scroll=$scrollOffsetX, frame=$framePosition, ms=$framePositionMs',
      name: 'Timeline',
    );

    // Call ViewModel method to handle the drop
    await timelineViewModel.handleClipDropToEmptyTimeline(
      clip: draggedClip,
      startTimeOnTrackMs: framePositionMs.toInt(),
    );

    // Post-drop logic: Select the newly created track and clip (if any)
    // This might require awaiting the VM update or using Future.delayed
    // Consider moving this logic to the ViewModel or using a callback
    Future.delayed(const Duration(milliseconds: 100), () {
       if (!mounted) return; // Check if widget is still mounted
      final updatedTracks = timelineViewModel.tracksNotifierForView.value;
      if (updatedTracks.isNotEmpty) {
        final firstTrack = updatedTracks.first;
        timelineViewModel.selectedTrackId = firstTrack.id;
        developer.log(
          '✅ Selected newly created track ${firstTrack.id}',
          name: 'Timeline',
        );

        // Refresh clips for the new track and select the first one
        timelineViewModel.refreshClips().then((_) {
          if (!mounted) return;
          final clipsOnTrack = timelineViewModel.clips
              .where((c) => c.trackId == firstTrack.id)
              .toList();
          if (clipsOnTrack.isNotEmpty) {
            timelineViewModel.selectedClipId = clipsOnTrack.first.databaseId;
            developer.log(
              '✅ Selected newly created clip ${clipsOnTrack.first.databaseId}',
              name: 'Timeline',
            );
          }
        });
      }
    });

    developer.log(
      '✅ Clip "${draggedClip.name}" added to new track at frame $framePosition',
      name: 'Timeline',
    );
  }

  // --- Track Reordering ---

  Future<void> handleTrackReorder(int oldIndex, int newIndex, int trackCount) async {
    if (oldIndex < 0 || oldIndex >= trackCount || newIndex < 0 || newIndex > trackCount) {
       developer.log(
        'TimelineInteraction: Invalid track reorder indices: $oldIndex -> $newIndex (count: $trackCount)',
        name: 'Timeline',
        level: 1000, // Warning level
      );
      return;
    }

    // Adjust index if moving downwards
    int adjustedNewIndex = newIndex;
    if (oldIndex < newIndex) {
       adjustedNewIndex -= 1;
    }

    developer.log(
      'TimelineInteraction: Track reordering requested: $oldIndex -> $adjustedNewIndex',
      name: 'Timeline',
    );

    if (oldIndex != adjustedNewIndex) {
      try {
        await timelineViewModel.reorderTracks(oldIndex, adjustedNewIndex);
         developer.log(
          'TimelineInteraction: Track reordering successful: $oldIndex -> $adjustedNewIndex',
          name: 'Timeline',
        );
      } catch (e, s) {
        developer.log(
          'TimelineInteraction: Error reordering tracks: $e',
          name: 'Timeline',
          error: e,
          stackTrace: s,
          level: 1200, // Error level
        );
        // Optionally show user feedback
      }
    }
  }

  // --- Track Label Resizing ---

  void handleTrackLabelResize(DragUpdateDetails details) {
     // Calculate new width based on drag delta, constrained between min/max
    final newWidth = (trackLabelWidth + details.delta.dx).clamp(50.0, 400.0);
    // Call the setter provided by the main state to update the value
    setTrackLabelWidth(newWidth);
  }

} 