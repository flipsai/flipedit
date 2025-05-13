import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/views/widgets/player/stream_video_player.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart'; // Added for stream URL and status

class PlayerPanel extends StatelessWidget with WatchItMixin {
  const PlayerPanel({super.key});

  // Define the server base URL as a constant for stability
  static const String _serverBaseUrl = 'http://localhost:8085';

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    final bool hasActiveProject = watchValue((TimelineNavigationViewModel vm) => vm.totalFramesNotifier) > 0;
    final bool isConnected = watchValue((PreviewViewModel vm) => vm.isConnectedNotifier);
    final String statusMessage = watchValue((PreviewViewModel vm) => vm.statusNotifier);
    
    // Get current frame and playback state from TimelineNavigationViewModel
    final int currentTimelineFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    final bool isPlaying = watchValue((TimelineNavigationViewModel vm) => vm.isPlayingNotifier);

    Widget content;

    if (!hasActiveProject) {
      content = const Center(
        child: Text('No media loaded', style: TextStyle(color: Colors.white)),
      );
    } else if (!isConnected) {
      content = Center(
        child: Text(
          'Preview Server Offline: $statusMessage',
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      // StreamVideoPlayer now takes a stable serverBaseUrl and an initialFrame from the timeline.
      // Its internal controller will handle seeking and stream restarts as needed based on these props.
      content = StreamVideoPlayer(
        key: ValueKey(_serverBaseUrl), // Ensures re-init if base URL were to change, though it's constant here
        serverBaseUrl: _serverBaseUrl,
        initialFrame: currentTimelineFrame, 
        autoPlay: isPlaying,
        showControls: true,
      );
    }

    return material.Material(
      color: const Color(0xFF333333), // Background color for the panel
      child: content,
    );
  }
}
