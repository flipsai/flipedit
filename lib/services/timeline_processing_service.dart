import 'dart:async';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/video_processing_service.dart' as video_service;
import 'package:flipedit/utils/logger.dart';

// We use the VideoInfo from the video_processing_service
typedef VideoInfo = video_service.VideoInfo;

// A simplified timeline processing service that works with our Python backend
class TimelineProcessingService {
  String get _logTag => runtimeType.toString();
  
  final video_service.VideoProcessingService _videoService;
  
  // Video processing state
  final Map<String, VideoInfo> _videoInfoCache = {};
  
  TimelineProcessingService({
    video_service.VideoProcessingService? videoService,
  }) : _videoService = videoService ?? video_service.VideoProcessingService();
  
  // Initialize and load videos for a list of clips
  Future<void> initializeWithClips(List<ClipModel> clips) async {
    logInfo(_logTag, 'Initializing with ${clips.length} clips');
    
    final uniquePaths = <String>{};
    
    // Collect unique video paths
    for (final clip in clips) {
      if (clip.sourcePath.isNotEmpty) {
        uniquePaths.add(clip.sourcePath);
      }
    }
    
    // Load all unique videos
    for (final path in uniquePaths) {
      try {
        if (!_videoService.isVideoLoaded(path)) {
          final info = await _videoService.loadVideo(path, path);
          _videoInfoCache[path] = info;
          logInfo(_logTag, 'Loaded video: $path');
        }
      } catch (e, stackTrace) {
        logError(_logTag, 'Error loading video $path: $e', stackTrace);
      }
    }
  }
  
  // Load a specific video
  Future<VideoInfo?> loadVideo(String path) async {
    try {
      final info = await _videoService.loadVideo(path, path);
      _videoInfoCache[path] = info;
      return info;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error loading video $path: $e', stackTrace);
      return null;
    }
  }
  
  // Get the duration of a video clip in milliseconds
  int getClipDurationMs(ClipModel clip) {
    if (clip.endTimeInSourceMs <= clip.startTimeInSourceMs) {
      return 0;
    }
    
    return clip.endTimeInSourceMs - clip.startTimeInSourceMs;
  }
  
  // Convert a timeline frame to a source frame for a clip
  int timelineToSourceFrame(ClipModel clip, int timelineFrame, int fps) {
    // Default to 30fps if not specified
    final framerate = fps > 0 ? fps : 30;
    
    // Calculate time on timeline in milliseconds
    final clipStartFrameOnTimeline = (clip.startTimeOnTrackMs / 1000 * framerate).floor();
    final frameOffsetInClip = timelineFrame - clipStartFrameOnTimeline;
    
    if (frameOffsetInClip < 0) {
      return 0; // Before clip start
    }
    
    // Convert to milliseconds in source
    final msInSource = clip.startTimeInSourceMs + (frameOffsetInClip / framerate * 1000).floor();
    
    // Convert to frame in source
    return (msInSource / 1000 * framerate).floor();
  }
  
  // Check if timeline frame is within a clip
  bool isFrameInClip(ClipModel clip, int timelineFrame, int fps) {
    final framerate = fps > 0 ? fps : 30;
    
    // Calculate clip bounds in frames
    final clipStartFrame = (clip.startTimeOnTrackMs / 1000 * framerate).floor();
    final clipDurationFrames = (getClipDurationMs(clip) / 1000 * framerate).ceil();
    final clipEndFrame = clipStartFrame + clipDurationFrames;
    
    return timelineFrame >= clipStartFrame && timelineFrame < clipEndFrame;
  }
  
  // Get information about a frame (simpler version for Python backend)
  Future<video_service.FrameInfo?> getFrameInfo(String videoPath, int frameIndex) async {
    try {
      return await _videoService.getFrame(videoPath, frameIndex);
    } catch (e, stackTrace) {
      logError(_logTag, 'Error getting frame info: $e', stackTrace);
      return null;
    }
  }
  
  // Generate a blank frame with given dimensions
  video_service.FrameInfo getBlankFrame(int width, int height) {
    return video_service.FrameInfo(
      width: width,
      height: height,
    );
  }
  
  // Clean up resources
  void dispose() {
    _videoService.dispose();
    _videoInfoCache.clear();
  }
}
