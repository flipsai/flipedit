import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_processing_service.dart';
import 'package:flipedit/services/video_texture_service.dart';
import 'package:flipedit/models/video_texture_model.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';

class TimelineProcessingService implements Disposable {
  late final VideoProcessingService _videoService;
  late final VideoTextureService _textureService;
  late final TimelineStateViewModel _timelineState;
  late final CanvasDimensionsService _canvasDimensionsService;
  
  VideoTextureModel? _textureModel;
  String? _currentTextureModelId;
  final Map<String, DateTime> _lastVideoLoad = {};
  
  TimelineProcessingService() {
    _videoService = di.get<VideoProcessingService>();
    _textureService = di.get<VideoTextureService>();
    _timelineState = di.get<TimelineStateViewModel>();
    _canvasDimensionsService = di.get<CanvasDimensionsService>();
    
    logInfo('TimelineProcessingService: Initialized');
  }
  
  /// Initialize texture model for rendering
  Future<bool> initializeTexture(String id) async {
    try {
      if (_currentTextureModelId == id && _textureModel != null) {
        return true; // Already initialized
      }
      
      // Clean up previous texture model
      if (_currentTextureModelId != null && _currentTextureModelId != id) {
        _textureService.disposeTextureModel(_currentTextureModelId!);
      }
      
      _textureModel = _textureService.createTextureModel(id);
      _currentTextureModelId = id;
      
      // Create session with single display
      await _textureModel!.createSession(id, numDisplays: 1);
      
      logInfo('TimelineProcessingService: Initialized texture model: $id');
      return true;
    } catch (e) {
      logError('TimelineProcessingService', 'Error initializing texture: $e');
      return false;
    }
  }
  
  /// Get texture ID for display
  ValueNotifier<int>? getTextureId(int display) {
    return _textureModel?.getTextureId(display);
  }
  
  /// Load all videos from timeline clips
  Future<void> loadTimelineVideos() async {
    final clips = _timelineState.clips;
    final uniqueVideoPaths = clips.map((clip) => clip.sourcePath).toSet();
    
    for (final path in uniqueVideoPaths) {
      if (path.isNotEmpty) {
        // Check if video was loaded recently (within last 5 minutes)
        final lastLoad = _lastVideoLoad[path];
        if (lastLoad != null && DateTime.now().difference(lastLoad).inMinutes < 5) {
          continue; // Skip recent loads
        }
        
        final videoId = path; // Use path as ID for simplicity
        await _videoService.loadVideo(videoId, path);
        _lastVideoLoad[path] = DateTime.now();
      }
    }
    
    logInfo('TimelineProcessingService: Loaded ${uniqueVideoPaths.length} unique videos');
  }
  
  /// Render a specific frame from the timeline
  Future<void> renderFrame(int frameIndex) async {
    if (_textureModel == null || !_textureModel!.isReady(0)) {
      logWarning('TimelineProcessingService', 'Texture not ready for rendering');
      return;
    }
    
    try {
      // Get clips at this frame
      final clips = getClipsAtFrame(frameIndex);
      
      if (clips.isEmpty) {
        // Render blank frame
        await renderBlankFrame();
        return;
      }
      
      // Get canvas dimensions
      final canvasWidth = _canvasDimensionsService.canvasWidthNotifier.value.toInt();
      final canvasHeight = _canvasDimensionsService.canvasHeightNotifier.value.toInt();
      
      List<cv.Mat> frameLayers = [];
      List<double> alphas = [];
      
      for (final clip in clips) {
        // Calculate source frame
        final sourceFrame = calculateSourceFrame(clip, frameIndex);
        
        // Get frame from video
        final videoFrame = _videoService.getVideoFrame(clip.sourcePath, sourceFrame);
        if (videoFrame == null) continue;
        
        // Convert to RGBA
        cv.Mat rgbaFrame = _videoService.convertToRGBA(videoFrame.mat);
        
        // Apply transformations based on preview position and size
        final transformParams = TransformParams(
          x: clip.previewPositionX,
          y: clip.previewPositionY,
          scale: calculateScale(clip, canvasWidth, canvasHeight),
          rotation: 0, // Add rotation if needed
        );
        
        cv.Mat transformed = _videoService.transformFrame(rgbaFrame, transformParams);
        
        frameLayers.add(transformed);
        alphas.add(1.0); // Full opacity for now
        
        // Clean up
        videoFrame.dispose();
        if (rgbaFrame != transformed) {
          rgbaFrame.dispose();
        }
      }
      
      // Composite all layers
      cv.Mat composited = _videoService.compositeFrames(
        frameLayers,
        alphas,
        canvasWidth,
        canvasHeight,
      );
      
      // Render to texture
      _textureModel!.renderFrame(
        0, // display index
        composited.dataPtr,
        composited.total * composited.elemSize,
        composited.cols,
        composited.rows,
      );
      
      // Clean up
      for (final frame in frameLayers) {
        frame.dispose();
      }
      composited.dispose();
      
    } catch (e) {
      logError('TimelineProcessingService', 'Error rendering frame $frameIndex: $e');
    }
  }
  
  /// Render a blank frame
  Future<void> renderBlankFrame() async {
    final canvasWidth = _canvasDimensionsService.canvasWidthNotifier.value.toInt();
    final canvasHeight = _canvasDimensionsService.canvasHeightNotifier.value.toInt();
    
    cv.Mat blankFrame = cv.Mat.zeros(canvasHeight, canvasWidth, cv.MatType.CV_8UC4);
    
    _textureModel!.renderFrame(
      0,
      blankFrame.dataPtr,
      blankFrame.total * blankFrame.elemSize,
      blankFrame.cols,
      blankFrame.rows,
    );
    
    blankFrame.dispose();
  }
  
  /// Get clips that are visible at a specific frame
  List<ClipModel> getClipsAtFrame(int frame) {
    return _timelineState.clips.where((clip) {
      final startFrame = msToFrame(clip.startTimeOnTrackMs, 30); // TODO: Get actual FPS
      final endFrame = msToFrame(clip.endTimeOnTrackMs, 30);
      return frame >= startFrame && frame < endFrame;
    }).toList();
  }
  
  /// Calculate source frame index for a clip at timeline frame
  int calculateSourceFrame(ClipModel clip, int timelineFrame) {
    final fps = 30.0; // TODO: Get actual FPS from timeline or clip
    final clipStartFrame = msToFrame(clip.startTimeOnTrackMs, fps);
    final sourceStartFrame = msToFrame(clip.startTimeInSourceMs, fps);
    final sourceEndFrame = msToFrame(clip.endTimeInSourceMs, fps);
    
    final frameInClip = timelineFrame - clipStartFrame;
    final sourceFrame = sourceStartFrame + frameInClip;
    
    // Clamp to source bounds
    return sourceFrame.clamp(sourceStartFrame, sourceEndFrame - 1);
  }
  
  /// Calculate scale factor for clip
  double calculateScale(ClipModel clip, int canvasWidth, int canvasHeight) {
    // Preview dimensions are relative to canvas size
    // If clip preview width is 100, it means 100% of canvas width
    final scaleX = clip.previewWidth / 100.0;
    final scaleY = clip.previewHeight / 100.0;
    return (scaleX + scaleY) / 2.0; // Average scale for now
  }
  
  /// Convert milliseconds to frame number
  int msToFrame(int ms, double fps) {
    return (ms * fps / 1000).round();
  }
  
  @override
  FutureOr onDispose() {
    dispose();
  }
  
  void dispose() {
    if (_currentTextureModelId != null) {
      _textureService.disposeTextureModel(_currentTextureModelId!);
    }
    _textureModel = null;
    logInfo('TimelineProcessingService: Disposed');
  }
}
