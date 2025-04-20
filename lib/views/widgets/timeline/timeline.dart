import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_database_service.dart'; // Replace ProjectService import
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math; // Add math import for max function

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatelessWidget with WatchItMixin {
  const Timeline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it to get ViewModels and Services
    final timelineViewModel = di<TimelineViewModel>();
    final databaseService = di<ProjectDatabaseService>(); // Get ProjectDatabaseService

    // Watch properties from TimelineViewModel
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final currentFrame = watchValue(
      (TimelineViewModel vm) => vm.currentFrameNotifier,
    );
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    final trackLabelWidth = watchValue(
      (TimelineViewModel vm) => vm.trackLabelWidthNotifier,
    );

    // Watch tracks list from the DatabaseService
    final tracks = watchValue(
      (ProjectDatabaseService ps) => ps.tracksNotifier,
    );

    // Only horizontal scroll controller needed from ViewModel now
    final trackContentHorizontalScrollController =
        timelineViewModel.trackContentHorizontalScrollController;

    const double timeRulerHeight = 25.0;
    const double trackItemSpacing = 4.0;

    return Container(
      color: theme.resources.cardBackgroundFillColorDefault,
      child: Column(
        children: [
          // Now uses WatchingWidget, no params needed
          const TimelineControls(),

          // Unified Timeline Content Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double framePixelWidth = 5.0;
                final double contentWidth =
                    totalFrames * zoom * framePixelWidth;
                final double totalScrollableWidth = math.max(
                  constraints.maxWidth,
                  contentWidth + trackLabelWidth,
                );
                final double playheadPosition =
                    currentFrame * zoom * framePixelWidth;

                return ClipRect(
                  // Clip horizontal overflow
                  child: Stack(
                    children: [
                      // Horizontally Scrollable Container for Ruler and All Tracks
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: trackContentHorizontalScrollController,
                        child: SizedBox(
                          width:
                              totalScrollableWidth, // Define scrollable width
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // TimeRuler spanning the full scrollable width
                              Padding(
                                padding: EdgeInsets.only(left: trackLabelWidth),
                                child: SizedBox(
                                  height: timeRulerHeight,
                                  width: totalScrollableWidth - trackLabelWidth,
                                  child: TimeRuler(
                                    zoom: zoom,
                                    availableWidth: math.max(
                                      0,
                                      constraints.maxWidth - trackLabelWidth,
                                    ),
                                  ),
                                ),
                              ),
                              // Vertically arranged Tracks (scrolls with the horizontal parent)
                              // Using Expanded + ListView if vertical scrolling is needed within the Column
                              // If not many tracks or vertical scroll isn't desired, a simple Column might suffice.
                              // Using ListView for consistency and potential future needs.
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: trackItemSpacing,
                                  ),
                                  itemCount: tracks.length,
                                  itemBuilder: (context, index) {
                                    if (index >= tracks.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final track = tracks[index];
                                    final trackClips =
                                        clips
                                            .where(
                                              (clip) =>
                                                  clip.trackId == track.id,
                                            )
                                            .toList();

                                    // Use the updated TimelineTrack widget
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: trackItemSpacing,
                                      ),
                                      child: TimelineTrack(
                                        track: track,
                                        clips: trackClips,
                                        onDelete: () {
                                          databaseService.deleteTrack(track.id);
                                        },
                                        trackLabelWidth: trackLabelWidth,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Playhead - Positioned relative to the Stack (which is clipped)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: playheadPosition + trackLabelWidth,
                        width: 2,
                        child: Container(color: theme.accentColor.normal),
                      ),
                      // Splitter - Positioned in the Stack
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left:
                            trackLabelWidth -
                            3, // Position based on label width
                        width: 6,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (DragUpdateDetails details) {
                            // Update width via ViewModel
                            timelineViewModel.updateTrackLabelWidth(
                              trackLabelWidth + details.delta.dx,
                            );
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeLeftRight,
                            child: Container(
                              color: theme.resources.subtleFillColorSecondary,
                              alignment: Alignment.center,
                              child: Container(
                                width: 1.5,
                                color:
                                    theme.resources.controlStrokeColorDefault,
                              ),
                            ),
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
