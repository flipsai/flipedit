import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:hugeicons/hugeicons.dart';

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
    final totalFrames = watchValue((TimelineViewModel vm) => vm.totalFramesNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    // Edit mode toolbar
    final currentMode = watchValue((TimelineViewModel vm) => vm.currentEditMode);
    final modeButtons = <Widget>[
      Tooltip(
        message: 'Select',
        child: Container(
          decoration: BoxDecoration(
            color: currentMode == EditMode.select ? theme.accentColor.lightest : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedCursor01, size: 16),
            onPressed: () => timelineViewModel.setEditMode(EditMode.select),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              foregroundColor: WidgetStateProperty.all(controlsContentColor),
            ),
          ),
        ),
      ),
      Tooltip(
        message: 'Ripple Trim',
        child: Container(
          decoration: BoxDecoration(
            color: currentMode == EditMode.rippleTrim ? theme.accentColor.lightest : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedCrop, size: 16),
            onPressed: () => timelineViewModel.setEditMode(EditMode.rippleTrim),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              foregroundColor: WidgetStateProperty.all(controlsContentColor),
            ),
          ),
        ),
      ),
      Tooltip(
        message: 'Roll',
        child: Container(
          decoration: BoxDecoration(
            color: currentMode == EditMode.rollEdit ? theme.accentColor.lightest : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedArrowHorizontal, size: 16),
            onPressed: () => timelineViewModel.setEditMode(EditMode.rollEdit),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              foregroundColor: WidgetStateProperty.all(controlsContentColor),
            ),
          ),
        ),
      ),
      Tooltip(
        message: 'Slip',
        child: Container(
          decoration: BoxDecoration(
            color: currentMode == EditMode.slip ? theme.accentColor.lightest : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedCursorMove01, size: 16),
            onPressed: () => timelineViewModel.setEditMode(EditMode.slip),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              foregroundColor: WidgetStateProperty.all(controlsContentColor),
            ),
          ),
        ),
      ),
      Tooltip(
        message: 'Slide',
        child: Container(
          decoration: BoxDecoration(
            color: currentMode == EditMode.slide ? theme.accentColor.lightest : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(HugeIcons.strokeRoundedArrowHorizontal, size: 16),
            onPressed: () => timelineViewModel.setEditMode(EditMode.slide),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
              foregroundColor: WidgetStateProperty.all(controlsContentColor),
            ),
          ),
        ),
      ),
    ];

    return Container(
      height: 40,
      color: theme.resources.subtleFillColorSecondary,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Zoom Out',
            child: IconButton(
              icon: Icon(HugeIcons.strokeRoundedMinusSign, size: 16, color: controlsContentColor),
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
              icon: Icon(HugeIcons.strokeRoundedAdd01, size: 16, color: controlsContentColor),
              onPressed: zoom < 5.0 // Use watched zoom directly
                  ? () => timelineViewModel.zoom = zoom * 1.2
                  : null,
            ),
          ),

          const SizedBox(width: 16),

          Tooltip(
            message: 'Go to Start',
            child: IconButton(
              icon: Icon(HugeIcons.strokeRoundedBackward01, size: 16, color: controlsContentColor),
              onPressed: () => timelineViewModel.currentFrame = 0,
            ),
          ),
          Tooltip(
            message: isPlaying ? 'Pause' : 'Play', // Use watched isPlaying
            child: IconButton(
              icon: Icon(
                isPlaying ? HugeIcons.strokeRoundedPause : HugeIcons.strokeRoundedPlay, // Use watched isPlaying
                size: 16,
                color: controlsContentColor, // Ensure color consistency
              ),
              onPressed: timelineViewModel.togglePlayPause, // Call the correct ViewModel method
            ),
          ),
          Tooltip(
            message: 'Go to End',
            child: IconButton(
              icon: Icon(HugeIcons.strokeRoundedForward01, size: 16, color: controlsContentColor),
              // Use watched totalFrames
              onPressed: () => timelineViewModel.currentFrame = totalFrames,
            ),
          ),

          const SizedBox(width: 16),

          ...modeButtons,

          const SizedBox(width: 16),
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
