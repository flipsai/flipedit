import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/player/native_player_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';

class NativeVideoPlayer extends StatelessWidget with WatchItMixin {
  final bool showControls;
  
  const NativeVideoPlayer({
    super.key,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    final isInitialized = watchValue((NativePlayerViewModel vm) => vm.isInitializedNotifier);
    final textureId = watchValue((NativePlayerViewModel vm) => vm.textureIdNotifier);
    final status = watchValue((NativePlayerViewModel vm) => vm.statusNotifier);
    final isRendering = watchValue((NativePlayerViewModel vm) => vm.isRenderingNotifier);
    
    // Get canvas dimensions for aspect ratio
    final canvasWidth = watchValue((CanvasDimensionsService svc) => svc.canvasWidthNotifier);
    final canvasHeight = watchValue((CanvasDimensionsService svc) => svc.canvasHeightNotifier);
    final aspectRatio = canvasWidth > 0 && canvasHeight > 0 
        ? canvasWidth / canvasHeight 
        : 16 / 9; // Default aspect ratio
    
    Widget content;
    
    if (!isInitialized || textureId == null || textureId == -1) {
      // Show loading/status
      content = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              status,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      // Show texture
      content = Stack(
        children: [
          // Video texture
          Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Texture(textureId: textureId),
            ),
          ),
          
          // Rendering indicator (optional)
          if (isRendering && showControls)
            const Positioned(
              top: 8,
              right: 8,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          
          // Controls overlay (if enabled)
          if (showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _PlayerControls(),
            ),
        ],
      );
    }
    
    return Container(
      color: Colors.black,
      child: content,
    );
  }
}

class _PlayerControls extends StatelessWidget with WatchItMixin {
  const _PlayerControls();

  @override
  Widget build(BuildContext context) {
    // Get the timeline navigation viewmodel directly
    final timelineNavViewModel = di.get<TimelineNavigationViewModel>();
    
    // Watch playback state
    final isPlaying = watchValue((TimelineNavigationViewModel vm) => vm.isPlayingNotifier);
    final currentFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    final totalFrames = watchValue((TimelineNavigationViewModel vm) => vm.totalFramesNotifier);
    
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Play/Pause button
            IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () {
                if (isPlaying) {
                  timelineNavViewModel.stopPlayback();
                } else {
                  timelineNavViewModel.startPlayback();
                }
              },
            ),
            
            const SizedBox(width: 8),
            
            // Frame counter
            SizedBox(
              width: 100,
              child: Text(
                '$currentFrame / $totalFrames',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            
            // Timeline slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbColor: Colors.white,
                  activeTrackColor: Colors.blue,
                  inactiveTrackColor: Colors.grey[700],
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: currentFrame.toDouble(),
                  min: 0,
                  max: totalFrames > 0 ? totalFrames.toDouble() : 1,
                  onChanged: totalFrames > 0 ? (value) {
                    // Set current frame directly
                    timelineNavViewModel.currentFrame = value.toInt();
                  } : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
