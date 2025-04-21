import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

/// Controls widget for the timeline including playback controls and zoom
class TimelineControls extends StatelessWidget with WatchItMixin {
  const TimelineControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final controlsContentColor = theme.resources.textFillColorPrimary;
    final timelineViewModel = di<TimelineViewModel>();

    // Watch basic values
    final isPlaying = watchValue((TimelineViewModel vm) => vm.isPlayingNotifier);
    final currentFrame = watchValue((TimelineViewModel vm) => vm.currentFrameNotifier);
    final totalFrames = watchValue((TimelineViewModel vm) => vm.totalFramesNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    // Watch the controller itself (can be null)
    final controller = watchValue((TimelineViewModel vm) => vm.videoPlayerControllerNotifier);

    return Container(
      height: 40,
      color: theme.resources.subtleFillColorSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Zoom Out',
            child: IconButton(
              icon: Icon(FluentIcons.remove, size: 16, color: controlsContentColor),
              onPressed: zoom > 0.2 // Use watched zoom directly
                  ? () => timelineViewModel.zoom = zoom / 1.2
                  : null,
            ),
          ),
          Tooltip(
            message: 'Zoom Level',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('${(zoom * 100).toStringAsFixed(0)}%', // Use watched zoom
                  style: theme.typography.caption?.copyWith(fontSize: 10)),
            ),
          ),
          Tooltip(
            message: 'Zoom In',
            child: IconButton(
              icon: Icon(FluentIcons.add, size: 16, color: controlsContentColor),
              onPressed: zoom < 5.0 // Use watched zoom directly
                  ? () => timelineViewModel.zoom = zoom * 1.2
                  : null,
            ),
          ),

          const SizedBox(width: 16),

          Tooltip(
            message: 'Go to Start',
            child: IconButton(
              icon: Icon(FluentIcons.previous, size: 16, color: controlsContentColor),
              onPressed: () => timelineViewModel.currentFrame = 0,
            ),
          ),
          Tooltip(
            message: isPlaying ? 'Pause' : 'Play', // Use watched isPlaying
            child: IconButton(
              icon: Icon(
                isPlaying ? FluentIcons.pause : FluentIcons.play, // Use watched isPlaying
                size: 16,
                color: controlsContentColor, // Ensure color consistency
              ),
              onPressed: () => timelineViewModel.togglePlayPause(),
            ),
          ),
          Tooltip(
            message: 'Go to End',
            child: IconButton(
              icon: Icon(FluentIcons.next, size: 16, color: controlsContentColor),
              // Use watched totalFrames
              onPressed: () => timelineViewModel.currentFrame = totalFrames,
            ),
          ),

          const SizedBox(width: 16),

          // Timecode Display
          if (controller != null)
            _TimecodeDisplay(controller: controller) // Use the new widget
          else
            // Fallback display when no controller is available
            Text(
              'Frame: $currentFrame / $totalFrames', // Use watched values
              style: theme.typography.caption?.copyWith(
                color: controlsContentColor,
                fontFamily: 'monospace', // Use monospace for frame count too
              ),
            ),
        ],
      ),
    );
  }
}

// New widget for timecode display using watch_it
class _TimecodeDisplay extends StatelessWidget with WatchItMixin {
  final VideoPlayerController controller;

  const _TimecodeDisplay({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final controlsContentColor = theme.resources.textFillColorPrimary;

    // Watch the controller - this widget rebuilds when controller notifies changes
    watch(controller);

    // Access value directly after watching
    final value = controller.value;

    if (!value.isInitialized) {
      return Text(
        '--:--.-- / --:--.--',
        style: theme.typography.caption?.copyWith(
          color: controlsContentColor,
          fontFamily: 'monospace',
        ),
      );
    }
    
    final position = value.position;
    final duration = value.duration;
    final positionString = _formatDuration(position);
    final durationString = _formatDuration(duration);
    
    return Text(
      '$positionString / $durationString',
      style: theme.typography.caption?.copyWith(
        color: controlsContentColor,
        fontFamily: 'monospace',
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    // Ensure milliseconds are padded to 3 digits for consistency
    String threeDigitMilliseconds = (d.inMilliseconds.remainder(1000)).toString().padLeft(3, "0");
    return '$twoDigitMinutes:$twoDigitSeconds.$threeDigitMilliseconds';
  }
}
