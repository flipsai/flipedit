import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flutter/services.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/src/rust/common/types.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  
  const VideoPlayerWidget({super.key, required this.videoPath});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerService _videoPlayerService;
  VideoPlayer? _localVideoPlayer;
  StreamSubscription<FrameData>? _frameSubscription;
  int? _textureId;
  bool _isInitialized = false;
  String? _errorMessage;
  double _aspectRatio = 16 / 9; // Default aspect ratio
  Timer? _frameTimer;
  Timer? _stateSyncTimer; // Timer for periodic state synchronization
  bool _isPlaying = false; // Cache playing state to avoid blocking UI
  int _noFrameCount = 0; // Counter for no frame data logging
  
  // Performance optimizations
  bool _hasValidTexture = false; // Track if we have a valid texture to avoid unnecessary setState
  int _lastSuccessfulFrameUpdate = 0; // Track frame updates
  
  String get _logTag => runtimeType.toString();
  
  @override
  void initState() {
    super.initState();
    _videoPlayerService = di<VideoPlayerService>();
    
    // Listen to timeline navigation for playback control
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    timelineNavViewModel.isPlayingNotifier.addListener(_onTimelinePlaybackStateChanged);
    
    _initializePlayer();
  }
  
  void _onTimelinePlaybackStateChanged() {
    // Early exit if widget is disposing or disposed
    if (!mounted || _localVideoPlayer == null) return;
    
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    final isTimelinePlaying = timelineNavViewModel.isPlayingNotifier.value;
    final isLocalVideoPlaying = _isPlaying;
    
    logDebug("Timeline playback state changed - timeline: $isTimelinePlaying, local video: $isLocalVideoPlaying, initialized: $_isInitialized, textureId: $_textureId", _logTag);
    
    // Only sync if the video player widget is fully initialized and has a texture and is still mounted
    if (!_isInitialized || _textureId == null) {
      logDebug("Video player not ready for playback - skipping sync", _logTag);
      return;
    }
    
    // Sync local video playback with timeline state
    if (isTimelinePlaying && !isLocalVideoPlaying) {
      logDebug("Starting local video playback to sync with timeline", _logTag);
      _localVideoPlayer!.play().then((_) {
        if (!mounted) return;
        _isPlaying = true;
        _videoPlayerService.setPlayingState(true); // Update service state
        logDebug("Local video playback started", _logTag);
        if (mounted) setState(() {});
      }).catchError((error) {
        if (mounted) {
          logError(_logTag, "Error starting local video playback: $error");
        }
      });
    } else if (!isTimelinePlaying && isLocalVideoPlaying) {
      logDebug("Stopping local video playback to sync with timeline", _logTag);
      _localVideoPlayer!.pause().then((_) {
        if (!mounted) return;
        _isPlaying = false;
        _videoPlayerService.setPlayingState(false); // Update service state
        logDebug("Local video playback paused", _logTag);
        if (mounted) setState(() {});
      }).catchError((error) {
        if (mounted) {
          logError(_logTag, "Error pausing local video playback: $error");
        }
      });
    } else {
      logDebug("No sync needed - both states already match", _logTag);
    }
  }
  
  Future<void> _initializePlayer() async {
    try {
      logDebug("Loading video from: ${widget.videoPath}", _logTag);
      
      // Check if file exists
      if (!await File(widget.videoPath).exists()) {
        throw Exception("Video file not found: ${widget.videoPath}");
      }
      
      // Initialize the local video player
      _localVideoPlayer = di<VideoPlayer>();

      // Set up the frame stream
      _frameSubscription = _localVideoPlayer!.setupFrameStream().listen(_onFrameReceived);

      // Register the video player with the service for global access
      _videoPlayerService.registerVideoPlayer(_localVideoPlayer!);
      
      // Create texture using Flutter's built-in texture system
      // For now, we'll use a dummy texture approach since we removed texture_rgba_renderer
      // The Rust backend will need to be updated to work with Flutter's native texture system
      _textureId = await _createDummyTexture();
      
      if (_textureId == null || _textureId == -1) {
        throw Exception("Failed to create texture");
      }
      
      logDebug("Created texture with ID: $_textureId", _logTag);
      
      if (mounted) {
        setState(() {});
      }
      
      // For now, pass a dummy pointer to the Rust video player
      // The Rust backend should be updated to work directly with Flutter's texture registry
      _localVideoPlayer!.setTexturePtr(ptr: 0);
      
      logDebug("Set texture ptr for Rust player (dummy approach)", _logTag);
      
      // Load video into local player
      await _localVideoPlayer!.loadVideo(filePath: widget.videoPath);
      
      // Update the service with the video path for coordination
      _videoPlayerService.setCurrentVideoPath(widget.videoPath);
      
      logDebug("Local video player initialized successfully", _logTag);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      
      // Add a longer delay to ensure pipeline is fully set up
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Don't start playback automatically - let timeline controls handle this
      logDebug("Video player ready for timeline control", _logTag);
      
      // Get video dimensions after a brief delay to ensure first frame is decoded
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _localVideoPlayer != null) {
          final dimensions = _localVideoPlayer!.getVideoDimensions();
          final width = dimensions.$1;
          final height = dimensions.$2;
          
          logDebug("Video dimensions: ${width}x$height", _logTag);
          
          if (width > 0 && height > 0 && mounted) {
            setState(() {
              _aspectRatio = width / height;
            });
          }
        }
      });
      
      // Start state synchronization timer
      _startStateSynchronization();
      
    } catch (e, stackTrace) {
      logError(_logTag, "Error initializing video player: $e", stackTrace);
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }
  
  Future<int?> _createDummyTexture() async {
    try {
      // Create a simple placeholder texture ID
      // Since we removed texture_rgba_renderer, this is a temporary approach
      // The proper solution would involve integrating with Flutter's TextureRegistry
      // through the engine or using a different texture management approach
      return DateTime.now().millisecondsSinceEpoch % 1000000;
    } catch (e) {
      logError(_logTag, "Failed to create dummy texture: $e");
      return null;
    }
  }
  
  Future<void> _onFrameReceived(FrameData frameData) async {
    if (!mounted) return;

    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;
      logDebug("Got frame data: ${frameData.width}x${frameData.height}, data length: ${frameData.data.length}", _logTag);
      
      // With Flutter's built-in texture system, frame updates are handled by the Rust backend
      // directly through the texture registry. We just need to track successful frame updates.
      _lastSuccessfulFrameUpdate++;
      
      // Only log every 30 successful updates to reduce log spam
      if (_lastSuccessfulFrameUpdate % 30 == 0) {
        logDebug("Received frame data (${_lastSuccessfulFrameUpdate} total)", _logTag);
      }
      
      // Update position/frame data from stream instead of polling
      final positionStartTime = DateTime.now().millisecondsSinceEpoch;
      _updatePositionFromFrame();
      final positionEndTime = DateTime.now().millisecondsSinceEpoch;
      if (_lastSuccessfulFrameUpdate % 30 == 0) {
        logDebug("Position update took ${positionEndTime - positionStartTime}ms", _logTag);
      }
      
      // Only call setState if texture state actually changed to avoid unnecessary rebuilds
      if (mounted && !_hasValidTexture) {
        _hasValidTexture = true;
        setState(() {});
      }
      
      final endTime = DateTime.now().millisecondsSinceEpoch;
      if (_lastSuccessfulFrameUpdate % 30 == 0) {
        logDebug("Total frame processing time: ${endTime - startTime}ms", _logTag);
      }
    } catch (e) {
      logError(_logTag, "Error processing frame: $e");
    }
  }
  
  void _updatePositionFromFrame() {
    if (_localVideoPlayer == null) return;
    
    try {
      // Get current position and frame from Rust
      final positionData = _localVideoPlayer!.getCurrentPositionAndFrame();
      final positionSeconds = positionData.$1;
      final frameNumber = positionData.$2;
      
      // Update service notifiers if values changed
      if ((_videoPlayerService.positionSecondsNotifier.value - positionSeconds).abs() > 0.01) {
        _videoPlayerService.positionSecondsNotifier.value = positionSeconds;
      }
      
      final frameInt = frameNumber.toInt();
      if (_videoPlayerService.currentFrameNotifier.value != frameInt) {
        _videoPlayerService.currentFrameNotifier.value = frameInt;
      }
      
      // Update playing state
      final rustIsPlaying = _localVideoPlayer!.isPlaying();
      if (_videoPlayerService.isPlayingNotifier.value != rustIsPlaying) {
        _videoPlayerService.isPlayingNotifier.value = rustIsPlaying;
      }
    } catch (e) {
      logError(_logTag, "Error updating position from frame: $e");
    }
  }
  
  void _startStateSynchronization() {
    // Periodically sync the cached playing state with the actual player state
    _stateSyncTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted || !_isInitialized || _localVideoPlayer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Sync with the local video player's actual state
        final actualPlayingState = await _localVideoPlayer!.syncPlayingState();
        if (_isPlaying != actualPlayingState && mounted) {
          setState(() {
            _isPlaying = actualPlayingState;
          });
          // Update service state
          _videoPlayerService.setPlayingState(actualPlayingState);
        }
      } catch (e) {
        logError(_logTag, "Error syncing playing state: $e");
      }
    });
  }
  
  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
  
  Future<void> _cleanup() async {
    try {
      logDebug("Starting cleanup...", _logTag);
      
      // Mark as not initialized early to prevent any further operations
      _isInitialized = false;
      
      // Cancel stream subscription
      await _frameSubscription?.cancel();
      _frameSubscription = null;
      logDebug("Frame stream cancelled", _logTag);
      
      // Cancel timers first to prevent any further setState calls
      _frameTimer?.cancel();
      _frameTimer = null;
      logDebug("Frame timer cancelled", _logTag);
      
      _stateSyncTimer?.cancel();
      _stateSyncTimer = null;
      logDebug("State sync timer cancelled", _logTag);
      
      // Remove timeline listener before unregistering to prevent callbacks during disposal
      try {
        final timelineNavViewModel = di<TimelineNavigationViewModel>();
        timelineNavViewModel.isPlayingNotifier.removeListener(_onTimelinePlaybackStateChanged);
        logDebug("Timeline listener removed", _logTag);
      } catch (e) {
        logError(_logTag, "Error removing timeline listener: $e");
      }
      
      // Unregister video player from service (now uses postFrameCallback internally)
      _videoPlayerService.unregisterVideoPlayer();
      
      if (_isInitialized && _localVideoPlayer != null) {
        logDebug("Stopping local video player...", _logTag);
        try {
          await _localVideoPlayer!.stop();
          logDebug("Local video player stopped", _logTag);
        } catch (e) {
          logError(_logTag, "Error stopping video player: $e");
        }
        
        logDebug("Disposing local video player...", _logTag);
        try {
          await _localVideoPlayer!.dispose();
          _localVideoPlayer = null;
          logDebug("Local video player disposed", _logTag);
        } catch (e) {
          logError(_logTag, "Error disposing video player: $e");
        }
      }
      
      if (_textureId != null) {
        logDebug("Disposing texture...", _logTag);
        try {
          // Since we're using a dummy texture approach, no actual disposal is needed
          // In a proper implementation, this would dispose the Flutter texture
          _textureId = null;
          logDebug("Texture disposed", _logTag);
        } catch (e) {
          logError(_logTag, "Error disposing texture: $e");
        }
      }
      
      logDebug("Cleanup completed", _logTag);
    } catch (e) {
      logError(_logTag, "Error during cleanup: $e");
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
    
    if (!_isInitialized || _textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: Texture(textureId: _textureId!),
              ),
            ),
          ),
        ),
      ],
    );
  } 
}
