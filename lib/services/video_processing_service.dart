import 'dart:async';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

class VideoFrame {
  final cv.Mat mat;
  final int width;
  final int height;
  final int frameIndex;
  
  VideoFrame({
    required this.mat,
    required this.width,
    required this.height,
    required this.frameIndex,
  });
  
  void dispose() {
    mat.dispose();
  }
}

class VideoProcessingService implements Disposable {
  final Map<String, cv.VideoCapture> _videoCaptures = {};
  final Map<String, VideoInfo> _videoInfoCache = {};
  
  VideoProcessingService() {
    logInfo('VideoProcessingService: Initialized');
  }
  
  /// Load a video file and cache its capture
  Future<bool> loadVideo(String id, String path) async {
    try {
      // Release existing capture if any
      _videoCaptures[id]?.release();
      
      final capture = cv.VideoCapture.fromFile(path);
      if (!capture.isOpened) {
        logError('VideoProcessingService', 'Failed to open video: $path');
        return false;
      }
      
      _videoCaptures[id] = capture;
      
      // Cache video info
      final info = VideoInfo(
        frameCount: capture.get(cv.CAP_PROP_FRAME_COUNT).toInt(),
        fps: capture.get(cv.CAP_PROP_FPS),
        width: capture.get(cv.CAP_PROP_FRAME_WIDTH).toInt(),
        height: capture.get(cv.CAP_PROP_FRAME_HEIGHT).toInt(),
      );
      _videoInfoCache[id] = info;
      
      logInfo('VideoProcessingService: Loaded video $id from $path');
      return true;
    } catch (e) {
      logError('VideoProcessingService', 'Error loading video $id: $e');
      return false;
    }
  }
  
  /// Get a specific frame from a video
  VideoFrame? getVideoFrame(String videoId, int frameIndex) {
    final capture = _videoCaptures[videoId];
    if (capture == null) {
      logError('VideoProcessingService', 'Video not loaded: $videoId');
      return null;
    }
    
    // Check if frame index is valid
    final info = _videoInfoCache[videoId];
    if (info != null && (frameIndex < 0 || frameIndex >= info.frameCount)) {
      logWarning('VideoProcessingService', 'Frame index $frameIndex out of bounds for video $videoId (0-${info.frameCount - 1})');
      return null;
    }
    
    try {
      // Check current position to avoid unnecessary seeking
      final currentPos = capture.get(cv.CAP_PROP_POS_FRAMES).toInt();
      if (currentPos != frameIndex) {
        capture.set(cv.CAP_PROP_POS_FRAMES, frameIndex.toDouble());
      }
      
      final result = capture.read();
      
      if (!result.$1) {
        logWarning('VideoProcessingService', 'Failed to read frame $frameIndex from video $videoId');
        return null;
      }
      
      final mat = result.$2;
      if (mat.isEmpty) {
        logWarning('VideoProcessingService', 'Empty frame at index $frameIndex from video $videoId');
        mat.dispose();
        return null;
      }
      
      return VideoFrame(
        mat: mat,
        width: mat.cols,
        height: mat.rows,
        frameIndex: frameIndex,
      );
    } catch (e) {
      logError('VideoProcessingService', 'Error getting frame $frameIndex from video $videoId: $e');
      return null;
    }
  }
  
  /// Apply transformation to a frame
  cv.Mat transformFrame(cv.Mat frame, TransformParams params) {
    try {
      final centerX = frame.cols / 2;
      final centerY = frame.rows / 2;
      
      // Create transformation matrix
      final transform = cv.getRotationMatrix2D(
        cv.Point2f(centerX, centerY),
        params.rotation,
        params.scale,
      );
      
      // Adjust for position
      final dx = params.x - centerX + centerX * params.scale;
      final dy = params.y - centerY + centerY * params.scale;
      
      // Set the translation part of the transformation matrix
      final currentX = transform.at<double>(0, 2);
      final currentY = transform.at<double>(1, 2);
      transform.set<double>(0, 2, currentX + dx);
      transform.set<double>(1, 2, currentY + dy);
      
      final result = cv.warpAffine(
        frame,
        transform,
        (frame.cols, frame.rows),
        flags: cv.INTER_LINEAR,
        borderMode: cv.BORDER_CONSTANT,
        borderValue: cv.Scalar(0, 0, 0, 0),
      );
      
      transform.dispose();
      return result;
    } catch (e) {
      logError('VideoProcessingService', 'Error transforming frame: $e');
      return frame.clone();
    }
  }
  
  /// Composite multiple frames into one
  cv.Mat compositeFrames(List<cv.Mat> frames, List<double> alphas, int canvasWidth, int canvasHeight) {
    if (frames.isEmpty) {
      return cv.Mat.zeros(canvasHeight, canvasWidth, cv.MatType.CV_8UC4);
    }
    
    try {
      // Start with a blank canvas
      cv.Mat result = cv.Mat.zeros(canvasHeight, canvasWidth, cv.MatType.CV_8UC4);
      
      for (int i = 0; i < frames.length; i++) {
        try {
          final frame = frames[i];
          final alpha = i < alphas.length ? alphas[i] : 1.0;
          
          // Validate frame
          if (frame.isEmpty) {
            logWarning('VideoProcessingService', 'Empty frame at index $i, skipping');
            continue;
          }
          
          // Ensure frame has correct number of channels (4 for RGBA)
          cv.Mat frameToUse;
          if (frame.channels != 4) {
            logInfo('VideoProcessingService', 'Converting frame from ${frame.channels} channels to 4 channels');
            if (frame.channels == 3) {
              frameToUse = cv.cvtColor(frame, cv.COLOR_BGR2RGBA);
            } else if (frame.channels == 1) {
              frameToUse = cv.cvtColor(frame, cv.COLOR_GRAY2RGBA);
            } else {
              logWarning('VideoProcessingService', 'Unsupported channel count: ${frame.channels}, skipping frame');
              continue;
            }
          } else {
            frameToUse = frame;
          }
          
          // Always resize frame to match canvas dimensions
          cv.Mat resized;
          if (frameToUse.cols != canvasWidth || frameToUse.rows != canvasHeight) {
            logInfo('VideoProcessingService', 'Resizing frame from ${frameToUse.cols}x${frameToUse.rows} to ${canvasWidth}x${canvasHeight}');
            resized = cv.resize(frameToUse, (canvasWidth, canvasHeight));
          } else {
            resized = frameToUse.clone();
          }
          
          // Add weighted with size validation
          if (resized.cols == result.cols && resized.rows == result.rows &&
              resized.channels == result.channels) {
            cv.addWeighted(result, 1.0 - alpha, resized, alpha, 0, dst: result);
          } else {
            logWarning('VideoProcessingService',
              'Size mismatch: result=${result.cols}x${result.rows}x${result.channels}, ' +
              'frame=${resized.cols}x${resized.rows}x${resized.channels}, skipping frame');
          }
          
          // Clean up
          if (frameToUse != frame) {
            frameToUse.dispose();
          }
          resized.dispose();
        } catch (frameError) {
          logError('VideoProcessingService', 'Error processing frame $i: $frameError');
          // Continue with next frame
        }
      }
      
      return result;
    } catch (e) {
      logError('VideoProcessingService', 'Error compositing frames: $e');
      return cv.Mat.zeros(canvasHeight, canvasWidth, cv.MatType.CV_8UC4);
    }
  }
  
  /// Convert frame to RGBA format for texture rendering
  cv.Mat convertToRGBA(cv.Mat frame) {
    try {
      if (frame.channels == 4) {
        return frame.clone();
      } else if (frame.channels == 3) {
        return cv.cvtColor(frame, cv.COLOR_BGR2RGBA);
      } else {
        logWarning('VideoProcessingService', 'Unexpected channel count: ${frame.channels}');
        return frame.clone();
      }
    } catch (e) {
      logError('VideoProcessingService', 'Error converting to RGBA: $e');
      return frame.clone();
    }
  }
  
  /// Get video information
  VideoInfo? getVideoInfo(String videoId) {
    return _videoInfoCache[videoId];
  }
  
  /// Check if a video is loaded
  bool isVideoLoaded(String videoId) {
    final capture = _videoCaptures[videoId];
    return capture != null && capture.isOpened;
  }
  
  /// Release a video capture
  void releaseVideo(String videoId) {
    _videoCaptures[videoId]?.release();
    _videoCaptures.remove(videoId);
    _videoInfoCache.remove(videoId);
    logInfo('VideoProcessingService: Released video $videoId');
  }
  
  @override
  FutureOr onDispose() {
    dispose();
  }
  
  void dispose() {
    for (final capture in _videoCaptures.values) {
      capture.release();
    }
    _videoCaptures.clear();
    _videoInfoCache.clear();
    logInfo('VideoProcessingService: Disposed');
  }
}

class VideoInfo {
  final int frameCount;
  final double fps;
  final int width;
  final int height;
  
  VideoInfo({
    required this.frameCount,
    required this.fps,
    required this.width,
    required this.height,
  });
  
  int get durationMs => fps > 0 ? (frameCount / fps * 1000).toInt() : 0;
}

class TransformParams {
  final double x;
  final double y;
  final double scale;
  final double rotation;
  
  const TransformParams({
    required this.x,
    required this.y,
    required this.scale,
    this.rotation = 0,
  });
}
