import 'package:fluent_ui/fluent_ui.dart';
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
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineStateViewModel _timelineStateViewModel;
  late final VideoPlayerService _videoPlayerService;
  String? _cachedVideoPath; // Cache the video path to prevent unnecessary recreation

  @override
  void initState() {
    super.initState();
    
    logDebug("Initializing PlayerPanel", 'PlayerPanel');

    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineStateViewModel = di<TimelineStateViewModel>();
    _videoPlayerService = di<VideoPlayerService>();

    // Listen for changes to rebuild UI
    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.addListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.addListener(_rebuild);
    _videoPlayerService.isPlayingNotifier.addListener(_rebuild);
    
    // Initialize cached video path
    _cachedVideoPath = _getFirstVideoPath();
  }

  void _rebuild() {
    if (mounted) {
      // Only update cached video path when clips change
      final newVideoPath = _getFirstVideoPath();
      if (newVideoPath != _cachedVideoPath) {
        logDebug("Video path changed from $_cachedVideoPath to $newVideoPath", 'PlayerPanel');
        _cachedVideoPath = newVideoPath;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _timelineNavViewModel.isPlayingNotifier.removeListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_rebuild);
    _timelineStateViewModel.clipsNotifier.removeListener(_rebuild);
    _videoPlayerService.isPlayingNotifier.removeListener(_rebuild);
    super.dispose();
  }

  String? _getFirstVideoPath() {
    final clips = _timelineStateViewModel.clips;
    if (clips.isEmpty) {
      return null;
    }
    
    // Find first video clip
    for (final clip in clips) {
      if (clip.sourcePath.isNotEmpty && File(clip.sourcePath).existsSync()) {
        logDebug("Using first video: ${clip.sourcePath}", 'PlayerPanel');
        return clip.sourcePath;
      }
    }
    
    logDebug("No valid video files found in clips", 'PlayerPanel');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isTimelinePlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final isVideoPlaying = _videoPlayerService.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
    final clips = _timelineStateViewModel.clips;
    final firstVideoPath = _cachedVideoPath;

    logDebug("Rebuilding PlayerPanel - ${clips.length} clips, first video: $firstVideoPath, timeline playing: $isTimelinePlaying, video playing: $isVideoPlaying", 'PlayerPanel');

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area
          Expanded(
            child: firstVideoPath != null
                ? VideoPlayerWidget(
                    key: ValueKey(firstVideoPath), // Prevent recreation during resizes
                    videoPath: firstVideoPath,
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
                                : 'Check that video files exist:\n${clips.map((c) => c.sourcePath).join('\n')}',
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

                // Current video info
                if (firstVideoPath != null)
                  Flexible(
                    child: Text(
                      'Playing: ${firstVideoPath.split('/').last}',
                      style: FluentTheme.of(context).typography.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(width: 8),

                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: firstVideoPath != null ? Colors.green : 
                           clips.isNotEmpty ? Colors.orange : Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    firstVideoPath != null ? 'Video Ready' : 
                    clips.isNotEmpty ? 'No Valid Videos' : 'No Clips',
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
