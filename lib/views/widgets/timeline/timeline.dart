import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
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
          // Timeline controls
          _buildTimelineControls(context, isPlaying, currentFrame, zoom),

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
                      _TrackLabel(label: 'Video 1', icon: FluentIcons.video),
                      _TrackLabel(
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
                                _TimeRuler(
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

  Widget _buildTimelineControls(
    BuildContext context,
    bool isPlaying,
    int currentFrame,
    double zoom,
  ) {
    final theme = FluentTheme.of(context);
    // Use primary text color from theme for icons/text on controls
    final controlsContentColor = theme.resources.textFillColorPrimary;
    final timelineViewModel = di<TimelineViewModel>();

    return Container(
      height: 40,
      // Use a subtle fill color for the controls background
      color: theme.resources.subtleFillColorSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Zoom controls
          Tooltip(
            message: 'Zoom Out',
            child: IconButton(
              icon: Icon(
                FluentIcons.remove,
                size: 16,
                color: controlsContentColor,
              ),
              onPressed: () => timelineViewModel.setZoom(zoom / 1.2),
            ),
          ),
          Tooltip(
            message: 'Zoom In',
            child: IconButton(
              icon: Icon(
                FluentIcons.add,
                size: 16,
                color: controlsContentColor,
              ),
              onPressed: () => timelineViewModel.setZoom(zoom * 1.2),
            ),
          ),

          const SizedBox(width: 16),

          // Playback controls
          Tooltip(
            message: 'Go to Start',
            child: IconButton(
              icon: Icon(
                FluentIcons.previous,
                size: 16,
                color: controlsContentColor,
              ),
              onPressed: () => timelineViewModel.seekTo(0),
            ),
          ),
          Tooltip(
            message: isPlaying ? 'Pause' : 'Play',
            child: IconButton(
              icon: Icon(
                isPlaying
                    ? FluentIcons.pause
                    : FluentIcons.play_solid, // Use solid play icon
                size: 16,
                color: controlsContentColor,
              ),
              onPressed: () => timelineViewModel.togglePlayback(),
            ),
          ),
          Tooltip(
            message: 'Go to End',
            child: IconButton(
              icon: Icon(
                FluentIcons.next,
                size: 16,
                color: controlsContentColor,
              ),
              onPressed:
                  () => timelineViewModel.seekTo(timelineViewModel.totalFrames),
            ),
          ),

          const SizedBox(width: 16),

          // Frame counter
          Text(
            'Frame: $currentFrame / ${timelineViewModel.totalFrames}',
            // Use theme typography, the color should be inherited or use primary text color
            style: theme.typography.caption?.copyWith(
              color: controlsContentColor,
            ),
          ),

          const Spacer(), // Pushes the following items to the end
          // Add clip button
          Tooltip(
            message: 'Add a new clip at the current frame',
            child: FilledButton(
              onPressed: () => _showAddClipDialog(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.add, size: 12),
                  const SizedBox(width: 4),
                  // FilledButton text color should be handled by the theme
                  Text('Add Clip', style: theme.typography.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Keep the add clip logic, maybe replace with actual file picking later
  void _showAddClipDialog(BuildContext context) {
    final timelineViewModel = di<TimelineViewModel>();

    final newClip = Clip(
      trackIndex: 0,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Dummy Clip', // More descriptive dummy name
      type: ClipType.video,
      filePath: '/path/to/dummy/file.mp4', // Placeholder path
      startFrame: timelineViewModel.currentFrame, // Add at current playhead
      durationFrames: 150, // Default duration (e.g., 5 seconds at 30fps)
    );

    timelineViewModel.addClip(newClip);
    // Optionally show a confirmation notification
    // displayInfoBar(context, builder: (context, close) {
    //   return InfoBar(
    //     title: const Text('Clip Added'),
    //     content: Text('${newClip.name} added to timeline.'),
    //     severity: InfoBarSeverity.success,
    //     isLong: false,
    //   );
    // });
  }
}

class _TrackLabel extends StatelessWidget {
  final String label;
  final IconData icon; // Accept icon data

  const _TrackLabel({required this.label, required this.icon}); // Use key

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      height: 60, // Standard height for track labels
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(
        bottom: 4,
        left: 4,
        right: 4,
      ), // Add spacing
      decoration: BoxDecoration(
        // Use a very subtle background for labels within the labels panel
        color: theme.resources.subtleFillColorTertiary,
        borderRadius: BorderRadius.circular(4),
        // Optional: Add a subtle border
        // border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        children: [
          Icon(
            icon, // Use passed icon
            size: 16,
            // Use secondary text color for less emphasis
            color: theme.resources.textFillColorSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            // Allow text to wrap if needed
            child: Text(
              label,
              // Use primary text color for labels
              style: theme.typography.body?.copyWith(
                color: theme.resources.textFillColorPrimary,
              ),
              overflow: TextOverflow.ellipsis, // Prevent overflow
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRuler extends StatelessWidget with WatchItMixin {
  final double zoom;
  final int currentFrame; // Keep currentFrame if needed for highlighting later

  const _TimeRuler({required this.zoom, required this.currentFrame});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Watch totalFrames for dynamic ruler length
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    const double frameWidth = 5.0; // Width of one frame at zoom 1.0
    const int framesPerMajorTick = 30; // e.g., Major tick every second at 30fps
    const int framesPerMinorTick = 5; // Minor tick every 5 frames

    // Consider using CustomPaint for performance with many ticks,
    // but ListView.builder is simpler for now.
    return Container(
      height: 25, // Slightly taller ruler
      // Match controls background
      color: theme.resources.subtleFillColorSecondary,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // Calculate itemCount based on frames and tick interval
        // This might draw more items than strictly necessary but simplifies logic
        itemCount: (totalFrames / framesPerMinorTick).ceil() + 1,
        itemBuilder: (context, index) {
          final frameNumber = index * framesPerMinorTick;
          final isMajorTick = frameNumber % framesPerMajorTick == 0;
          final tickHeight = isMajorTick ? 10.0 : 5.0; // Taller major ticks
          final tickWidth = frameWidth * framesPerMinorTick * zoom;

          return Container(
            width: tickWidth,
            decoration: BoxDecoration(
              border: Border(
                // Use standard control stroke
                right: BorderSide(
                  color: theme.resources.controlStrokeColorDefault,
                ),
              ),
            ),
            child: Stack(
              children: [
                // Tick mark line
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 1, // Tick line width
                    height: tickHeight,
                    // Use secondary text color for tick marks
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                // Label for major ticks
                if (isMajorTick)
                  Positioned(
                    left: 3, // Offset label slightly
                    top: 0,
                    child: Text(
                      // Display timecode (e.g., seconds) or frame number
                      // (frameNumber ~/ 30).toString() // Example: Seconds at 30fps
                      frameNumber.toString(),
                      // Use secondary text color for ruler labels
                      style: theme.typography.caption?.copyWith(
                        fontSize: 10,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
