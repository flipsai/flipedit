import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/views/widgets/player/websocket_frame_player.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/di/service_locator.dart';

class PlayerPanel extends StatelessWidget with WatchItMixin {
  const PlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');
    
    // Watch the timeline navigation viewmodel for changes
    final timelineNavigationViewModel = watchIt<TimelineNavigationViewModel>();
    // A project is active if there are frames in the timeline
    final bool hasActiveProject = timelineNavigationViewModel.totalFrames > 0;
    
    // If no project is loaded, show a placeholder
    if (!hasActiveProject) {
      return Container(
        color: const Color(0xFF333333),
        child: const Center(
          child: Text('No media loaded', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    
    // WebSocket URL for the frame server (adjust as needed)
    const websocketUrl = 'ws://localhost:8765';
    
    return material.Material(
      child: WebSocketFramePlayer(
        websocketUrl: websocketUrl,
        autoPlay: true,
        showControls: true,
      ),
    );
  }
}
