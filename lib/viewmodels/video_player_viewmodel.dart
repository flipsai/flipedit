import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerViewModel {
  final String leftVideoPath;
  final String? rightVideoPath;

  VideoPlayer? _videoPlayer;
  final ValueNotifier<int?> textureIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);

  // Convenient getters
  int? get textureId => textureIdNotifier.value;
  String? get errorMessage => errorMessageNotifier.value;

  VideoPlayerViewModel({
    required this.leftVideoPath,
    this.rightVideoPath,
  }) {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Acquire Flutter engine handle for zero-copy texture rendering
      final handle = await EngineContext.instance.getEngineHandle();

      // Create texture via Rust API
      final textureId = createVideoTexture(
        width: 1920,
        height: 1080,
        engineHandle: handle,
      );

      // Instantiate video player (Rust side)
      _videoPlayer = VideoPlayer();
      _videoPlayer!.setTexturePtr(ptr: textureId);

      // Load primary video (left)
      await _videoPlayer!.loadVideo(filePath: leftVideoPath);

      // Register player with service for shared state / seeking
      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.registerVideoPlayer(_videoPlayer!);
      videoPlayerService.setCurrentVideoPath(leftVideoPath);

      textureIdNotifier.value = textureId;
    } catch (e) {
      final errMsg = "Failed to initialize video player: $e";
      errorMessageNotifier.value = errMsg;
      logError('VideoPlayerViewModel', errMsg);
    }
  }

  Future<void> togglePlayPause() async {
    if (_videoPlayer == null) return;

    try {
      final videoPlayerService = di<VideoPlayerService>();
      final isPlaying = videoPlayerService.isPlaying;
      logInfo('Toggle play/pause – currently playing: $isPlaying', 'VideoPlayerViewModel');

      if (isPlaying) {
        await _videoPlayer!.pause();
        videoPlayerService.setPlayingState(false);
      } else {
        await _videoPlayer!.play();
        videoPlayerService.setPlayingState(true);
      }
    } catch (e) {
      final errMsg = "Playback error: $e";
      errorMessageNotifier.value = errMsg;
      logError('VideoPlayerViewModel', errMsg);
    }
  }

  void dispose() {
    final videoPlayerService = di<VideoPlayerService>();
    videoPlayerService.unregisterVideoPlayer();
    _videoPlayer?.dispose();
    textureIdNotifier.dispose();
    errorMessageNotifier.dispose();
  }
} 