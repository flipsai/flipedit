import 'package:fluent_ui/fluent_ui.dart';
// Removed import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_playhead_logic_mixin.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_scroll_logic_mixin.dart';
import 'package:flipedit/views/widgets/timeline/mixins/timeline_interaction_logic_mixin.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math; // Add math import for max function
import 'package:flipedit/utils/logger.dart'; // Import for logging functions
import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'dart:developer' as developer; // Import for developer logging
import 'package:flipedit/views/widgets/timeline/components/timeline_playhead.dart';
import 'package:flutter/gestures.dart'; // Import for PointerHoverEvent

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatefulWidget with WatchItStatefulWidgetMixin {
  // Mixin moved here
  // Parameters for snapping and aspect ratio lock removed - now handled by EditorViewModel

  const Timeline({super.key});

  @override
  State<Timeline> createState() => _TimelineState();
}

// Apply the mixins here
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
  late TimelineViewModel timelineViewModel;

  @override
  late TimelineNavigationViewModel timelineNavigationViewModel;

  // Store the listener function to remove it in dispose
  VoidCallback? _scrollRequestListener;

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
    timelineViewModel = di<TimelineViewModel>();
    timelineNavigationViewModel = di<TimelineNavigationViewModel>();

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
  }

  @override
  void dispose() {
    if (_scrollRequestListener != null) {
      timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier
          .removeListener(_scrollRequestListener!);
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
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final tracks = watchValue(
      (TimelineViewModel vm) => vm.tracksNotifierForView,
    );

    final zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    );
    final totalFrames = watchValue(
      (TimelineNavigationViewModel vm) => vm.totalFramesNotifier,
    );

    // Use currentFramePosition from TimelinePlayheadLogicMixin
    // It's kept in sync internally by the mixin

    // Debug logging
    if (clips.isNotEmpty) {
      logDebug(
        'Timeline',
        '🧩 Timeline build with ${clips.length} clips, ${tracks.length} tracks, totalFrames: $totalFrames',
      );
    }

    const double timeRulerHeight = 25.0;
    const double trackItemSpacing = 4.0;
    const double framePixelWidth = 5.0; // Consistent constant

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
                  viewportWidth, // Ensure it's at least viewport width
                  contentWidth + trackLabelWidth, // Content + label area
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
                            availableWidth:
                                viewportWidth -
                                trackLabelWidth, // Correct width for ruler content
                          ),
                        ),

                      // Horizontally Scrollable Container
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: scrollController,
                        physics:
                            timelineViewModel.hasContent
                                ? const ClampingScrollPhysics()
                                : const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: totalScrollableWidth,
                          // Temporarily replace AnimatedBuilder with Builder to test initial drag update
                          child: Builder(
                            builder: (context) {
                              final currentScrollOffset = // Calculation now inside Builder
                                  scrollController.hasClients
                                      ? scrollController.offset
                                      : 0.0;
                              return Stack(
                                // Return the Stack
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

                                  // Playhead and Resizer moved outside SingleChildScrollView
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      // --- Track label width resizer handle (MOVED HERE) ---
                      if (tracks.isNotEmpty)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: trackLabelWidth - 3,
                          width: 6,
                          child: GestureDetector(
                            // Use method from TimelineInteractionLogicMixin
                            onHorizontalDragUpdate: handleTrackLabelResize,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: Container(
                                color: theme.resources.subtleFillColorTransparent, // Make handle area transparent
                                alignment: Alignment.center,
                                child: Container(
                                  width: 1.5, // Visible line width
                                  color: theme.resources.controlStrokeColorDefault,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // --- DaVinci Resolve-style Playhead (MOVED HERE) ---
                      if (tracks.isNotEmpty)
                        // Use ValueListenableBuilder to update playhead position directly
                        ValueListenableBuilder<int>(
                          valueListenable: visualFramePositionNotifier, // From mixin
                          builder: (context, visualFrame, _) {
                            // Get current scroll offset safely
                            final currentScrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
                            // Calculate pixel position based on the visual frame from the notifier
                            final double playheadPositionPx = visualFrame * zoom * framePixelWidth;
                            // Calculate final left position, accounting for scroll offset AND centering the hit area
                            final double finalLeft = (trackLabelWidth + playheadPositionPx - currentScrollOffset) - (20.0 / 2);

                            return Positioned(
                              top: 0, // Position relative to the outer Stack
                              bottom: 0,
                              // Position based on the value from the notifier AND scroll offset
                              left: finalLeft,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.allScroll,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  // Use handlers from TimelinePlayheadLogicMixin
                                  onHorizontalDragStart: handlePlayheadDragStart,
                                  onHorizontalDragUpdate: handlePlayheadDragUpdate,
                                  onHorizontalDragEnd: handlePlayheadDragEnd,
                                  onHorizontalDragCancel: handlePlayheadDragCancel,
                                  child: SizedBox(
                                    width: 20, // Hit area width
                                    height: double.infinity, // Span the container height
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        // Playhead graphic itself
                                        Positioned(
                                          left: (20 - 10) / 2, // Center within hit area
                                          top: 0,
                                          bottom: 0,
                                          child: const TimelinePlayhead(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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
