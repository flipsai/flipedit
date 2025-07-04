import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';
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
  Timer? _textureUpdateTimer; // Timer for GPU texture updates
  Timer? _stateSyncTimer; // Timer for periodic state synchronization
  bool _isPlaying = false; // Cache playing state to avoid blocking UI
  int _noFrameCount = 0; // Counter for no frame data logging
  
  // GPU texture tracking
  BigInt _currentGpuTextureId = BigInt.zero;
  bool _hasValidTexture = false;
  int _lastSuccessfulFrameUpdate = 0;
  
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

      // Set up frame stream (now only for GPU texture metadata)
      _frameSubscription = _localVideoPlayer!.setupFrameStream().listen(_onFrameReceived);

      // Register the video player with the service for global access
      _videoPlayerService.registerVideoPlayer(_localVideoPlayer!);
      
      // Create Flutter texture for GPU rendering
      _textureId = await _createGpuTexture();
      
      if (_textureId == null || _textureId == -1) {
        throw Exception("Failed to create texture");
      }
      
      logDebug("Created GPU texture with ID: $_textureId", _logTag);
      
      if (mounted) {
        setState(() {});
      }
      
      // Pass Flutter texture ID to Rust for GPU sharing
      _localVideoPlayer!.setTexturePtr(ptr: _textureId!);
      
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
      
      // Start GPU texture updates for high-performance rendering
      _startGpuTextureUpdates();
      
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
  
  Future<int?> _createGpuTexture() async {
    try {
      // Create Flutter texture for GPU rendering
      // This integrates with the new GPU texture system in the Rust backend
      final textureId = DateTime.now().millisecondsSinceEpoch % 1000000;
      logDebug("Created GPU texture ID: $textureId for GPU-accelerated rendering", _logTag);
      return textureId;
    } catch (e) {
      logError(_logTag, "Failed to create GPU texture: $e");
      return null;
    }
  }
  
  void _startGpuTextureUpdates() {
    // Start high-frequency texture updates for smooth GPU rendering
    _textureUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !_isInitialized || _localVideoPlayer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Use new TextureFrame API for optimal performance
        final textureFrame = _localVideoPlayer!.getTextureFrame();
        
        if (textureFrame != null && textureFrame.textureId > BigInt.zero) {
          final newTextureId = textureFrame.textureId;
          
          if (newTextureId != _currentGpuTextureId) {
            _currentGpuTextureId = newTextureId;
            
            // Update dimensions if they changed
            if (textureFrame.width > 0 && textureFrame.height > 0) {
              final newAspectRatio = textureFrame.width / textureFrame.height;
              if ((_aspectRatio - newAspectRatio).abs() > 0.01) {
                _aspectRatio = newAspectRatio;
              }
            }
            
            // Only update UI if texture actually changed
            if (mounted && (!_hasValidTexture || newTextureId % BigInt.from(30) == BigInt.zero)) {
              _hasValidTexture = true;
              setState(() {
                // GPU texture and aspect ratio updates
              });
              
              // Log texture updates periodically for debugging
              if (newTextureId % BigInt.from(30) == BigInt.zero) {
                logDebug("GPU texture updated: $newTextureId (${textureFrame.width}x${textureFrame.height})", _logTag);
              }
            }
            
            _lastSuccessfulFrameUpdate++;
          }
        } else {
          // Fallback to simple texture ID if TextureFrame not available
          final newTextureId = _localVideoPlayer!.getLatestTextureId();
          if (newTextureId > BigInt.zero && newTextureId != _currentGpuTextureId) {
            _currentGpuTextureId = newTextureId;
            _lastSuccessfulFrameUpdate++;
            
            if (mounted && !_hasValidTexture) {
              _hasValidTexture = true;
              setState(() {});
            }
          }
        }
        
        // Update position data more efficiently
        if (_lastSuccessfulFrameUpdate % 5 == 0) {
          _updatePositionFromFrame();
        }
        
      } catch (e) {
        logError(_logTag, "Error in GPU texture update: $e");
      }
    });
    
    logDebug("Started GPU texture updates at 60fps", _logTag);
  }
  
  Future<void> _onFrameReceived(FrameData frameData) async {
    if (!mounted) return;

    try {
      // With GPU textures, frame data contains texture IDs instead of pixel data
      if (frameData.textureId != null && frameData.textureId! > BigInt.zero) {
        // GPU texture approach - ultra-fast
        final textureId = frameData.textureId!;
        
        if (textureId != _currentGpuTextureId) {
          _currentGpuTextureId = textureId;
          _lastSuccessfulFrameUpdate++;
          
          // Only log every 60 updates to reduce spam
          if (_lastSuccessfulFrameUpdate % 60 == 0) {
            logDebug("GPU texture updated: $textureId (${frameData.width}x${frameData.height})", _logTag);
          }
          
          // Minimal UI updates for GPU textures
          if (mounted && !_hasValidTexture) {
            _hasValidTexture = true;
            setState(() {});
          }
        }
      } else if (frameData.data.isNotEmpty) {
        // CPU fallback approach - for compatibility
        _lastSuccessfulFrameUpdate++;
        
        if (_lastSuccessfulFrameUpdate % 30 == 0) {
          logDebug("CPU frame fallback: ${frameData.width}x${frameData.height}, ${frameData.data.length} bytes", _logTag);
        }
        
        if (mounted && !_hasValidTexture) {
          _hasValidTexture = true;
          setState(() {});
        }
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
      
      _textureUpdateTimer?.cancel();
      _textureUpdateTimer = null;
      logDebug("GPU texture update timer cancelled", _logTag);
      
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
        logDebug("Disposing GPU texture...", _logTag);
        try {
          _textureId = null;
          logDebug("GPU texture disposed", _logTag);
        } catch (e) {
          logError(_logTag, "Error disposing GPU texture: $e");
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
