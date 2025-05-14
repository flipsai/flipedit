import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/timeline_processing_service.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

class NativePlayerViewModel extends ChangeNotifier implements Disposable {
  late final TimelineProcessingService _timelineProcessingService;
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineStateViewModel _timelineStateViewModel;
  late final CanvasDimensionsService _canvasDimensionsService;
  
  Timer? _playbackTimer;
  bool _isDisposed = false;
  
  VoidCallback? _isPlayingListener;
  VoidCallback? _currentFrameListener;
  VoidCallback? _clipsListener;
  VoidCallback? _canvasDimensionsListener;
  
  final ValueNotifier<bool> _isInitializedNotifier = ValueNotifier(false);
  ValueListenable<bool> get isInitializedNotifier => _isInitializedNotifier;
  
  final ValueNotifier<bool> _isRenderingNotifier = ValueNotifier(false);
  ValueListenable<bool> get isRenderingNotifier => _isRenderingNotifier;
  
  final ValueNotifier<String> _statusNotifier = ValueNotifier('Initializing...');
  ValueListenable<String> get statusNotifier => _statusNotifier;
  
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier(null);
  ValueListenable<int?> get textureIdNotifier => _textureIdNotifier;
  
  // Track last rendered frame to avoid unnecessary re-renders
  int _lastRenderedFrame = -1;
  
  NativePlayerViewModel() {
    logDebug('NativePlayerViewModel: Initializing...');
    
    _timelineProcessingService = di.get<TimelineProcessingService>();
    _timelineNavViewModel = di.get<TimelineNavigationViewModel>();
    _timelineStateViewModel = di.get<TimelineStateViewModel>();
    _canvasDimensionsService = di.get<CanvasDimensionsService>();
    
    // Set up listeners
    _isPlayingListener = _handlePlaybackChange;
    _timelineNavViewModel.isPlayingNotifier.addListener(_isPlayingListener!);
    
    _currentFrameListener = _handleFrameChange;
    _timelineNavViewModel.currentFrameNotifier.addListener(_currentFrameListener!);
    
    _clipsListener = _handleClipsChange;
    _timelineStateViewModel.clipsNotifier.addListener(_clipsListener!);
    
    _canvasDimensionsListener = _handleCanvasDimensionsChange;
    _canvasDimensionsService.canvasWidthNotifier.addListener(_canvasDimensionsListener!);
    _canvasDimensionsService.canvasHeightNotifier.addListener(_canvasDimensionsListener!);
    
    // Initialize
    _initialize();
  }
  
  Future<void> _initialize() async {
    if (_isDisposed) return;
    
    try {
      _statusNotifier.value = 'Initializing video system...';
      
      // Initialize texture
      final success = await _timelineProcessingService.initializeTexture('flipedit_player');
      
      if (!success) {
        _statusNotifier.value = 'Failed to initialize video system';
        return;
      }
      
      // Get texture ID
      final textureIdNotifier = _timelineProcessingService.getTextureId(0);
      if (textureIdNotifier != null) {
        // Listen to texture ID changes
        void updateTextureId() {
          if (!_isDisposed) {
            _textureIdNotifier.value = textureIdNotifier.value;
          }
        }
        textureIdNotifier.addListener(updateTextureId);
        _textureIdNotifier.value = textureIdNotifier.value;
      }
      
      // Load videos from timeline
      _statusNotifier.value = 'Loading media files...';
      await _timelineProcessingService.loadTimelineVideos();
      
      _isInitializedNotifier.value = true;
      _statusNotifier.value = 'Ready';
      
      // Render initial frame
      await _renderCurrentFrame();
      
    } catch (e) {
      logError('NativePlayerViewModel', 'Initialization error: $e');
      _statusNotifier.value = 'Error: ${e.toString()}';
    }
  }
  
  void _handlePlaybackChange() {
    if (_isDisposed) return;
    
    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    
    if (isPlaying) {
      _startPlayback();
    } else {
      _stopPlayback();
    }
  }
  
  void _handleFrameChange() {
    if (_isDisposed || !_isInitializedNotifier.value) return;
    
    // Always render the current frame when it changes
    _renderCurrentFrame();
  }
  
  void _handleClipsChange() async {
    if (_isDisposed || !_isInitializedNotifier.value) return;
    
    logVerbose('NativePlayerViewModel: Timeline clips changed, reloading videos...');
    
    // Reload videos when clips change
    await _timelineProcessingService.loadTimelineVideos();
    
    // Reset last rendered frame to force re-render
    _lastRenderedFrame = -1;
    
    // Re-render current frame
    await _renderCurrentFrame();
  }
  
  void _handleCanvasDimensionsChange() {
    if (_isDisposed || !_isInitializedNotifier.value) return;
    
    logVerbose('NativePlayerViewModel: Canvas dimensions changed');
    
    // Reset last rendered frame to force re-render with new dimensions
    _lastRenderedFrame = -1;
    
    // Re-render current frame with new dimensions
    _renderCurrentFrame();
  }
  
  void _startPlayback() {
    if (_isDisposed || !_isInitializedNotifier.value) return;
    
    _stopPlayback(); // Stop any existing playback
    
    logInfo('NativePlayerViewModel: Starting playback');
    
    // TODO: Get FPS from timeline or project settings
    const fps = 30.0;
    final frameDuration = Duration(microseconds: (1000000 / fps).round());
    
    _playbackTimer = Timer.periodic(frameDuration, (timer) async {
      if (_isDisposed || !_timelineNavViewModel.isPlayingNotifier.value) {
        timer.cancel();
        return;
      }
      
      // Get current frame
      final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
      final totalFrames = _timelineNavViewModel.totalFramesNotifier.value;
      
      // Calculate next frame (simple increment by 1)
      final nextFrame = currentFrame + 1;
      
      if (nextFrame >= totalFrames && totalFrames > 0) {
        // Stop at the end
        _timelineNavViewModel.stopPlayback();
        return;
      }
      
      // Update frame position (this will trigger frame change listener)
      _timelineNavViewModel.currentFrame = nextFrame;
    });
  }
  
  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    logInfo('NativePlayerViewModel: Stopped playback');
  }
  
  Future<void> _renderCurrentFrame({bool force = false}) async {
    if (_isDisposed || !_isInitializedNotifier.value || _isRenderingNotifier.value) return;
    
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
    
    // Skip if we've already rendered this frame (unless forced)
    if (!force && currentFrame == _lastRenderedFrame) {
      return;
    }
    
    _isRenderingNotifier.value = true;
    
    try {
      await _timelineProcessingService.renderFrame(currentFrame);
      _lastRenderedFrame = currentFrame;
    } catch (e) {
      logError('NativePlayerViewModel', 'Error rendering frame $currentFrame: $e');
    } finally {
      if (!_isDisposed) {
        _isRenderingNotifier.value = false;
      }
    }
  }
  
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    logDebug('NativePlayerViewModel: Disposing...');
    
    _stopPlayback();
    
    // Remove listeners
    _timelineNavViewModel.isPlayingNotifier.removeListener(_isPlayingListener!);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    _timelineStateViewModel.clipsNotifier.removeListener(_clipsListener!);
    _canvasDimensionsService.canvasWidthNotifier.removeListener(_canvasDimensionsListener!);
    _canvasDimensionsService.canvasHeightNotifier.removeListener(_canvasDimensionsListener!);
    
    // Dispose notifiers
    _isInitializedNotifier.dispose();
    _isRenderingNotifier.dispose();
    _statusNotifier.dispose();
    _textureIdNotifier.dispose();
    
    super.dispose();
    logDebug('NativePlayerViewModel: Disposed');
  }
  
  @override
  FutureOr onDispose() {
    // dispose() is already called by ChangeNotifier
  }
}
