import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show ScaffoldMessenger, SnackBar;
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/views/widgets/player/cached_timeline_video_player_widget.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineStateViewModel _timelineStateViewModel;

  @override
  void initState() {
    super.initState();
    
    logDebug("Initializing PlayerPanel with timeline composer", 'PlayerPanel');

    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineStateViewModel = di<TimelineStateViewModel>();

    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.addListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timelineNavViewModel.isPlayingNotifier.removeListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel with timeline composer...", 'PlayerPanel');

    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
    final clips = _timelineStateViewModel.clipsNotifier.value;
    final hasVideoClips = clips.any((clip) => clip.type == ClipType.video);

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area - shows timeline composition
          Expanded(
            child: hasVideoClips
                ? CachedTimelineVideoPlayerWidget(
                    clips: clips,
                    timelineNavViewModel: _timelineNavViewModel,
                  )
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            FluentIcons.video,
                            size: 48,
                            color: Colors.white.withOpacity(0.54),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No video clips in timeline',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add video clips to the timeline to see playback',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.54),
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
                // Play/Pause button
                Button(
                  onPressed: hasVideoClips ? () async {
                    try {
                      if (isPlaying) {
                        _timelineNavViewModel.stopPlayback();
                      } else {
                        await _timelineNavViewModel.startPlayback();
                      }
                    } catch (e) {
                      logError('PlayerPanel', 'Error toggling playback: $e');
                      // Show error to user if needed
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Playback error: ${e.toString()}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  } : null,
                  child: Icon(
                    isPlaying ? FluentIcons.pause : FluentIcons.play,
                    size: 16,
                  ),
                ),

                const SizedBox(width: 8),

                // Frame info
                Text('Frame: $currentFrame'),

                const Spacer(),

                // Mode label
                Text(
                  hasVideoClips 
                      ? 'Cached Player (${clips.length} clips)'
                      : 'Cached Player (Empty)',
                  style: FluentTheme.of(context).typography.caption,
                ),

                const SizedBox(width: 8),

                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: hasVideoClips 
                        ? Colors.green // Green for active timeline with video clips
                        : Colors.orange, // Orange for empty timeline
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    hasVideoClips 
                        ? 'Active' 
                        : 'Empty',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
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
