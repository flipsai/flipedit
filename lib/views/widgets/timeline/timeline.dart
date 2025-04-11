import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/enums/clip_type.dart';
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
    // Use watch_it's data binding to observe multiple properties in a clean way
    final timelineViewModel =
        di<TimelineViewModel>(); // Get the ViewModel instance
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final currentFrame = watchValue(
      (TimelineViewModel vm) => vm.currentFrameNotifier,
    );
    final isPlaying = watchValue(
      (TimelineViewModel vm) => vm.isPlayingNotifier,
    );
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    // Get the separate scroll controllers from the ViewModel
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
              children: [
                // Track labels - Fixed width for labels
                Container(
                  width: 120,
                  color:
                      theme
                          .resources
                          .subtleFillColorTransparent, // A slightly different, subtle background
                  child: ListView(
                    controller: trackLabelScrollController, // Use label controller
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                    ), // Consistent padding
                    children: const [
                      // Add SizedBox to align with TimeRuler
                      SizedBox(height: 25),
                      // Use const for static labels
                      TrackLabel(label: 'Video 1', icon: FluentIcons.video),
                      TrackLabel(
                        label: 'Audio 1',
                        icon: FluentIcons.music_in_collection,
                      ),
                      // Add more tracks as needed
                    ],
                  ),
                ),

                // Timeline tracks - Takes remaining space
                Expanded(
                  child: LayoutBuilder(
                    // Wrap with LayoutBuilder
                    builder: (context, constraints) {
                      // Calculate content width based on total frames and zoom
                      const double framePixelWidth = 5.0;
                      final double contentWidth =
                          totalFrames * zoom * framePixelWidth;

                      // Calculate minimum width needed for the scrollable area
                      final double minScrollWidth = math.max(
                        constraints.maxWidth, // Width of the viewport
                        contentWidth, // Width required by all frames
                      );

                      return Stack(
                        children: [
                          // Scrollable tracks area
                          Positioned.fill(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              // controller: ScrollController(), // Consider adding if programmatic scroll is needed
                              child: SizedBox(
                                // Set width to ensure it fills viewport or content, whichever is larger
                                width: minScrollWidth,
                                child: Column(
                                  children: [
                                    // Time ruler - Pass available width
                                    TimeRuler(
                                      zoom: zoom,
                                      currentFrame: currentFrame,
                                      availableWidth:
                                          constraints
                                              .maxWidth, // Pass viewport width
                                    ),

                                    // Tracks container
                                    Expanded(
                                      child: ListView(
                                        controller:
                                            trackContentScrollController, // Use content controller
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ), // Consistent padding
                                        children: [
                                          // Video track with clips
                                          TimelineTrack(
                                            trackIndex: 0,
                                            clips:
                                                clips
                                                    .where(
                                                      (clip) =>
                                                          clip.type ==
                                                              ClipType.video ||
                                                          clip.type ==
                                                              ClipType.image,
                                                    )
                                                    .toList(),
                                          ),

                                          // Audio track
                                          TimelineTrack(
                                            trackIndex: 1,
                                            clips:
                                                clips
                                                    .where(
                                                      (clip) =>
                                                          clip.type ==
                                                          ClipType.audio,
                                                    )
                                                    .toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Current frame indicator (playhead)
                          Positioned(
                            top:
                                25, // Adjust top position to be below the ruler (ruler height is 25)
                            bottom: 0,
                            // Calculate position based on frame and zoom
                            left:
                                currentFrame *
                                zoom *
                                framePixelWidth, // Use constant
                            width: 2,
                            child: Container(
                              // Use theme accent color for the playhead
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
