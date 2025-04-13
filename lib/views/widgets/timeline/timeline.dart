import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_service.dart'; // Import ProjectService
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/track_label.dart';
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
    final projectService = di<ProjectService>(); // Get ProjectService

    // Watch properties from TimelineViewModel
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final currentFrame = watchValue((TimelineViewModel vm) => vm.currentFrameNotifier);
    final isPlaying = watchValue((TimelineViewModel vm) => vm.isPlayingNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue((TimelineViewModel vm) => vm.totalFramesNotifier);
    final trackLabelWidth = watchValue((TimelineViewModel vm) => vm.trackLabelWidthNotifier); // Watch the new notifier

    // Watch tracks list directly from the ProjectService notifier
    final tracks = watchValue((ProjectService ps) => ps.currentProjectTracksNotifier);

    // Scroll controllers
    final trackLabelScrollController = timelineViewModel.trackLabelScrollController;
    final trackContentScrollController = timelineViewModel.trackContentScrollController;

    return Container(
      // Use a standard dark background from the theme resources
      color: theme.resources.cardBackgroundFillColorDefault,
      // Use theme subtle border color
      // border: Border(top: BorderSide(color: theme.resources.controlStrokeColorDefault)),
      child: Column(
        children: [
          // Now uses WatchingWidget, no params needed
          const TimelineControls(),

          // Timeline content
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
              children: [
                // Track labels - Resizable width
                SizedBox(
                  width: trackLabelWidth, // Use watched width
                  child: ListView.builder(
                    controller: trackLabelScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tracks.length + 1, // Use watched tracks.length
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const SizedBox(height: 25); // Space for TimeRuler
                      }
                      final track = tracks[index - 1]; // Use watched tracks list
                      // Use the TrackLabel directly, passing the onDelete callback
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                        child: TrackLabel(
                          track: track, // Pass the whole track object
                          onDelete: () {
                            projectService.removeTrack(track.id);
                          },
                        ),
                      );
                    },
                  ),
                ),

                // Splitter
                GestureDetector(
                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                    timelineViewModel.updateTrackLabelWidth(trackLabelWidth + details.delta.dx);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      width: 6,
                      color: theme.resources.subtleFillColorSecondary,
                      margin: const EdgeInsets.symmetric(horizontal: 1), // Small margin for visual separation
                      alignment: Alignment.center,
                      child: Container(
                        width: 1.5,
                        color: theme.resources.controlStrokeColorDefault,
                      ),
                    ),
                  ),
                ),

                // Timeline tracks - Takes remaining space
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double framePixelWidth = 5.0;
                      final double contentWidth = totalFrames * zoom * framePixelWidth;
                      final double minScrollWidth = math.max(constraints.maxWidth, contentWidth);

                      // Ensure the playhead calculation uses the available width
                      final double playheadPosition = currentFrame * zoom * framePixelWidth;

                      return Stack(
                        clipBehavior: Clip.hardEdge, // Clip content within bounds
                        children: [
                          // Scrollable Area
                          Positioned.fill(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              controller: trackContentScrollController, // Make sure this is linked
                              child: SizedBox(
                                width: minScrollWidth,
                                child: Column(
                                  children: [
                                    // TimeRuler - ensure it aligns and scrolls correctly
                                    SizedBox(
                                      height: 25,
                                      width: minScrollWidth,
                                      child: TimeRuler(
                                        zoom: zoom,
                                        currentFrame: currentFrame,
                                        availableWidth: minScrollWidth, // Use full content width for ruler
                                      ),
                                    ),
                                    // Tracks List
                                    Expanded(
                                      child: ListView.builder(
                                        // Link the controllers ONLY if vertical scrolling is intended here
                                        // For horizontal sync, the SingleChildScrollView's controller is key.
                                        // controller: trackContentScrollController, // Removed if only horizontal scroll needed
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        itemCount: tracks.length, // Use watched tracks.length
                                        itemBuilder: (context, index) {
                                          final track = tracks[index]; // Use watched tracks list
                                          final trackClips = clips.where((clip) => clip.trackId == track.id).toList();
                                          return TimelineTrack(
                                            trackId: track.id, // Pass track.id instead of index
                                            clips: trackClips,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Playhead
                          Positioned(
                            top: 0, // Align playhead with the top of the TimeRuler
                            bottom: 0,
                            left: playheadPosition,
                            width: 2,
                            child: Container(
                              color: theme.accentColor.normal,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
