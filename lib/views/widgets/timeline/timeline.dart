import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Keep for now (actions)
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart'; // Import State VM
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_playhead_logic_mixin.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_scroll_logic_mixin.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_interaction_logic_mixin.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_playhead.dart';

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
        TimelinePlayheadLogicMixin,
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
  
  // Add a listener for ensuring playhead follows video position
  VoidCallback? _currentFrameListener;

  @override
  double trackLabelWidth = 120.0;

  // Animation controllers are still managed here as they require TickerProvider
  @override
  late AnimationController playheadPhysicsController;

  @override
  late AnimationController scrubSnapController;

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
    _timelineStateViewModel = di<TimelineStateViewModel>(); // Initialize State VM instance
 
     // Setup physics controllers (needed by TimelinePlayheadLogicMixin)
    playheadPhysicsController = AnimationController(
      vsync: this, // Provided by TickerProviderStateMixin
      duration: const Duration(milliseconds: 800),
    );
    scrubSnapController = AnimationController(
      vsync: this, // Provided by TickerProviderStateMixin
      duration: const Duration(milliseconds: 150),
    );

    // Initialize logic from the playhead mixin
    initializePlayheadLogic(ensurePlayheadVisible: ensurePlayheadVisible);

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
        
    // Add listener to keep the visualFramePositionNotifier in sync with currentFrameNotifier
    _currentFrameListener = () {
      final currentFrame = timelineNavigationViewModel.currentFrameNotifier.value;
      // Update the visual frame position if it's different
      if (visualFramePositionNotifier.value != currentFrame) {
        visualFramePositionNotifier.value = currentFrame;
      }
    };
    timelineNavigationViewModel.currentFrameNotifier.addListener(_currentFrameListener!);
  }

  @override
  void dispose() {
    if (_scrollRequestListener != null) {
      timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier
          .removeListener(_scrollRequestListener!);
    }

    if (_currentFrameListener != null) {
      timelineNavigationViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    }

    disposePlayheadLogic();

    // Dispose animation controllers (managed here)
    playheadPhysicsController.dispose();
    scrubSnapController.dispose();

    // Dispose scroll controller (managed here)
    scrollController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Watch properties from ViewModels
    final clips = watchValue((TimelineStateViewModel vm) => vm.clipsNotifier); // Watch State VM
    final tracks = watchValue(
      (TimelineStateViewModel vm) => vm.tracksNotifierForView, // Watch State VM
    );

    final zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    );
    final totalFrames = watchValue(
      (TimelineNavigationViewModel vm) => vm.totalFramesNotifier,
    );

    // Debug logging
    if (clips.isNotEmpty) {
      logDebug(
        'Timeline',
        '🧩 Timeline build with ${clips.length} clips, ${tracks.length} tracks, totalFrames: $totalFrames',
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
                // Use instance variable viewportWidth
                viewportWidth = constraints.maxWidth;
                final double contentWidth =
                    totalFrames * zoom * framePixelWidth;
                final double totalScrollableWidth = math.max(
                  viewportWidth,
                  contentWidth + trackLabelWidth,
                );

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

                      // Horizontally Scrollable Container
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: scrollController,
                        physics:
                            _timelineStateViewModel.hasContent // Use State VM instance
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: totalScrollableWidth,
                          // Temporarily replace AnimatedBuilder with Builder to test initial drag update
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
                                            // Width should be the scrollable content width
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
                                          // Use method from TimelineInteractionLogicMixin
                                          onWillAcceptWithDetails:
                                              (details) =>
                                                  handleTimelineAreaWillAccept(
                                                    details.data,
                                                    tracks,
                                                  ),
                                          // Use method from TimelineInteractionLogicMixin
                                          onAcceptWithDetails:
                                              (details) async =>
                                                  handleTimelineAreaAccept(
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
                                              // Use method from TimelineInteractionLogicMixin
                                              onReorder:
                                                  (oldIndex, newIndex) =>
                                                      handleTrackReorder(
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
                                  if (tracks.isNotEmpty)
                                    ValueListenableBuilder<int>(
                                      valueListenable:
                                          visualFramePositionNotifier,
                                      builder: (context, visualFrame, _) {
                                        final double playheadPositionPx =
                                            visualFrame *
                                            zoom *
                                            framePixelWidth;
                                        const double hitAreaWidth = 20.0;
                                        final double finalLeft =
                                            (trackLabelWidth +
                                                playheadPositionPx) -
                                            (hitAreaWidth / 2);

                                        return Positioned(
                                          top: 0,
                                          bottom: 0,
                                          left: finalLeft,
                                          child: MouseRegion(
                                            cursor:
                                                SystemMouseCursors.allScroll,
                                            child: GestureDetector(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onHorizontalDragStart:
                                                  handlePlayheadDragStart,
                                              onHorizontalDragUpdate:
                                                  handlePlayheadDragUpdate,
                                              onHorizontalDragEnd:
                                                  handlePlayheadDragEnd,
                                              onHorizontalDragCancel:
                                                  handlePlayheadDragCancel,
                                              child: SizedBox(
                                                width: hitAreaWidth,
                                                height: double.infinity,
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    Positioned(
                                                      left:
                                                          (hitAreaWidth - 10) /
                                                          2,
                                                      top: 0,
                                                      bottom: 0,
                                                      child:
                                                          const TimelinePlayhead(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  if (tracks.isNotEmpty)
                                    Positioned(
                                      top: 0,
                                      bottom: 0,
                                      left: trackLabelWidth - 3,
                                      width: 6,
                                      child: GestureDetector(
                                        onHorizontalDragUpdate:
                                            handleTrackLabelResize,
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
