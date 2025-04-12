import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/project_service.dart';

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

          const Spacer(),

          // Add Media Button
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
    // Get ProjectService instance
    final projectService = di<ProjectService>();
    return FilledButton(
      onPressed: () async {
        print("Add Media button pressed - Placeholder");
        
        // Get the first track ID or default/error if none
        final int targetTrackId;
        // Access tracks directly from the ProjectService notifier
        final currentTracks = projectService.currentProjectTracksNotifier.value;
        if (currentTracks.isNotEmpty) {
           targetTrackId = currentTracks.first.id;
        } else {
           print("Error: No tracks loaded to add clip to.");
           // Optionally show a user message
           return; // Don't proceed if no track is available
        }

        final dummyClipData = ClipModel(
          databaseId: null,
          trackId: targetTrackId, // Use determined track ID
          name: 'New Video Clip',
          type: ClipType.video,
          sourcePath: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
          startTimeInSourceMs: 0,
          endTimeInSourceMs: 5000,
          startTimeOnTrackMs: 0,
        );
        await timelineViewModel.addClipAtPosition(
          clipData: dummyClipData,
          trackId: targetTrackId, // Use determined track ID
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
