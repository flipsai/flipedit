import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/player/opencv_python_player_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';

class PythonPlayerPanel extends StatelessWidget with WatchItMixin {
  const PythonPlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    logDebug('Building PythonPlayerPanel', 'PythonPlayerPanel');
    
    // Use watch() to get the viewmodels from DI
    final playerViewModel = di<OpenCvPythonPlayerViewModel>();
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    
    // Use watchValue() for reactive properties
    final textureId = watchValue((OpenCvPythonPlayerViewModel vm) => vm.textureIdNotifier);
    final isReady = watchValue((OpenCvPythonPlayerViewModel vm) => vm.isReadyNotifier);
    final status = watchValue((OpenCvPythonPlayerViewModel vm) => vm.statusNotifier);
    final fps = watchValue((OpenCvPythonPlayerViewModel vm) => vm.fpsNotifier);
    final isPlaying = watchValue((TimelineNavigationViewModel vm) => vm.isPlayingNotifier);
    final currentFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    
    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area
          Expanded(
            child: Center(
              child: textureId != -1
                  ? Container(
                      color: Colors.blue.withOpacity(0.2),
                      width: double.infinity,
                      height: double.infinity,
                      child: Stack(
                        children: [
                          // Texture widget with explicit size
                          Positioned.fill(
                            child: material.Texture(
                              textureId: textureId,
                              filterQuality: material.FilterQuality.high,
                            ),
                          ),
                          
                          // Debug overlay to show texture ID
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              color: Colors.black.withOpacity(0.5),
                              child: Text(
                                'Texture ID: $textureId',
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                              ),
                            ),
                          ),
                          
                          // If Python connection is in progress or failed, show an overlay
                          if (!isReady)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(0.7),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const ProgressRing(),
                                      const SizedBox(height: 16),
                                      Text(
                                        status,
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const Center(
                      child: ProgressRing(),
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
                  onPressed: () {
                    if (isPlaying) {
                      timelineNavViewModel.stopPlayback();
                    } else {
                      timelineNavViewModel.startPlayback();
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
                  'Python OpenCV Renderer',
                  style: FluentTheme.of(context).typography.caption,
                ),
                
                const SizedBox(width: 8),
                
                // FPS counter
                Text('$fps FPS'),
                
                const SizedBox(width: 8),
                
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.green : Colors.yellow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isReady ? 'Ready' : status,
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