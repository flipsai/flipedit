import 'dart:async';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flutter/material.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatefulWidget with WatchItStatefulWidgetMixin {
  final String leftVideoPath;
  final String rightVideoPath;

  const VideoPlayerWidget({
    super.key,
    required this.leftVideoPath,
    required this.rightVideoPath,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  int? _textureId;
  String? _errorMessage;
  VideoPlayer? _videoPlayer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Get engine handle for texture rendering
      final handle = await EngineContext.instance.getEngineHandle();
      
      // Create texture for video rendering
      final textureId = createVideoTexture(
        width: 1920, 
        height: 1080, 
        engineHandle: handle,
      );
      
      // Create a VideoPlayer instance for proper play/pause control
      _videoPlayer = VideoPlayer();
      
      // Set texture pointer for the video player
      _videoPlayer!.setTexturePtr(ptr: textureId);
      
      // Load the left video (for now, we'll focus on single video functionality)
      await _videoPlayer!.loadVideo(filePath: widget.leftVideoPath);
      
      // Register with the video player service for position updates
      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.registerVideoPlayer(_videoPlayer!);
      videoPlayerService.setCurrentVideoPath(widget.leftVideoPath);
      
      setState(() => _textureId = textureId);
    } catch (e) {
      setState(() => _errorMessage = "Failed to initialize video player: $e");
    }
  }

  @override
  void dispose() {
    // Unregister from video player service
    if (_videoPlayer != null) {
      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.unregisterVideoPlayer();
      _videoPlayer!.dispose();
    }
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_videoPlayer == null) return;
    
    try {
      final videoPlayerService = di<VideoPlayerService>();
      
      // Use the video player service state as the source of truth
      final isCurrentlyPlaying = videoPlayerService.isPlaying;
      
      print("Flutter: Toggle play/pause - currently playing: $isCurrentlyPlaying");
      
      if (isCurrentlyPlaying) {
        print("Flutter: Calling pause()");
        await _videoPlayer!.pause();
        videoPlayerService.setPlayingState(false);
        print("Flutter: Pause completed, state set to false");
      } else {
        print("Flutter: Calling play()");
        await _videoPlayer!.play();
        videoPlayerService.setPlayingState(true);
        print("Flutter: Play completed, state set to true");
      }
    } catch (e) {
      setState(() => _errorMessage = "Playback error: $e");
      print("Flutter: Error in toggle play/pause: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Error: $_errorMessage'),
          ],
        ),
      );
    }

    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Get the video player service using watch_it
    final videoPlayerService = di<VideoPlayerService>();
    
    return Column(
      children: [
        Expanded(
          child: Texture(textureId: _textureId!),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: videoPlayerService.isPlayingNotifier,
              builder: (context, isPlaying, child) {
                return IconButton(
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlayPause,
                );
              },
            ),
            const SizedBox(width: 16),
            // Display position information
            ValueListenableBuilder<double>(
              valueListenable: videoPlayerService.positionSecondsNotifier,
              builder: (context, position, child) {
                final minutes = (position ~/ 60).toString().padLeft(2, '0');
                final seconds = (position % 60).toInt().toString().padLeft(2, '0');
                return Text(
                  '$minutes:$seconds',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
