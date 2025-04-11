import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/track_label.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatelessWidget with WatchItMixin {
  const Timeline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it's data binding to observe multiple properties in a clean way
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

    return Container(
      // Use a standard dark background from the theme resources
      color: theme.resources.cardBackgroundFillColorDefault,
      // Use theme subtle border color
      // border: Border(top: BorderSide(color: theme.resources.controlStrokeColorDefault)),
      child: Column(
        children: [
          TimelineControls(
            isPlaying: isPlaying,
            currentFrame: currentFrame,
            zoom: zoom,
          ),

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
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                    ), // Consistent padding
                    children: const [
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
                  child: Stack(
                    children: [
                      // Scrollable tracks area
                      Positioned.fill(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          // Add a controller for potential programmatic scrolling
                          // controller: ScrollController(),
                          child: Container(
                            // Calculate width based on total frames and zoom factor
                            // Ensure minimum width to prevent visual issues if totalFrames is 0
                            width:
                                (totalFrames * zoom * 5.0).clamp(
                                  MediaQuery.of(context).size.width - 120,
                                  double.infinity,
                                ) +
                                200, // Adjusted width calculation
                            child: Column(
                              children: [
                                // Time ruler
                                TimeRuler(
                                  zoom: zoom,
                                  currentFrame: currentFrame,
                                ),

                                // Tracks container
                                Expanded(
                                  child: ListView(
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
                        top: 0, // Should start below the ruler
                        bottom: 0,
                        // Calculate position based on frame and zoom
                        left: currentFrame * zoom * 5.0,
                        width: 2,
                        child: Container(
                          // Use theme accent color for the playhead
                          color: theme.accentColor.normal,
                        ),
                      ),
                    ],
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
