import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart' hide Native;
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/video_texture_model.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/services/video_processing_service.dart';
import 'package:flipedit/services/video_texture_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

class NativePlayerViewModel extends ChangeNotifier implements Disposable {
  // Dependencies
  final TimelineNavigationViewModel _timelineNavViewModel;
  final TimelineStateViewModel _timelineStateViewModel;
  final VideoProcessingService _videoProcessingService;
  final VideoTextureService _textureService;
  final CanvasDimensionsService _canvasDimensionsService;

  // Texture rendering
  VideoTextureModel? _textureModel;
  final int _strideAlign = Platform.isMacOS ? 64 : 1;
  
  // Performance monitoring
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);
  int _lastRenderTimeUs = 0;
  
  // Frame cache
  final Map<String, Map<int, cv.Mat>> _frameCache = {};
  static const int _maxCacheSize = 60; // Cache ~2 seconds at 30fps
  
  // Playback state
  int _currentRenderMethod = 1; // 0: Method channel, 1: Native FFI, 2: OpenCV direct
  Timer? _renderTimer;
  VoidCallback? _playStateListener;
  VoidCallback? _frameListener;
  VoidCallback? _clipsListener;
  
  // Public state
  final ValueNotifier<int> textureIdNotifier = ValueNotifier(-1);
  final ValueNotifier<bool> isReadyNotifier = ValueNotifier(false);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Initializing...');

  NativePlayerViewModel({
    TimelineNavigationViewModel? timelineNavViewModel,
    TimelineStateViewModel? timelineStateViewModel,
    VideoProcessingService? videoProcessingService,
    VideoTextureService? textureService,
    CanvasDimensionsService? canvasDimensionsService,
  }) : 
    _timelineNavViewModel = timelineNavViewModel ?? di<TimelineNavigationViewModel>(),
    _timelineStateViewModel = timelineStateViewModel ?? di<TimelineStateViewModel>(),
    _videoProcessingService = videoProcessingService ?? di<VideoProcessingService>(),
    _textureService = textureService ?? di<VideoTextureService>(),
    _canvasDimensionsService = canvasDimensionsService ?? di<CanvasDimensionsService>() {
    
    _initialize();
  }

  Future<void> _initialize() async {
    logInfo('Initializing NativePlayerViewModel');
    statusNotifier.value = 'Initializing...';
    
    try {
      // Create texture model
      _textureModel = _textureService.createTextureModel('timeline_player');
      await _textureModel!.createSession('timeline_player');
      
      // Get texture ID
      final textureId = _textureModel!.getTextureId(0).value;
      textureIdNotifier.value = textureId;
      logInfo('Created texture with ID: $textureId');
      
      // Setup listeners
      _playStateListener = _onPlayStateChanged;
      _timelineNavViewModel.isPlayingNotifier.addListener(_playStateListener!);
      
      _frameListener = _onFrameChanged;
      _timelineNavViewModel.currentFrameNotifier.addListener(_frameListener!);
      
      _clipsListener = _onClipsChanged;
      _timelineStateViewModel.clipsNotifier.addListener(_clipsListener!);
      
      // Preload all videos for the clips
      statusNotifier.value = 'Loading videos...';
      try {
        final clips = _timelineStateViewModel.clips;
        logInfo('Preloading videos for ${clips.length} clips');
        
        for (final clip in clips) {
          if (clip.sourcePath.isNotEmpty) {
            final videoId = clip.sourcePath;
            
            // Check if video is already loaded
            if (!_videoProcessingService.isVideoLoaded(videoId)) {
              logInfo('Preloading video for clip: $videoId');
              await _videoProcessingService.loadVideo(videoId, videoId);
            }
          }
        }
        logInfo('Finished preloading videos');
      } catch (e) {
        logError('Error preloading videos: $e');
      }
      
      isReadyNotifier.value = true;
      statusNotifier.value = 'Ready';
      
      // Initial render
      _renderCurrentFrame();
      
      logInfo('NativePlayerViewModel initialized with textureId: $textureId');
    } catch (e) {
      logError('Error initializing player: $e');
      statusNotifier.value = 'Error: $e';
    }
  }

  void _onPlayStateChanged() {
    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    
    if (isPlaying) {
      _startRenderLoop();
    } else {
      _stopRenderLoop();
      // Render current frame once more to ensure it's displayed
      _renderCurrentFrame();
    }
  }

  void _onFrameChanged() {
    if (!_timelineNavViewModel.isPlayingNotifier.value) {
      // Only manually render on frame change when not playing
      // (during playback, the render loop handles this)
      _renderCurrentFrame();
    }
  }

  Future<void> _onClipsChanged() async {
    logInfo('Clips changed, updating player...');
    
    // When clips change, clear cache
    _clearCache();
    
    // Preload all videos for the clips
    try {
      final clips = _timelineStateViewModel.clips;
      for (final clip in clips) {
        if (clip.sourcePath.isNotEmpty) {
          final videoId = clip.sourcePath;
          
          // Check if video is already loaded
          if (!_videoProcessingService.isVideoLoaded(videoId)) {
            logInfo('Preloading video for clip: $videoId');
            await _videoProcessingService.loadVideo(videoId, videoId);
          }
        }
      }
      logInfo('Finished preloading videos for ${clips.length} clips');
    } catch (e) {
      logError('Error preloading videos: $e');
    }
    
    // Re-render current frame
    _renderCurrentFrame();
  }

  void _startRenderLoop() {
    _stopRenderLoop();
    
    // Create a timer that runs at 60fps for smooth rendering
    _renderTimer = Timer.periodic(const Duration(milliseconds: 1000 ~/ 60), (_) {
      _renderCurrentFrame();
    });
  }

  void _stopRenderLoop() {
    _renderTimer?.cancel();
    _renderTimer = null;
  }

  Future<void> _renderCurrentFrame() async {
    try {
      if (!isReadyNotifier.value || _textureModel == null || !_textureModel!.isReady(0)) {
        return;
      }
      
      final startTime = DateTime.now().microsecondsSinceEpoch;
      
      try {
        // Safely get current frame
        final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
        
        // Get visible clips at current frame with safeguards
        List<ClipModel> visibleClips = [];
        try {
          visibleClips = _getVisibleClipsAtFrame(currentFrame);
        } catch (e) {
          logError('Error getting visible clips: $e');
          // Continue with empty list
        }
        
        if (visibleClips.isEmpty) {
          // Render empty frame
          try {
            _renderEmptyFrame();
          } catch (e) {
            logError('Error rendering empty frame: $e');
          }
        } else {
          // Composite and render clips with additional error handling
          try {
            await _renderCompositeFrame(visibleClips, currentFrame);
          } catch (e) {
            logError('Error compositing frame: $e');
            try {
              _renderEmptyFrame(); // Fallback to empty frame on error
            } catch (innerError) {
              logError('Failed to render fallback empty frame: $innerError');
            }
          }
        }
        
        // Calculate FPS
        final endTime = DateTime.now().microsecondsSinceEpoch;
        final renderTime = endTime - startTime;
        _lastRenderTimeUs = renderTime;
        
        final fps = renderTime > 0 ? 1000000 ~/ renderTime : 0;
        fpsNotifier.value = fps;
      } catch (e) {
        logError('Error in render frame process: $e');
        statusNotifier.value = 'Error: $e';
      }
    } catch (e) {
      logError('Critical error in render frame: $e');
      // Don't update status here to avoid potential crash
    }
  }

  List<ClipModel> _getVisibleClipsAtFrame(int timelineFrame) {
    try {
      // Safely get clips with null check
      final clips = _timelineStateViewModel.clips;
      if (clips.isEmpty) {
        return [];
      }
      
      final visibleClips = <ClipModel>[];
      
      for (final clip in clips) {
        try {
          if (clip.startTimeOnTrackMs < 0 || clip.endTimeOnTrackMs <= 0) {
            continue; // Skip invalid clips
          }
          
          // Convert to frames with safeguards against division by zero
          final clipStartFrame = (clip.startTimeOnTrackMs / 1000 * 30).floor();
          final clipEndFrame = (clip.endTimeOnTrackMs / 1000 * 30).floor();
          
          if (timelineFrame >= clipStartFrame && timelineFrame < clipEndFrame) {
            visibleClips.add(clip);
          }
        } catch (e) {
          logError('Error processing clip in _getVisibleClipsAtFrame: $e');
          // Continue with next clip
        }
      }
      
      // Sort by track order (bottom to top) with error handling
      try {
        visibleClips.sort((a, b) => a.trackId.compareTo(b.trackId));
      } catch (e) {
        logError('Error sorting clips: $e');
        // Return unsorted if sorting fails
      }
      
      return visibleClips;
    } catch (e) {
      logError('Error in _getVisibleClipsAtFrame: $e');
      return [];
    }
  }

  Future<void> _renderCompositeFrame(List<ClipModel> clips, int timelineFrame) async {
    // Safely get canvas dimensions with fallback values
    int canvasWidth = 640;  // Default fallback width
    int canvasHeight = 360; // Default fallback height
    
    try {
      canvasWidth = _canvasDimensionsService.canvasWidthNotifier.value.toInt();
      canvasHeight = _canvasDimensionsService.canvasHeightNotifier.value.toInt();
    } catch (e) {
      logError('Error getting canvas dimensions: $e');
    }
    
    // Use minimum size if dimensions are invalid
    if (canvasWidth <= 0) canvasWidth = 640;
    if (canvasHeight <= 0) canvasHeight = 360;
    
    final frames = <cv.Mat>[];
    final alphas = <double>[];
    final framesToDispose = <cv.Mat>[]; // Track frames we need to dispose
    
    try {
      // Process each clip with error handling
      for (final clip in clips) {
        try {
          final clipFrame = _timelineToClipFrame(clip, timelineFrame);
          if (clipFrame < 0) continue; // Skip invalid frames
          
          // Try to get from cache first - use sourcePath as the key
          final videoId = clip.sourcePath;
          if (videoId.isEmpty) {
            logWarning('Clip has empty source path, skipping');
            continue;
          }
          
          cv.Mat? frame = _getCachedFrame(videoId, clipFrame);
          bool fromCache = frame != null;
          
          // If not in cache, load and process
          if (frame == null) {
            // First ensure the video is loaded
            if (!_videoProcessingService.isVideoLoaded(videoId)) {
              logInfo('Loading video for clip: $videoId');
              await _videoProcessingService.loadVideo(videoId, videoId);
            }
            
            frame = await _loadFrameForClip(clip, clipFrame);
            if (frame != null) {
              _cacheFrame(videoId, clipFrame, frame);
            }
          }
          
          if (frame != null) {
            // For frames from cache, we need to track and dispose our copy
            if (fromCache) {
              framesToDispose.add(frame);
            }
            
            frames.add(frame);
            
            // Default opacity to 1.0 if not specified in metadata
            double opacity = 1.0;
            try {
              opacity = (clip.metadata['opacity'] as double?) ?? 1.0;
            } catch (e) {
              logWarning('Error reading opacity, using default: $e');
            }
            alphas.add(opacity);
          }
        } catch (e) {
          logError('Error processing clip ${clip.databaseId}: $e');
          // Continue with next clip
        }
      }
      
      // Composite frames
      if (frames.isNotEmpty) {
        try {
          // Log frame information for debugging
          logInfo('Compositing ${frames.length} frames:');
          for (int i = 0; i < frames.length; i++) {
            final frame = frames[i];
            final alpha = i < alphas.length ? alphas[i] : 1.0;
            logInfo('  Frame $i: ${frame.cols}x${frame.rows}x${frame.channels}, alpha=$alpha');
          }
          
          // Ensure all frames have 4 channels (RGBA)
          final processedFrames = <cv.Mat>[];
          for (final frame in frames) {
            if (frame.channels != 4) {
              logInfo('Converting frame from ${frame.channels} channels to 4 channels');
              cv.Mat converted;
              if (frame.channels == 3) {
                converted = cv.cvtColor(frame, cv.COLOR_BGR2RGBA);
              } else if (frame.channels == 1) {
                converted = cv.cvtColor(frame, cv.COLOR_GRAY2RGBA);
              } else {
                logWarning('Unsupported channel count: ${frame.channels}, using original frame');
                converted = frame.clone();
              }
              processedFrames.add(converted);
              framesToDispose.add(converted);
            } else {
              processedFrames.add(frame);
            }
          }
          
          // Composite the frames
          logInfo('Calling compositeFrames with canvas size: ${canvasWidth}x${canvasHeight}');
          final compositeFrame = _videoProcessingService.compositeFrames(
            processedFrames, alphas, canvasWidth, canvasHeight
          );
          framesToDispose.add(compositeFrame);
          
          // Log composite frame info
          logInfo('Composite frame created: ${compositeFrame.cols}x${compositeFrame.rows}x${compositeFrame.channels}');
          
          // Render to texture
          _renderFrameToTexture(compositeFrame);
        } catch (e, stack) {
          logError('Error in final compositing stage: $e');
          logError('Stack trace: $stack');
          _renderEmptyFrame();
        }
      } else {
        logInfo('No frames to composite, rendering empty frame');
        _renderEmptyFrame();
      }
    } catch (e) {
      logError('Error compositing frames: $e');
    } finally {
      // Clean up all frames we created in this method
      for (final frame in framesToDispose) {
        try {
          if (!frame.isEmpty) {
            frame.dispose();
          }
        } catch (e) {
          // Ignore disposal errors
        }
      }
    }
  }

  void _renderFrameToTexture(cv.Mat frame) {
    try {
      if (_textureModel == null) {
        logError('Texture model is null in _renderFrameToTexture');
        return;
      }
      
      if (!_textureModel!.isReady(0)) {
        logWarning('Texture model not ready in _renderFrameToTexture');
        return;
      }
      
      if (frame.isEmpty) {
        logWarning('Frame is empty in _renderFrameToTexture');
        return;
      }
      
      logInfo('Rendering frame to texture: ${frame.cols}x${frame.rows}x${frame.channels}');
      
      switch (_currentRenderMethod) {
        case 0: // Method channel
          logInfo('Using Method Channel rendering');
          _renderWithMethodChannel(frame);
          break;
        case 1: // Native FFI
          logInfo('Using Native FFI rendering');
          _renderWithNativeFFI(frame);
          break;
        case 2: // OpenCV direct
          logInfo('Using OpenCV direct rendering');
          _renderWithOpenCV(frame);
          break;
        default:
          logWarning('Unknown render method: $_currentRenderMethod, defaulting to Native FFI');
          _renderWithNativeFFI(frame);
      }
    } catch (e, stack) {
      logError('Error in _renderFrameToTexture: $e');
      logError('Stack trace: $stack');
    }
  }

  void _renderWithMethodChannel(cv.Mat frame) {
    try {
      if (_textureModel == null) {
        logError('Texture model is null in _renderWithMethodChannel');
        return;
      }
      
      if (!_textureModel!.isReady(0)) {
        logWarning('Texture model not ready in _renderWithMethodChannel');
        return;
      }
      
      // Validate frame
      if (frame.isEmpty) {
        logWarning('Empty frame in _renderWithMethodChannel');
        return;
      }
      
      if (frame.channels != 4) {
        logWarning('Frame has ${frame.channels} channels, expected 4 (RGBA) in _renderWithMethodChannel');
      }
      
      // Get frame data
      final data = frame.data;
      if (data.isEmpty) {
        logWarning('Empty frame data in _renderWithMethodChannel');
        return;
      }
      
      logInfo('Rendering frame via Method Channel: ${frame.cols}x${frame.rows}, ${data.length} bytes');
      
      // Use the texture model's renderFrameBytes method directly
      // This ensures we're using the correct texture key that was used to create the texture
      _textureModel!.renderFrameBytes(
        0, // display index
        data,
        frame.cols,
        frame.rows
      );
      
      logInfo('Method channel rendering completed');
    } catch (e, stack) {
      logError('Error in method channel rendering: $e');
      logError('Stack trace: $stack');
    }
  }

  void _renderWithNativeFFI(cv.Mat frame) {
    try {
      if (_textureModel == null) {
        logError('Texture model is null in _renderWithNativeFFI');
        return;
      }
      
      if (!_textureModel!.isReady(0)) {
        logWarning('Texture model not ready in _renderWithNativeFFI');
        return;
      }
      
      if (frame.isEmpty) {
        logWarning('Attempted to render empty frame in _renderWithNativeFFI');
        return;
      }
      
      // Validate frame
      if (frame.channels != 4) {
        logWarning('Frame has ${frame.channels} channels, expected 4 (RGBA) in _renderWithNativeFFI');
      }
      
      // Get frame data as Uint8List
      final data = frame.data;
      if (data.isEmpty) {
        logWarning('Empty frame data in _renderWithNativeFFI');
        return;
      }
      
      logInfo('Frame data size: ${data.length} bytes (${frame.cols}x${frame.rows}x${frame.channels})');
      
      // Use the texture model's renderFrameBytes method directly
      // This is more reliable than trying to get the texture pointer and using Native.instance.onRgba
      try {
        logInfo('Rendering frame using texture model renderFrameBytes');
        
        _textureModel!.renderFrameBytes(
          0, // display index
          data,
          frame.cols,
          frame.rows
        );
        
        logInfo('Texture model rendering completed successfully');
      } catch (e, stack) {
        logError('Error in texture model rendering: $e');
        logError('Stack trace: $stack');
      }
    } catch (e, stack) {
      logError('Error in native FFI rendering: $e');
      logError('Stack trace: $stack');
    }
  }

  void _renderWithOpenCV(cv.Mat frame) {
    try {
      if (_textureModel == null) {
        logError('Texture model is null in _renderWithOpenCV');
        return;
      }
      
      if (!_textureModel!.isReady(0)) {
        logWarning('Texture model not ready in _renderWithOpenCV');
        return;
      }
      
      if (frame.isEmpty) {
        logWarning('Attempted to render empty frame in _renderWithOpenCV');
        return;
      }
      
      // Validate frame
      if (frame.channels != 4) {
        logWarning('Frame has ${frame.channels} channels, expected 4 (RGBA) in _renderWithOpenCV');
      }
      
      // Get frame data as Uint8List
      final data = frame.data;
      if (data.isEmpty) {
        logWarning('Empty frame data in _renderWithOpenCV');
        return;
      }
      
      logInfo('Frame data size: ${data.length} bytes (${frame.cols}x${frame.rows}x${frame.channels})');
      
      // Use the texture model's renderFrameBytes method directly
      try {
        logInfo('Rendering frame using texture model renderFrameBytes (OpenCV)');
        
        _textureModel!.renderFrameBytes(
          0, // display index
          data,
          frame.cols,
          frame.rows
        );
        
        logInfo('OpenCV rendering completed successfully');
      } catch (e, stack) {
        logError('Error in OpenCV rendering: $e');
        logError('Stack trace: $stack');
      }
    } catch (e, stack) {
      logError('Error in OpenCV rendering: $e');
      logError('Stack trace: $stack');
    }
  }

  void _renderEmptyFrame() {
    try {
      // Safely get canvas dimensions with fallback values
      int canvasWidth = 640;  // Default fallback width
      int canvasHeight = 360; // Default fallback height
      
      try {
        canvasWidth = _canvasDimensionsService.canvasWidthNotifier.value.toInt();
        canvasHeight = _canvasDimensionsService.canvasHeightNotifier.value.toInt();
      } catch (e) {
        logError('Error getting canvas dimensions for empty frame: $e');
      }
      
      // Use minimum size if dimensions are invalid
      if (canvasWidth <= 0) canvasWidth = 640;
      if (canvasHeight <= 0) canvasHeight = 360;
      
      try {
        final emptyFrame = cv.Mat.zeros(canvasHeight, canvasWidth, cv.MatType.CV_8UC4);
        _renderFrameToTexture(emptyFrame);
        emptyFrame.dispose();
      } catch (e) {
        logError('Error creating or rendering empty frame: $e');
      }
    } catch (e) {
      logError('Critical error in _renderEmptyFrame: $e');
    }
  }

  int _timelineToClipFrame(ClipModel clip, int timelineFrame) {
    try {
      if (clip.startTimeOnTrackMs < 0) {
        return 0; // Default to first frame for invalid clips
      }
      
      // Convert with safeguards against division by zero
      final clipStartFrame = (clip.startTimeOnTrackMs / 1000 * 30).floor();
      final clipFrame = timelineFrame - clipStartFrame;
      
      // Ensure frame is within valid range
      if (clipFrame < 0) {
        return 0;
      }
      
      return clipFrame;
    } catch (e) {
      logError('Error calculating clip frame: $e');
      return 0; // Default to first frame on error
    }
  }

  Future<cv.Mat?> _loadFrameForClip(ClipModel clip, int frameIndex) async {
    try {
      if (frameIndex < 0) {
        logWarning('Invalid frame index: $frameIndex');
        return null;
      }
      
      // Use the clip's source path as the video ID
      String videoId;
      try {
        if (clip.sourcePath.isEmpty) {
          logError('Clip has empty source path');
          return null;
        }
        videoId = clip.sourcePath;
      } catch (e) {
        logError('Error getting clip source path: $e');
        return null;
      }
      
      // Get video frame from processing service
      VideoFrame? videoFrame;
      try {
        videoFrame = _videoProcessingService.getVideoFrame(videoId, frameIndex);
      } catch (e) {
        logError('Error getting video frame: $e');
        return null;
      }
      
      if (videoFrame == null) {
        return null;
      }
      
      // Apply transformations with error handling
      try {
        // Safely extract transform parameters with defaults
        double scale = 1.0;
        double rotation = 0.0;
        try {
          scale = clip.metadata['scale'] as double? ?? 1.0;
          rotation = clip.metadata['rotation'] as double? ?? 0.0;
        } catch (e) {
          logWarning('Error reading transform parameters, using defaults: $e');
        }
        
        final transform = TransformParams(
          x: clip.previewPositionX,
          y: clip.previewPositionY,
          scale: scale,
          rotation: rotation,
        );
        
        final transformedMat = _videoProcessingService.transformFrame(videoFrame.mat, transform);
        
        // Return a clone to avoid issues with the original being disposed
        return transformedMat.clone();
      } catch (e) {
        logError('Error applying transformations: $e');
        
        // Return the original frame as fallback if transformation fails
        try {
          return videoFrame.mat.clone();
        } catch (innerError) {
          logError('Failed to clone original frame: $innerError');
          return null;
        }
      }
    } catch (e) {
      logError('Critical error loading frame for clip: $e');
      return null;
    }
  }

  cv.Mat? _getCachedFrame(String clipId, int frameIndex) {
    try {
      if (frameIndex < 0) {
        return null;
      }
      
      if (_frameCache.containsKey(clipId) &&
          _frameCache[clipId]!.containsKey(frameIndex)) {
        try {
          final cachedFrame = _frameCache[clipId]![frameIndex];
          if (cachedFrame == null || cachedFrame.isEmpty) {
            return null;
          }
          return cachedFrame.clone();
        } catch (e) {
          logError('Error cloning cached frame: $e');
          return null;
        }
      }
      return null;
    } catch (e) {
      logError('Error getting cached frame: $e');
      return null;
    }
  }

  void _cacheFrame(String clipId, int frameIndex, cv.Mat frame) {
    try {
      if (frameIndex < 0 || frame.isEmpty) {
        return;
      }
      
      // Create map for clip if it doesn't exist
      if (!_frameCache.containsKey(clipId)) {
        _frameCache[clipId] = {};
      }
      
      // If cache is full, remove oldest frame
      try {
        if (_frameCache[clipId]!.length >= _maxCacheSize) {
          final oldestKey = _frameCache[clipId]!.keys.first;
          try {
            _frameCache[clipId]![oldestKey]?.dispose();
          } catch (e) {
            logWarning('Error disposing old cached frame: $e');
          }
          _frameCache[clipId]!.remove(oldestKey);
        }
      } catch (e) {
        logWarning('Error managing cache size: $e');
        // Clear the cache for this clip if we can't manage it properly
        _clearCacheForClip(clipId);
      }
      
      // Store a clone in the cache
      try {
        _frameCache[clipId]![frameIndex] = frame.clone();
      } catch (e) {
        logError('Error cloning frame for cache: $e');
      }
    } catch (e) {
      logError('Error caching frame: $e');
    }
  }
  
  void _clearCacheForClip(String clipId) {
    try {
      if (_frameCache.containsKey(clipId)) {
        for (final frame in _frameCache[clipId]!.values) {
          try {
            frame.dispose();
          } catch (e) {
            // Ignore disposal errors
          }
        }
        _frameCache[clipId]!.clear();
      }
    } catch (e) {
      logWarning('Error clearing cache for clip $clipId: $e');
    }
  }

  void _clearCache() {
    try {
      // Create a copy of the keys to avoid concurrent modification
      final clipIds = List<String>.from(_frameCache.keys);
      
      for (final clipId in clipIds) {
        try {
          _clearCacheForClip(clipId);
        } catch (e) {
          logWarning('Error clearing cache for clip $clipId: $e');
        }
      }
      
      _frameCache.clear();
      logInfo('Frame cache cleared');
    } catch (e) {
      logError('Error clearing frame cache: $e');
    }
  }

  // Public methods
  void setRenderMethod(int methodId) {
    if (methodId >= 0 && methodId <= 2) {
      _currentRenderMethod = methodId;
      _renderCurrentFrame();
    }
  }

  int get renderMethod => _currentRenderMethod;
  
  void clearCache() {
    _clearCache();
  }

  @override
  void dispose() {
    try {
      logInfo('Disposing NativePlayerViewModel');
      
      try {
        // Stop rendering
        _stopRenderLoop();
      } catch (e) {
        logError('Error stopping render loop: $e');
      }
      
      try {
        // Remove listeners
        if (_playStateListener != null) {
          _timelineNavViewModel.isPlayingNotifier.removeListener(_playStateListener!);
        }
        
        if (_frameListener != null) {
          _timelineNavViewModel.currentFrameNotifier.removeListener(_frameListener!);
        }
        
        if (_clipsListener != null) {
          _timelineStateViewModel.clipsNotifier.removeListener(_clipsListener!);
        }
      } catch (e) {
        logError('Error removing listeners: $e');
      }
      
      try {
        // Clear cache
        _clearCache();
      } catch (e) {
        logError('Error clearing cache during disposal: $e');
      }
      
      try {
        // Dispose texture
        if (_textureModel != null) {
          _textureService.disposeTextureModel('timeline_player');
        }
      } catch (e) {
        logError('Error disposing texture model: $e');
      }
      
      try {
        // Dispose notifiers
        textureIdNotifier.dispose();
        isReadyNotifier.dispose();
        statusNotifier.dispose();
        fpsNotifier.dispose();
      } catch (e) {
        logError('Error disposing notifiers: $e');
      }
      
      logInfo('NativePlayerViewModel disposed successfully');
    } catch (e) {
      logError('Critical error during NativePlayerViewModel disposal: $e');
    } finally {
      super.dispose();
    }
  }

  @override
  FutureOr onDispose() {
    // Already handled in dispose()
  }
}