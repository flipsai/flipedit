import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Controls widget for the timeline including playback controls and zoom
class TimelineControls extends StatelessWidget {
  final bool isPlaying;
  final int currentFrame;
  final double zoom;

  const TimelineControls({
    super.key,
    required this.isPlaying,
    required this.currentFrame,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final controlsContentColor = theme.resources.textFillColorPrimary;
    final timelineViewModel = di<TimelineViewModel>();

    return Container(
      height: 40,
      color: theme.resources.subtleFillColorSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
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
                isPlaying ? FluentIcons.pause : FluentIcons.play_solid,
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
              onPressed: () => timelineViewModel.seekTo(timelineViewModel.totalFrames),
            ),
          ),

          const SizedBox(width: 16),

          Text(
            'Frame: $currentFrame / ${timelineViewModel.totalFrames}',
            style: theme.typography.caption?.copyWith(
              color: controlsContentColor,
            ),
          ),

          const Spacer(),
          
          Tooltip(
            message: 'Add a new clip at the current frame',
            child: FilledButton(
              onPressed: () => _showAddClipDialog(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.add, size: 12),
                  const SizedBox(width: 4),
                  Text('Add Clip', style: theme.typography.caption),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddClipDialog(BuildContext context) {
    final timelineViewModel = di<TimelineViewModel>();

    final newClip = Clip(
      trackIndex: 0,
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Dummy Clip',
      type: ClipType.video,
      filePath: '/path/to/dummy/file.mp4',
      startFrame: timelineViewModel.currentFrame,
      durationFrames: 150,
    );

    timelineViewModel.addClip(newClip);
  }
} 