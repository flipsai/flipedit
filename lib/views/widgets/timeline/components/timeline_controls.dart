import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:hugeicons/hugeicons.dart';

/// Controls widget for the timeline including playback controls and zoom
import 'package:flipedit/viewmodels/editor_viewmodel.dart'; // Import EditorViewModel

/// Controls widget for the timeline including playback controls and zoom
class TimelineControls extends StatelessWidget with WatchItMixin {
  const TimelineControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final controlsContentColor = theme.resources.textFillColorPrimary;
    final timelineViewModel = di<TimelineViewModel>();
    final editorViewModel = di<EditorViewModel>(); // Inject EditorViewModel

    // Watch basic values
    final isPlaying = watchValue((TimelineViewModel vm) => vm.isPlayingNotifier);
    final totalFrames = watchValue((TimelineViewModel vm) => vm.totalFramesNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final isPlayheadLocked = watchValue((TimelineViewModel vm) => vm.isPlayheadLockedNotifier); // Watch lock state

    // Watch snapping and aspect ratio lock states from EditorViewModel
    final snappingEnabled = watchValue((EditorViewModel vm) => vm.snappingEnabledNotifier);
    final aspectRatioLocked = watchValue((EditorViewModel vm) => vm.aspectRatioLockedNotifier);

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
          ), // End Tooltip for Go to End

          Tooltip( // Add Tooltip for Lock Playhead
            message: isPlayheadLocked ? 'Unlock Playhead Scroll' : 'Lock Playhead Scroll',
            child: Container(
              decoration: BoxDecoration(
                color: isPlayheadLocked ? theme.accentColor.lightest : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  isPlayheadLocked ? FluentIcons.lock : FluentIcons.unlock, // Use FluentIcons
                  size: 16,
                  color: controlsContentColor,
                ),
                onPressed: timelineViewModel.togglePlayheadLock,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(controlsContentColor),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16), // Spacing after playback controls

          ...modeButtons, // Keep the mode buttons

          const SizedBox(width: 16), // Spacing after mode buttons

          Tooltip(
            message: 'Enable Snapping',
            child: Container(
              decoration: BoxDecoration(
                color: snappingEnabled ? theme.accentColor.lightest : Colors.transparent, // Use watched state
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  HugeIcons.strokeRoundedMagnet,
                  size: 16,
                  color: controlsContentColor,
                ),
                onPressed: editorViewModel.toggleSnapping, // Call ViewModel method
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(controlsContentColor),
                ),
              ),
            ),
          ),

          Tooltip(
            message: aspectRatioLocked ? 'Unlock Aspect Ratio (Aspect Ratio Locked)' : 'Lock Aspect Ratio', // Use watched state for message
            child: Container(
              decoration: BoxDecoration(
                color: aspectRatioLocked ? theme.accentColor.lightest : Colors.transparent, // Use watched state
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  aspectRatioLocked ? HugeIcons.strokeRoundedTouchLocked01 : HugeIcons.strokeRoundedTouch01, // Use suggested touch icons
                  size: 16,
                  color: controlsContentColor,
                ),
                onPressed: editorViewModel.toggleAspectRatioLock, // Call ViewModel method
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(controlsContentColor),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16), // Spacing after new buttons
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
