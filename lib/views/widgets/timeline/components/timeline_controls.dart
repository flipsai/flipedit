import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
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

    final isPlaying = watchValue(
      (TimelineViewModel vm) => vm.isPlayingNotifier,
    );
    final currentFrame = watchValue(
      (TimelineViewModel vm) => vm.currentFrameNotifier,
    );
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    final controller = watchValue(
      (TimelineViewModel vm) => vm.videoPlayerControllerNotifier,
    );

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
              onPressed: timelineViewModel.zoom > 0.2
                  ? () => timelineViewModel.zoom = zoom / 1.2
                  : null,
            ),
          ),
          Tooltip(
            message: 'Zoom Level Display (Optional)',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('${(zoom * 100).toStringAsFixed(0)}%',
                  style: theme.typography.caption?.copyWith(fontSize: 10)),
            ),
          ),
          Tooltip(
            message: 'Zoom In',
            child: IconButton(
              icon: Icon(FluentIcons.add, size: 16, color: controlsContentColor),
              onPressed: timelineViewModel.zoom < 5.0
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
            message: isPlaying ? 'Pause' : 'Play',
            child: IconButton(
              icon: Icon(
                isPlaying ? FluentIcons.pause : FluentIcons.play,
                size: 16,
              ),
              onPressed: () => timelineViewModel.togglePlayPause(),
            ),
          ),
          Tooltip(
            message: 'Go to End',
            child: IconButton(
              icon: Icon(FluentIcons.next, size: 16, color: controlsContentColor),
              onPressed: () => timelineViewModel.currentFrame = totalFrames,
            ),
          ),

          const SizedBox(width: 16),

          if (controller != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) {
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
              },
            )
          else
            Text(
              'Frame: $currentFrame / $totalFrames',
              style: theme.typography.caption?.copyWith(
                color: controlsContentColor,
              ),
            ),

          const Spacer(),

          Tooltip(
            message: 'Add Media',
            child: _buildAddMediaButton(context, timelineViewModel, theme, controlsContentColor),
          ),
        ],
      ),
    );
  }

  // Helper method for Add Media button
  Widget _buildAddMediaButton(
    BuildContext context,
    TimelineViewModel timelineViewModel,
    FluentThemeData theme,
    Color controlsContentColor,
  ) {
    return FilledButton(
      onPressed: () async {
        print("Add Media button pressed - Placeholder");
        final dummyClipData = ClipModel(
          databaseId: null,
          trackId: 1, // TODO: Determine target track ID
          name: 'New Video Clip',
          type: ClipType.video,
          sourcePath: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          startTimeInSourceMs: 0,
          endTimeInSourceMs: 5000,
          startTimeOnTrackMs: 0,
        );
        await timelineViewModel.addClipAtPosition(
          clipData: dummyClipData,
          trackId: 1, // TODO: Determine target track ID
          startTimeInSourceMs: dummyClipData.startTimeInSourceMs,
          endTimeInSourceMs: dummyClipData.endTimeInSourceMs,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.add, size: 12, color: controlsContentColor),
          const SizedBox(width: 4),
          Text('Add Clip', style: theme.typography.caption?.copyWith(color: controlsContentColor)),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    String twoDigitMilliseconds = twoDigits(d.inMilliseconds.remainder(1000));
    return '$twoDigitMinutes:$twoDigitSeconds.$twoDigitMilliseconds';
  }
}
