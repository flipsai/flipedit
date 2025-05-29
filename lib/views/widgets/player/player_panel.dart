import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/widgets/video_player_widget.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineViewModel _timelineViewModel;
  String? _currentVideoPath;

  @override
  void initState() {
    super.initState();
    logDebug("Initializing PlayerPanel...", 'PlayerPanel');

    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineViewModel = di<TimelineViewModel>();

    // Add listener to rebuild on state changes
    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.addListener(_onFrameChanged);
    _timelineViewModel.clipsNotifier.addListener(_updateCurrentVideo);
    
    // Initial video update
    _updateCurrentVideo();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  
  void _onFrameChanged() {
    _updateCurrentVideo();
    _rebuild();
  }
  
  void _updateCurrentVideo() {
    // Get the clip at the current frame position
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
    final clips = _timelineViewModel.clipsNotifier.value;
    
    // Find the clip that contains the current frame
    for (final clip in clips) {
      if (clip.type == ClipType.video && 
          clip.startFrame <= currentFrame && 
          currentFrame < clip.startFrame + clip.durationFrames) {
        // Found the current clip
        if (_currentVideoPath != clip.sourcePath) {
          setState(() {
            _currentVideoPath = clip.sourcePath;
          });
        }
        return;
      }
    }
    
    // No video clip at current position
    if (_currentVideoPath != null) {
      setState(() {
        _currentVideoPath = null;
      });
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _timelineNavViewModel.isPlayingNotifier.removeListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_onFrameChanged);
    _timelineViewModel.clipsNotifier.removeListener(_updateCurrentVideo);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area
          Expanded(
            child: _currentVideoPath != null
                ? VideoPlayerWidget(videoPath: _currentVideoPath!)
                : const Center(
                    child: Text(
                      'No video loaded',
                      style: TextStyle(color: Colors.white),
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
                  onPressed: () async {
                    try {
                      if (isPlaying) {
                        _timelineNavViewModel.stopPlayback();
                      } else {
                        await _timelineNavViewModel.startPlayback();
                      }
                    } catch (e) {
                      logError('PlayerPanel', 'Error toggling playback: $e');
                    }
                  },
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
                  'GStreamer Video Player',
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
                    color: _currentVideoPath != null ? Colors.green : Colors.yellow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _currentVideoPath != null ? 'Ready' : 'No Video',
                    style: FluentTheme.of(context).typography.caption,
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
