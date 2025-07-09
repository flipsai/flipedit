import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:io';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/widgets/video_player_widget.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  final TimelineNavigationViewModel _timelineNavViewModel = di<TimelineNavigationViewModel>();
  final TimelineStateViewModel _timelineStateViewModel = di<TimelineStateViewModel>();
  final VideoPlayerService _videoPlayerService = di<VideoPlayerService>();

  @override
  void initState() {
    super.initState();
    
    // Set up listeners for rebuilds when data changes
    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.addListener(_rebuild);
    _videoPlayerService.isPlayingNotifier.addListener(_rebuild);
    _videoPlayerService.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _timelineNavViewModel.isPlayingNotifier.removeListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.removeListener(_rebuild);
    _videoPlayerService.isPlayingNotifier.removeListener(_rebuild);
    _videoPlayerService.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTimelinePlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final isVideoPlaying = _videoPlayerService.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
    final clips = _timelineStateViewModel.clips;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area
          Expanded(
            child: clips.isNotEmpty
                ? const VideoPlayerWidget(
                    key: ValueKey('timeline_player'), // Stable key for timeline player
                  )
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.video,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.54),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            clips.isEmpty ? 'No clips found' : 'No valid video files',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            clips.isEmpty 
                                ? 'Add some video clips to the timeline'
                                : 'Check that video files exist',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.54),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Player controls and info bar
          Container(
            height: 40,
            color: Colors.grey[160],
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Frame info
                Flexible(
                  child: Text(
                    'Frame: $currentFrame',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(width: 8),

                // Playback status info
                Flexible(
                  child: Text(
                    'Timeline: ${isTimelinePlaying ? "Playing" : "Stopped"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                const SizedBox(width: 8),
                
                Flexible(
                  child: Text(
                    'Video: ${isVideoPlaying ? "Playing" : "Stopped"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(width: 8),

                // Clips info
                Flexible(
                  child: Text(
                    'Clips: ${clips.length}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const Spacer(),

                // Timeline status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: clips.isNotEmpty ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    clips.isNotEmpty ? 'Timeline Ready' : 'No Clips',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
