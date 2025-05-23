import 'dart:async';

import 'package:flipedit/utils/logger.dart';

// Simple struct to hold basic frame info
class FrameInfo {
  final int width;
  final int height;

  FrameInfo({required this.width, required this.height});
}

// VideoInfo holds metadata about a video
class VideoInfo {
  final String path;
  final int frameCount;
  final double fps;
  final int width;
  final int height;
  final Duration duration;

  VideoInfo({
    required this.path,
    required this.frameCount,
    required this.fps,
    required this.width,
    required this.height,
  }) : duration = Duration(milliseconds: (frameCount / fps * 1000).round());
}

// TransformParams for frame transformations
class TransformParams {
  final double scale;
  final double rotation;
  final double offsetX;
  final double offsetY;

  TransformParams({
    this.scale = 1.0,
    this.rotation = 0.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
  });
}

// VideoProcessingService - simplified for Python backend
class VideoProcessingService {
  String get _logTag => runtimeType.toString();

  final Map<String, VideoInfo> _videoInfos = {};

  // Load a video - now just stores metadata
  Future<VideoInfo> loadVideo(String id, String path) async {
    if (_videoInfos.containsKey(id)) {
      return _videoInfos[id]!;
    }

    try {
      // In our Python implementation, the actual video processing happens in Python,
      // so we only need to create a placeholder VideoInfo here

      // These values would normally come from the video but we provide defaults
      // The real processing will be handled by the Python backend
      final videoInfo = VideoInfo(
        path: path,
        frameCount: 300, // Default placeholder
        fps: 30,
        width: 1920,
        height: 1080,
      );

      _videoInfos[id] = videoInfo;
      logInfo(_logTag, 'Loaded video info: $path');

      return videoInfo;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error loading video: $e', stackTrace);
      rethrow;
    }
  }

  bool isVideoLoaded(String id) {
    return _videoInfos.containsKey(id);
  }

  // Unload a video
  void unloadVideo(String id) {
    if (_videoInfos.containsKey(id)) {
      _videoInfos.remove(id);
      logInfo(_logTag, 'Unloaded video: $id');
    }
  }

  // Get frame - this will be handled by Python so we only provide info
  Future<FrameInfo> getFrame(String videoId, int frameIndex) async {
    try {
      final videoInfo = _videoInfos[videoId];
      if (videoInfo == null) {
        throw Exception('Video not loaded: $videoId');
      }

      // Return frame info only - the actual frame will be handled by Python
      return FrameInfo(width: videoInfo.width, height: videoInfo.height);
    } catch (e, stackTrace) {
      logError(_logTag, 'Error getting frame: $e', stackTrace);
      rethrow;
    }
  }

  // Clean up resources
  void dispose() {
    _videoInfos.clear();
  }
}
