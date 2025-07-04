import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/play_pause_command.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flipedit/utils/logger.dart';

/// Controls widget for the timeline including playback controls and zoom
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/services/video_player_service.dart';

/// Controls widget for the timeline including playback controls and zoom
class TimelineControls extends StatelessWidget with WatchItMixin {
  const TimelineControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final controlsContentColor = theme.resources.textFillColorPrimary;
    final timelineViewModel =
        di<TimelineViewModel>(); // Still needed for edit mode
    final timelineNavigationViewModel =
        di<TimelineNavigationViewModel>(); // Inject Navigation VM
    final editorViewModel =
        di<EditorViewModel>(); // Still needed for snapping/aspect lock

    // Watch navigation/playback values from TimelineNavigationViewModel
    final isPlaying = watchValue(
      (TimelineNavigationViewModel vm) => vm.isPlayingNotifier, // Back to timeline navigation
    );
    final totalFrames = watchValue(
      (TimelineNavigationViewModel vm) => vm.totalFramesNotifier,
    );
    final zoom = watchValue(
      (TimelineNavigationViewModel vm) => vm.zoomNotifier,
    );
    final isPlayheadLocked = watchValue(
      (TimelineNavigationViewModel vm) => vm.isPlayheadLockedNotifier,
    );

    // Watch video player service state for better feedback
    final hasActiveVideo = watchValue(
      (VideoPlayerService service) => service.hasActiveVideoNotifier,
    );

    // Watch snapping and aspect ratio lock states from EditorViewModel
    final snappingEnabled = watchValue(
      (EditorViewModel vm) => vm.snappingEnabledNotifier,
    );
    final aspectRatioLocked = watchValue(
      (EditorViewModel vm) => vm.aspectRatioLockedNotifier,
    );

    // Edit mode toolbar
    final currentMode = watchValue(
      (TimelineViewModel vm) => vm.currentEditMode,
    );
    final modeButtons = <Widget>[
      Tooltip(
        message: 'Select',
        child: Container(
          decoration: BoxDecoration(
            color:
                currentMode == EditMode.select
                    ? theme.accentColor.lightest
                    : Colors.transparent,
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
              icon: Icon(
                HugeIcons.strokeRoundedMinusSign,
                size: 16,
                color: controlsContentColor,
              ),
              // Use navigation VM for zoom setter
              onPressed:
                  zoom > 0.2
                      ? () => timelineNavigationViewModel.zoom = zoom / 1.2
                      : null,
            ),
          ),
          Tooltip(
            message: 'Zoom Level',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                '${(zoom * 100).toStringAsFixed(0)}%', // Use watched zoom
                style: theme.typography.caption?.copyWith(fontSize: 10),
              ),
            ),
          ),
          Tooltip(
            message: 'Zoom In',
            child: IconButton(
              icon: Icon(
                HugeIcons.strokeRoundedAdd01,
                size: 16,
                color: controlsContentColor,
              ),
              // Use navigation VM for zoom setter
              onPressed:
                  zoom < 5.0
                      ? () => timelineNavigationViewModel.zoom = zoom * 1.2
                      : null,
            ),
          ),

          const SizedBox(width: 16),

          Tooltip(
            message: 'Go to Start',
            child: IconButton(
              icon: Icon(
                HugeIcons.strokeRoundedBackward01,
                size: 16,
                color: controlsContentColor,
              ),
              // Use navigation VM for currentFrame setter
              onPressed: () => timelineNavigationViewModel.currentFrame = 0,
            ),
          ),
          Tooltip(
            message: !hasActiveVideo 
              ? 'Loading video player...' 
              : isPlaying ? 'Pause' : 'Play', // Use watched isPlaying
            child: IconButton(
              icon: Icon(
                isPlaying
                    ? HugeIcons.strokeRoundedPause
                    : HugeIcons.strokeRoundedPlay,
                size: 16,
                color: !hasActiveVideo 
                  ? controlsContentColor.withOpacity(0.5)  // Dimmed when not ready
                  : controlsContentColor,
              ),
              // Use PlayPauseCommand for unified playback control
              onPressed: () async {
                logInfo("Play button pressed - isPlaying: $isPlaying, hasActiveVideo: $hasActiveVideo", 'TimelineControls');
                final command = PlayPauseCommand(vm: timelineNavigationViewModel);
                await command.execute();
              },
            ),
          ),
          Tooltip(
            message: 'Go to End',
            child: IconButton(
              icon: Icon(
                HugeIcons.strokeRoundedForward01,
                size: 16,
                color: controlsContentColor,
              ),
              // Use navigation VM for currentFrame setter
              onPressed:
                  () => timelineNavigationViewModel.currentFrame = totalFrames,
            ),
          ),

          Tooltip(
            // Add Tooltip for Lock Playhead
            message:
                isPlayheadLocked
                    ? 'Unlock Playhead Scroll'
                    : 'Lock Playhead Scroll',
            child: Container(
              decoration: BoxDecoration(
                color:
                    isPlayheadLocked
                        ? theme.accentColor.lightest
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  isPlayheadLocked
                      ? FluentIcons.lock
                      : FluentIcons.unlock, // Use FluentIcons
                  size: 16,
                  color: controlsContentColor,
                ),
                // Use navigation VM for togglePlayheadLock
                onPressed: timelineNavigationViewModel.togglePlayheadLock,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(
                    controlsContentColor,
                  ),
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
                color:
                    snappingEnabled
                        ? theme.accentColor.lightest
                        : Colors.transparent, // Use watched state
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  HugeIcons.strokeRoundedMagnet,
                  size: 16,
                  color: controlsContentColor,
                ),
                onPressed:
                    editorViewModel.toggleSnapping, // Call ViewModel method
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(
                    controlsContentColor,
                  ),
                ),
              ),
            ),
          ),

          Tooltip(
            message:
                aspectRatioLocked
                    ? 'Unlock Aspect Ratio (Aspect Ratio Locked)'
                    : 'Lock Aspect Ratio', // Use watched state for message
            child: Container(
              decoration: BoxDecoration(
                color:
                    aspectRatioLocked
                        ? theme.accentColor.lightest
                        : Colors.transparent, // Use watched state
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(
                  aspectRatioLocked
                      ? HugeIcons.strokeRoundedTouchLocked01
                      : HugeIcons
                          .strokeRoundedTouch01, // Use suggested touch icons
                  size: 16,
                  color: controlsContentColor,
                ),
                onPressed:
                    editorViewModel
                        .toggleAspectRatioLock, // Call ViewModel method
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.all(4)),
                  foregroundColor: WidgetStateProperty.all(
                    controlsContentColor,
                  ),
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
