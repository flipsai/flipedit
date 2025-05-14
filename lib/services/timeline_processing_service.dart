import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_texture_service.dart';
import 'package:flipedit/models/video_texture_model.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

class TimelineProcessingService implements Disposable {
  late final VideoTextureService _textureService;
  late final TimelineStateViewModel _timelineState;
  
  VideoTextureModel? _textureModel;
  String? _currentTextureModelId;
  
  final Map<String, cv.VideoCapture> _videoCaptures = {};
  final Map<String, VideoInfo> _videoInfoCache = {};
  
  ClipModel? _currentClip;
  cv.VideoCapture? _currentCapture;
  int _lastRenderedFrame = -1;
  
  TimelineProcessingService() {
    _textureService = di.get<VideoTextureService>();
    _timelineState = di.get<TimelineStateViewModel>();
    logInfo('TimelineProcessingService: Initialized');
  }
  
  Future<bool> initializeTexture(String id) async {
    logInfo('TimelineProcessingService: Initializing texture model: $id');
    try {
      if (_currentTextureModelId == id && _textureModel != null) {
        logInfo('TimelineProcessingService: Reusing existing texture model: $id');
        return true;
      }
      
      if (_currentTextureModelId != null && _currentTextureModelId != id) {
        logInfo('TimelineProcessingService: Disposing previous texture model: $_currentTextureModelId');
        _textureService.disposeTextureModel(_currentTextureModelId!);
      }
      
      logInfo('TimelineProcessingService: Creating new texture model: $id');
      _textureModel = _textureService.createTextureModel(id);
      _currentTextureModelId = id;
      
      logInfo('TimelineProcessingService: Creating session for texture model: $id');
      await _textureModel!.createSession(id, numDisplays: 1);
      
      logInfo('TimelineProcessingService: Successfully initialized texture model: $id');
      return true;
    } catch (e, stack) {
      logError('TimelineProcessingService', 'Error initializing texture: $e', stack);
      return false;
    }
  }
  
  ValueNotifier<int>? getTextureId(int display) {
    return _textureModel?.getTextureId(display);
  }
  
  Future<void> loadTimelineVideos() async {
    final clips = _timelineState.clips;
    
    for (final clip in clips) {
      if (clip.sourcePath.isNotEmpty) {
        await _loadVideo(clip.sourcePath);
      }
    }
    logInfo('TimelineProcessingService: Loaded ${clips.length} videos');
  }
  
  Future<bool> _loadVideo(String path) async {
    try {
      if (_videoCaptures.containsKey(path)) {
        return true; // Already loaded
      }
      
      final capture = cv.VideoCapture.fromFile(path);
      if (!capture.isOpened) {
        logError('TimelineProcessingService', 'Failed to open video: $path');
        return false;
      }
      
      _videoCaptures[path] = capture;
      
      final info = VideoInfo(
        frameCount: capture.get(cv.CAP_PROP_FRAME_COUNT).toInt(),
        fps: capture.get(cv.CAP_PROP_FPS),
        width: capture.get(cv.CAP_PROP_FRAME_WIDTH).toInt(),
        height: capture.get(cv.CAP_PROP_FRAME_HEIGHT).toInt(),
      );
      _videoInfoCache[path] = info;
      
      logInfo('TimelineProcessingService: Loaded video from $path');
      return true;
    } catch (e) {
      logError('TimelineProcessingService', 'Error loading video $path: $e');
      return false;
    }
  }
  
  Future<void> renderFrame(int frameIndex) async {
    if (_textureModel == null || !_textureModel!.isReady(0)) {
      // logWarning('TimelineProcessingService', 'Texture model not ready for rendering frame $frameIndex');
      return;
    }

    final overallStartTime = DateTime.now().microsecondsSinceEpoch;
    int getClipTime = 0, calculateSourceFrameTime = 0, setFrameTime = 0, readFrameTime = 0, cvtColorTime = 0, textureRenderTime = 0;

    try {
      final getClipStart = DateTime.now().microsecondsSinceEpoch;
      final clip = _getClipAtFrame(frameIndex);
      getClipTime = DateTime.now().microsecondsSinceEpoch - getClipStart;
      
      if (clip == null) {
        // logDebug('TimelineProcessingService', 'No clip at frame $frameIndex, rendering blank.');
        await _renderBlankFrame();
        _lastRenderedFrame = frameIndex; 
        return;
      }
      
      if (_currentClip?.sourcePath != clip.sourcePath) {
        _currentClip = clip;
        _currentCapture = _videoCaptures[clip.sourcePath];
      }
      
      if (_currentCapture == null || !_currentCapture!.isOpened) {
        logWarning('TimelineProcessingService', 'Current capture for clip ${clip.sourcePath} is null or not open. Rendering blank.');
        await _renderBlankFrame();
        _lastRenderedFrame = frameIndex;
        return;
      }
      
      final calculateSourceFrameStart = DateTime.now().microsecondsSinceEpoch;
      final sourceFrame = _calculateSourceFrame(clip, frameIndex);
      calculateSourceFrameTime = DateTime.now().microsecondsSinceEpoch - calculateSourceFrameStart;
      
      final setFrameStart = DateTime.now().microsecondsSinceEpoch;
      _currentCapture!.set(cv.CAP_PROP_POS_FRAMES, sourceFrame.toDouble());
      setFrameTime = DateTime.now().microsecondsSinceEpoch - setFrameStart;
      
      final readFrameStart = DateTime.now().microsecondsSinceEpoch;
      final result = _currentCapture!.read();
      readFrameTime = DateTime.now().microsecondsSinceEpoch - readFrameStart;
      
      if (result.$1 && !result.$2.isEmpty) {
        final mat = result.$2;
        
        final cvtColorStart = DateTime.now().microsecondsSinceEpoch;
        final pic = cv.cvtColor(mat, cv.COLOR_BGR2RGBA); // VideoTextureModel expects RGBA
        cvtColorTime = DateTime.now().microsecondsSinceEpoch - cvtColorStart;
        
        final textureRenderStart = DateTime.now().microsecondsSinceEpoch;
        _textureModel!.renderFrame(
          0, // display index
          pic.dataPtr,
          pic.total * pic.elemSize,
          pic.cols,
          pic.rows,
        );
        textureRenderTime = DateTime.now().microsecondsSinceEpoch - textureRenderStart;
        
        mat.dispose();
        pic.dispose();
      } else {
        logWarning('TimelineProcessingService', 'Failed to read frame $sourceFrame from ${clip.sourcePath}. Rendering blank.');
        await _renderBlankFrame();
      }
      
      _lastRenderedFrame = frameIndex;
      
    } catch (e, stack) {
      logError('TimelineProcessingService', 'Error rendering frame $frameIndex: $e', stack);
      await _renderBlankFrame(); // Ensure a blank frame on error
    } finally {
      final totalTime = DateTime.now().microsecondsSinceEpoch - overallStartTime;
      // Log timing breakdown occasionally (e.g., every 30 frames or if slow)
      if (frameIndex % 30 == 0 || totalTime > 33000) { // Log if > ~33ms (30fps budget)
        logDebug('TimelineProcessingService: Frame $frameIndex timing (µs):', 'RenderTiming');
        logDebug('  GetClip: $getClipTime', 'RenderTiming');
        logDebug('  CalcSrcFrame: $calculateSourceFrameTime', 'RenderTiming');
        logDebug('  SetFramePos: $setFrameTime', 'RenderTiming');
        logDebug('  ReadFrame: $readFrameTime', 'RenderTiming');
        logDebug('  CvtColor: $cvtColorTime', 'RenderTiming');
        logDebug('  TextureRender: $textureRenderTime', 'RenderTiming');
        logDebug('  Total: $totalTime', 'RenderTiming');
      }
    }
  }
  
  Future<void> _renderBlankFrame() async {
    if (_textureModel == null || !_textureModel!.isReady(0)) return;

    const width = 1920; // Or get from CanvasDimensionsService if restored
    const height = 1080;
    
    // VideoTextureModel expects RGBA. Create a black RGBA frame.
    cv.Mat blankFrame = cv.Mat.zeros(height, width, cv.MatType.CV_8UC4);
    // cv.Vec4b blackColor = cv.Vec4b(0, 0, 0, 255); // Or use cv.Scalar.all(0) and then convert to RGBA with alpha
    // blankFrame.setTo(blackColor);
    // blackColor.dispose();

    _textureModel!.renderFrame(
      0, // display index
      blankFrame.dataPtr,
      blankFrame.total * blankFrame.elemSize,
      blankFrame.cols,
      blankFrame.rows,
    );
    
    blankFrame.dispose();
  }
  
  ClipModel? _getClipAtFrame(int frame) {
    final clips = _timelineState.clips;
    for (final clip in clips) {
      final startFrame = _msToFrame(clip.startTimeOnTrackMs, 30.0);
      final endFrame = _msToFrame(clip.endTimeOnTrackMs, 30.0);
      if (frame >= startFrame && frame < endFrame) {
        return clip;
      }
    }
    return null;
  }
  
  int _calculateSourceFrame(ClipModel clip, int timelineFrame) {
    const fps = 30.0;
    final clipStartFrame = _msToFrame(clip.startTimeOnTrackMs, fps);
    final sourceStartFrame = _msToFrame(clip.startTimeInSourceMs, fps);
    final frameInClip = timelineFrame - clipStartFrame;
    final sourceFrame = sourceStartFrame + frameInClip;
    final videoInfo = _videoInfoCache[clip.sourcePath];
    return sourceFrame.clamp(0, videoInfo?.frameCount ?? sourceFrame);
  }
  
  int _msToFrame(int ms, double fps) {
    return (ms * fps / 1000).round();
  }
  
  @override
  FutureOr onDispose() {
    dispose();
  }
  
  void dispose() {
    logInfo('TimelineProcessingService: Starting disposal');
    
    // currentFrameNotifier.value?.dispose(); // Removed this
    // currentFrameNotifier.dispose(); // Removed this

    if (_currentTextureModelId != null) {
      logInfo('TimelineProcessingService: Disposing texture model: $_currentTextureModelId');
      _textureService.disposeTextureModel(_currentTextureModelId!);
    } else {
      logInfo('TimelineProcessingService: No texture model to dispose');
    }
    
    logInfo('TimelineProcessingService: Releasing video captures (count: ${_videoCaptures.length})');
    for (final capture in _videoCaptures.values) {
      capture.release();
    }
    _videoCaptures.clear();
    _videoInfoCache.clear();
    
    _textureModel = null;
    _currentClip = null;
    _currentCapture = null;

    logInfo('TimelineProcessingService: Disposal complete');
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
}
