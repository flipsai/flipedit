import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:io';

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
  
  // Fixed video path - using equipe.mp4
  static const String _fixedVideoPath = '/Users/remymenard/Downloads/equipe.mp4';

  @override
  void initState() {
    super.initState();
    
    logDebug("Initializing PlayerPanel with fixed video: $_fixedVideoPath", 'PlayerPanel');

    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineViewModel = di<TimelineViewModel>();

    // Keep listeners for the play/pause controls but don't use them for video selection
    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.addListener(_rebuild);
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
    _timelineNavViewModel.currentFrameNotifier.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel with fixed video...", 'PlayerPanel');

    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area - always shows the fixed video
          Expanded(
            child: File(_fixedVideoPath).existsSync()
                ? VideoPlayerWidget(videoPath: _fixedVideoPath)
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
                            'equipe.mp4 not found',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Place equipe.mp4 at:\n$_fixedVideoPath',
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

                // Mode label - updated to indicate fixed video mode
                Text(
                  'Fixed Video Player (equipe.mp4)',
                  style: FluentTheme.of(context).typography.caption,
                ),

                const SizedBox(width: 8),

                // Status indicator - shows different colors based on video availability
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: File(_fixedVideoPath).existsSync() 
                        ? Colors.blue // Blue for fixed video mode with valid file
                        : Colors.orange, // Orange for missing video file
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    File(_fixedVideoPath).existsSync() 
                        ? 'equipe.mp4' 
                        : 'Missing',
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
