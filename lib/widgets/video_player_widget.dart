import 'dart:async';
import 'package:flipedit/src/rust/v2/flutter_bridge/api.dart';
import 'package:flipedit/utils/logger.dart';
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
  VideoEditorV2? _videoEditor;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Ensure all operations happen on the main thread
       // Get engine handle for texture rendering
       final handle = await EngineContext.instance.getEngineHandle();
       
       // Create VideoEditorV2 instance
       _videoEditor = createVideoEditorV2();
       
       // Add video file to the editor
       addVideoFileV2(editor: _videoEditor!, filePath: widget.leftVideoPath);
       
       // Setup preview with texture rendering
       final textureId = setupPreviewV2(
         editor: _videoEditor!,
         engineHandle: handle,
         width: 1920,
         height: 1080,
       );
       
       // Register with the video player service
       final videoPlayerService = di<VideoPlayerService>();
       videoPlayerService.registerVideoEditor(_videoEditor!);
       videoPlayerService.setCurrentVideoPath(widget.leftVideoPath);
       
       setState(() => _textureId = textureId);
    } catch (e) {
      setState(() => _errorMessage = "Initialization error: $e");
      logInfo("Flutter: Error in initialization: $e");
    }
  }

  @override
  void dispose() {
    // Unregister from video player service
    if (_videoEditor != null) {
      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.unregisterVideoEditor();
      // Note: VideoEditorV2 doesn't have explicit dispose method
    }
    super.dispose();
  }

  void _togglePlayPause() async {
    if (_videoEditor == null) return;
    
    try {
      final videoPlayerService = di<VideoPlayerService>();
      
      // Use the video player service state as the source of truth
      final isCurrentlyPlaying = videoPlayerService.isPlaying;
      
      logInfo("Flutter: Toggle play/pause - currently playing: $isCurrentlyPlaying");
      
      if (isCurrentlyPlaying) {
        logInfo("Flutter: Calling pausePreviewV2()");
        pausePreviewV2(editor: _videoEditor!);
        videoPlayerService.setPlayingState(false);
        logInfo("Flutter: Pause completed, state set to false");
      } else {
        logInfo("Flutter: Calling playPreviewV2()");
        playPreviewV2(editor: _videoEditor!);
        videoPlayerService.setPlayingState(true);
        logInfo("Flutter: Play completed, state set to true");
      }
    } catch (e) {
      setState(() => _errorMessage = "Playback error: $e");
      logInfo("Flutter: Error in toggle play/pause: $e");
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
