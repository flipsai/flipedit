import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  
  const VideoPlayerWidget({super.key, required this.videoPath});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerService _videoPlayerService;
  VideoPlayer? _localVideoPlayer; // Local video player instance for this widget
  final _textureRenderer = TextureRgbaRenderer();
  int? _textureId;
  int _textureKey = -1;
  bool _isInitialized = false;
  String? _errorMessage;
  double _aspectRatio = 16 / 9; // Default aspect ratio
  Timer? _frameTimer;
  Timer? _stateSyncTimer; // Timer for periodic state synchronization
  bool _isPlaying = false; // Cache playing state to avoid blocking UI
  int _noFrameCount = 0; // Counter for no frame data logging
  
  String get _logTag => 'VideoPlayerWidget';
  
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
    final timelineNavViewModel = di<TimelineNavigationViewModel>();
    final isTimelinePlaying = timelineNavViewModel.isPlayingNotifier.value;
    final isLocalVideoPlaying = _isPlaying;
    
    logDebug("Timeline playback state changed - timeline: $isTimelinePlaying, local video: $isLocalVideoPlaying, initialized: $_isInitialized, textureId: $_textureId", _logTag);
    
    // Only sync if the video player widget is fully initialized and has a texture and is still mounted
    if (!mounted || !_isInitialized || _textureId == null || _localVideoPlayer == null) {
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
        logError(_logTag, "Error starting local video playback: $error");
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
        logError(_logTag, "Error pausing local video playback: $error");
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
      
      // Create local video player instance
      _localVideoPlayer = VideoPlayer();
      
      // Create texture
      _textureKey = DateTime.now().millisecondsSinceEpoch;
      final textureId = await _textureRenderer.createTexture(_textureKey);
      
      if (textureId == -1) {
        throw Exception("Failed to create texture");
      }
      
      logDebug("Created texture with ID: $textureId", _logTag);
      
      if (mounted) {
        setState(() {
          _textureId = textureId;
        });
      }
      
      // Get texture pointer and pass to local video player
      final texturePtr = await _textureRenderer.getTexturePtr(_textureKey);
      _localVideoPlayer!.setTexturePtr(ptr: texturePtr);
      
      logDebug("Set texture pointer: $texturePtr", _logTag);
      
      // Validate texture pointer
      if (texturePtr == 0) {
        throw Exception("Invalid texture pointer received");
      }
      
      // Load video into local player
      await _localVideoPlayer!.loadVideo(filePath: widget.videoPath);
      
      // Update the service with the video path for coordination
      _videoPlayerService.setCurrentVideoPath(widget.videoPath);
      
      // Register this video player instance for seeking
      _videoPlayerService.registerVideoPlayer(_localVideoPlayer!);
      
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
      
      // Start frame update timer
      _startFrameUpdater();
      
      // Start state synchronization timer
      _startStateSynchronization();
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
      logError(_logTag, "Error initializing video player: $e");
    }
  }
  
  void _startFrameUpdater() {
    // Start a timer to periodically fetch frames from Rust and update the texture
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      if (!mounted || !_isInitialized || _localVideoPlayer == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Get the latest frame from the local video player
        final frameData = _localVideoPlayer!.getLatestFrame();
        
        if (frameData != null) {
          logDebug("Got frame data: ${frameData.width}x${frameData.height}, data length: ${frameData.data.length}", _logTag);
          
          // Convert the frame data to Uint8List
          final uint8Data = Uint8List.fromList(frameData.data);
          
          // Update the texture using the onRgba API
          final success = await _textureRenderer.onRgba(
            _textureKey, 
            uint8Data, 
            frameData.height.toInt(), 
            frameData.width.toInt(),
            1 // stride_align - use 1 for no alignment
          );
          
          if (!success) {
            logWarning(_logTag, "Failed to update texture with frame data");
          } else {
            logDebug("Successfully updated texture with frame data", _logTag);
          }
          
          // Only call setState if we successfully updated the texture and widget is still mounted
          if (mounted && success) {
            setState(() {});
          }
        } else {
          // Log when no frame data is available
          _noFrameCount++;
          if (_noFrameCount % 30 == 0) { // Log every 30 attempts (once per second)
            logDebug("No frame data available (count: $_noFrameCount), local player initialized: $_isInitialized, playing: $_isPlaying", _logTag);
          }
        }

        // Audio is now handled directly by Rust - no need to check for audio data here
        
      } catch (e) {
        logError(_logTag, "Error updating frame: $e");
      }
    });
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
      
      // Cancel timers first to prevent any further setState calls
      if (_frameTimer != null) {
        _frameTimer!.cancel();
        _frameTimer = null;
        logDebug("Frame timer cancelled", _logTag);
      }
      
      if (_stateSyncTimer != null) {
        _stateSyncTimer!.cancel();
        _stateSyncTimer = null;
        logDebug("State sync timer cancelled", _logTag);
      }
      
      // Unregister video player from service
      _videoPlayerService.unregisterVideoPlayer();
      
      // Remove timeline listener
      try {
        final timelineNavViewModel = di<TimelineNavigationViewModel>();
        timelineNavViewModel.isPlayingNotifier.removeListener(_onTimelinePlaybackStateChanged);
        logDebug("Timeline listener removed", _logTag);
      } catch (e) {
        logError(_logTag, "Error removing timeline listener: $e");
      }
      
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
      
      if (_textureKey != -1) {
        logDebug("Closing texture...", _logTag);
        try {
          await _textureRenderer.closeTexture(_textureKey);
          logDebug("Texture closed", _logTag);
          _textureKey = -1;
        } catch (e) {
          logError(_logTag, "Error closing texture: $e");
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
