import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Keep for now (actions)
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart'; // Import State VM
import 'package:flipedit/services/video_player_service.dart'; // Add VideoPlayerService import
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/components/lightweight_playhead_overlay.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_scroll_logic_mixin.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_interaction_logic_mixin.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';

/// Main timeline widget that shows clips and tracks
class Timeline extends StatefulWidget with WatchItStatefulWidgetMixin {
  const Timeline({super.key});

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline>
    with
        TickerProviderStateMixin,
        TimelineScrollLogicMixin,
        TimelineInteractionLogicMixin {
  @override
  double viewportWidth = 0;

  @override
  final ScrollController scrollController = ScrollController();

  @override
  late TimelineViewModel timelineViewModel; // Keep for now (actions)

  @override
  late TimelineNavigationViewModel timelineNavigationViewModel;

  // Add State ViewModel instance
  late TimelineStateViewModel _timelineStateViewModel;

  // Implement getter required by TimelineInteractionLogicMixin
  @override
  TimelineStateViewModel get timelineStateViewModel => _timelineStateViewModel;

  // Store the listener function to remove it in dispose
  VoidCallback? _scrollRequestListener;

  @override
  double trackLabelWidth = 120.0;

  @override
  Function(double) get setTrackLabelWidth => (newWidth) {
    if (trackLabelWidth != newWidth) {
      setState(() {
        trackLabelWidth = newWidth;
      });
    }
  };

  @override
  void initState() {
    super.initState();
    timelineViewModel = di<TimelineViewModel>(); // Keep for now
    timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _timelineStateViewModel =
        di<TimelineStateViewModel>(); // Initialize State VM instance

    // Define the listener callback function using the navigation view model
    _scrollRequestListener = () {
      final frame =
          timelineNavigationViewModel
              .navigationService
              .scrollToFrameRequestNotifier
              .value;
      if (frame == null) return;
      // Call method from TimelineScrollLogicMixin
      handleScrollRequest(frame);
    };

    timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier
        .addListener(_scrollRequestListener!);
  }

  @override
  void dispose() {
    if (_scrollRequestListener != null) {
      timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier
          .removeListener(_scrollRequestListener!);
    }

    // Dispose scroll controller (managed here)
    scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Update viewportWidth when constraints change
        viewportWidth = constraints.maxWidth;
        
        return _TimelineContent(
          timelineStateViewModel: _timelineStateViewModel,
          timelineNavigationViewModel: timelineNavigationViewModel,
          timelineViewModel: timelineViewModel,
          viewportWidth: viewportWidth,
          trackLabelWidth: trackLabelWidth,
          scrollController: scrollController,
          onTrackLabelResize: handleTrackLabelResize,
          onTimelineAreaWillAccept: handleTimelineAreaWillAccept,
          onTimelineAreaAccept: handleTimelineAreaAccept,
          onTrackReorder: handleTrackReorder,
        );
      },
    );
  }
}

class _TimelineContent extends StatelessWidget with WatchItMixin {
  final TimelineStateViewModel timelineStateViewModel;
  final TimelineNavigationViewModel timelineNavigationViewModel;
  final TimelineViewModel timelineViewModel;
  final double viewportWidth;
  final double trackLabelWidth;
  final ScrollController scrollController;
  final void Function(DragUpdateDetails) onTrackLabelResize;
  final bool Function(ClipModel, List<dynamic>) onTimelineAreaWillAccept;
  final Future<void> Function(ClipModel, DragTargetDetails<ClipModel>, BuildContext) onTimelineAreaAccept;
  final void Function(int, int, int) onTrackReorder;

  const _TimelineContent({
    required this.timelineStateViewModel,
    required this.timelineNavigationViewModel,
    required this.timelineViewModel,
    required this.viewportWidth,
    required this.trackLabelWidth,
    required this.scrollController,
    required this.onTrackLabelResize,
    required this.onTimelineAreaWillAccept,
    required this.onTimelineAreaAccept,
    required this.onTrackReorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Watch properties from ViewModels
    final clips = watchValue(
      (TimelineStateViewModel vm) => vm.clipsNotifier,
    );
    final tracks = watchValue(
      (TimelineStateViewModel vm) => vm.tracksNotifierForView,
    );

    final zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    );
    final timelineEnd = watchValue(
      (TimelineNavigationViewModel vm) => vm.timelineEndNotifier,
    );

    // Watch VideoPlayerService to determine if a video is loaded
    final hasActiveVideo = watchValue(
      (VideoPlayerService service) => service.hasActiveVideoNotifier,
    );

    // Debug logging
    if (clips.isNotEmpty) {
      logDebug(
        'Timeline',
        '🧩 Timeline build with ${clips.length} clips, ${tracks.length} tracks, timelineEnd: $timelineEnd',
      );
    }

    const double timeRulerHeight = 25.0;
    const double trackItemSpacing = 4.0;
    const double framePixelWidth = 5.0;

    return Container(
      color: theme.resources.cardBackgroundFillColorDefault,
      child: Column(
        children: [
          TimelineControls(),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double contentWidth = timelineEnd * zoom * framePixelWidth;
                final double totalScrollableWidth = math.max(
                  viewportWidth,
                  contentWidth + trackLabelWidth,
                );
                final double availableHeight = constraints.maxHeight;

                return ClipRect(
                  child: Stack(
                    children: [
                      // Show TimeRuler at the top when no tracks exist
                      if (tracks.isEmpty)
                        SizedBox(
                          height: timeRulerHeight,
                          width: viewportWidth,
                          child: TimeRuler(
                            zoom: zoom,
                            availableWidth: viewportWidth - trackLabelWidth,
                          ),
                        ),

                      // Horizontally Scrollable Container (Isolated from playhead updates)
                      RepaintBoundary(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: scrollController,
                          physics: timelineStateViewModel.hasContent
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: totalScrollableWidth,
                            child: Builder(
                              builder: (context) {
                                final currentScrollOffset =
                                    scrollController.hasClients
                                        ? scrollController.offset
                                        : 0.0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Column containing TimeRuler and Tracks List
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // TimeRuler
                                        if (tracks.isNotEmpty)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              left: trackLabelWidth,
                                            ),
                                            child: SizedBox(
                                              height: timeRulerHeight,
                                              width:
                                                  totalScrollableWidth -
                                                  trackLabelWidth,
                                              child: TimeRuler(
                                                zoom: zoom,
                                                availableWidth:
                                                    totalScrollableWidth -
                                                    trackLabelWidth,
                                              ),
                                            ),
                                          ),

                                        // Track List Area with DragTarget for empty timeline
                                        Expanded(
                                          child: DragTarget<ClipModel>(
                                            onWillAcceptWithDetails:
                                                (details) =>
                                                    onTimelineAreaWillAccept(
                                                      details.data,
                                                      tracks,
                                                    ),
                                            onAcceptWithDetails:
                                                (details) async =>
                                                    onTimelineAreaAccept(
                                                      details.data,
                                                      details,
                                                      context,
                                                    ),
                                            builder: (
                                              context,
                                              candidateData,
                                              rejectedData,
                                            ) {
                                              // Empty state message
                                              if (tracks.isEmpty &&
                                                  candidateData.isEmpty) {
                                                return Center(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(
                                                        FluentIcons.error,
                                                        size: 24,
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'No tracks in project',
                                                        style:
                                                            theme
                                                                .typography
                                                                .bodyLarge,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Drag media here to create a track',
                                                        style: theme
                                                            .typography
                                                            .body
                                                            ?.copyWith(
                                                              color:
                                                                  theme
                                                                      .resources
                                                                      .textFillColorSecondary,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }

                                              // Tracks list
                                              return ReorderableListView.builder(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: trackItemSpacing,
                                                    ),
                                                onReorder:
                                                    (oldIndex, newIndex) =>
                                                        onTrackReorder(
                                                          oldIndex,
                                                          newIndex,
                                                          tracks.length,
                                                        ),
                                                buildDefaultDragHandles: false,
                                                itemCount: tracks.length,
                                                itemBuilder: (context, index) {
                                                  final track = tracks[index];
                                                  return Padding(
                                                    key: ValueKey(
                                                      'track_${track.id}',
                                                    ),
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom:
                                                              trackItemSpacing,
                                                        ),
                                                    child: TimelineTrack(
                                                      key: ValueKey(
                                                        'timeline_track_${track.id}',
                                                      ),
                                                      track: track,
                                                      onDelete:
                                                          () => timelineViewModel
                                                              .deleteTrack(
                                                                track.id,
                                                              ),
                                                      trackLabelWidth:
                                                          trackLabelWidth,
                                                      scrollOffset:
                                                          currentScrollOffset,
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Track Label Resize Handle
                                    if (tracks.isNotEmpty)
                                      Positioned(
                                        top: 0,
                                        bottom: 0,
                                        left: trackLabelWidth - 3,
                                        width: 6,
                                        child: GestureDetector(
                                          onHorizontalDragUpdate: onTrackLabelResize,
                                          child: MouseRegion(
                                            cursor:
                                                SystemMouseCursors
                                                    .resizeLeftRight,
                                            child: Container(
                                              color:
                                                  theme
                                                      .resources
                                                      .subtleFillColorTransparent,
                                              alignment: Alignment.center,
                                              child: Container(
                                                width: 1.5,
                                                color:
                                                    theme
                                                        .resources
                                                        .controlStrokeColorDefault,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),

                      // Lightweight Playhead Overlay (Separate Rendering Layer)
                      if (hasActiveVideo)
                        LightweightPlayheadOverlay(
                          key: const ValueKey('timeline_playhead'),
                          zoom: zoom,
                          trackLabelWidth: trackLabelWidth,
                          timelineHeight: availableHeight,
                          scrollController: scrollController,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
