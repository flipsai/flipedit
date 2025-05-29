import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';
import 'video_seek_slider.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  
  const VideoPlayerWidget({super.key, required this.videoPath});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayer _videoPlayer;
  final _textureRenderer = TextureRgbaRenderer();
  int? _textureId;
  int _textureKey = -1;
  bool _isInitialized = false;
  String? _errorMessage;
  double _aspectRatio = 16 / 9; // Default aspect ratio
  Timer? _frameTimer;
  Timer? _stateSyncTimer; // Timer for periodic state synchronization
  bool _isPlaying = false; // Cache playing state to avoid blocking UI
  
  String get _logTag => 'VideoPlayerWidget';
  
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }
  
  Future<void> _initializePlayer() async {
    try {
      // Create video player instance
      _videoPlayer = VideoPlayer();
      
      logDebug("Loading video from: ${widget.videoPath}", _logTag);
      
      // Check if file exists
      if (!await File(widget.videoPath).exists()) {
        throw Exception("Video file not found: ${widget.videoPath}");
      }
      
      // First, test if the basic pipeline works
      logDebug("Testing basic GStreamer pipeline...", _logTag);
      await _videoPlayer.testPipeline(filePath: widget.videoPath);
      logDebug("Basic pipeline test completed successfully", _logTag);
      
      // Create texture
      _textureKey = DateTime.now().millisecondsSinceEpoch;
      final textureId = await _textureRenderer.createTexture(_textureKey);
      
      if (textureId == -1) {
        throw Exception("Failed to create texture");
      }
      
      logDebug("Created texture with ID: $textureId", _logTag);
      
      setState(() {
        _textureId = textureId;
      });
      
      // Get texture pointer and pass to Rust
      final texturePtr = await _textureRenderer.getTexturePtr(_textureKey);
      _videoPlayer.setTexturePtr(ptr: texturePtr);
      
      logDebug("Set texture pointer: $texturePtr", _logTag);
      
      // Validate texture pointer
      if (texturePtr == 0) {
        throw Exception("Invalid texture pointer received");
      }
      
      // Load video
      await _videoPlayer.loadVideo(filePath: widget.videoPath);
      
      logDebug("Video loaded successfully", _logTag);
      
      setState(() {
        _isInitialized = true;
      });
      
      // Add a longer delay to ensure pipeline is fully set up
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Start playback
      await _videoPlayer.play();
      
      logDebug("Video playback started", _logTag);
      
      // Sync initial playing state
      _isPlaying = await _videoPlayer.syncPlayingState();
      
      // Get video dimensions after a brief delay to ensure first frame is decoded
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final dimensions = _videoPlayer.getVideoDimensions();
          final width = dimensions.$1;
          final height = dimensions.$2;
          
          logDebug("Video dimensions: ${width}x$height", _logTag);
          
          if (width > 0 && height > 0) {
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
      setState(() {
        _errorMessage = e.toString();
      });
      logError(_logTag, "Error initializing video player: $e");
    }
  }
  
  void _startFrameUpdater() {
    // Start a timer to periodically fetch frames from Rust and update the texture
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      if (!mounted || !_isInitialized) {
        timer.cancel();
        return;
      }
      
      try {
        // Get the latest frame from Rust
        final frameData = _videoPlayer.getLatestFrame();
        
        if (frameData != null) {
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
          }
          
          // Only call setState if we successfully updated the texture
          // This reduces unnecessary UI rebuilds
          if (mounted && success) {
            setState(() {});
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
      if (!mounted || !_isInitialized) {
        timer.cancel();
        return;
      }
      
      try {
        final actualPlayingState = await _videoPlayer.syncPlayingState();
        if (_isPlaying != actualPlayingState && mounted) {
          setState(() {
            _isPlaying = actualPlayingState;
          });
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
      // Cancel the frame timer
      _frameTimer?.cancel();
      _frameTimer = null;
      
      // Cancel the state sync timer
      _stateSyncTimer?.cancel();
      _stateSyncTimer = null;
      
      if (_isInitialized) {
        logDebug("Stopping video player...", _logTag);
        await _videoPlayer.stop();
        logDebug("Video player stopped", _logTag);
        
        logDebug("Disposing video player...", _logTag);
        await _videoPlayer.dispose();
        logDebug("Video player disposed", _logTag);
      }
      
      if (_textureKey != -1) {
        logDebug("Closing texture...", _logTag);
        await _textureRenderer.closeTexture(_textureKey);
        logDebug("Texture closed", _logTag);
        _textureKey = -1;
      }
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
        _buildControls(),
      ],
    );
  }
  
  Widget _buildControls() {
    // Get audio information
    final hasAudio = _videoPlayer.hasAudio();
    
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Audio information display
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasAudio ? Icons.volume_up : Icons.volume_off,
                  color: hasAudio ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  hasAudio 
                    ? 'Audio: Enabled (Direct System Output)'
                    : 'No Audio',
                  style: TextStyle(
                    color: hasAudio ? Colors.green : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                if (hasAudio) ...[
                  const SizedBox(width: 16),
                  Icon(
                    _isPlaying ? Icons.speaker : Icons.speaker_outlined,
                    color: _isPlaying ? Colors.blue : Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isPlaying ? 'Playing' : 'Stopped',
                    style: TextStyle(
                      color: _isPlaying ? Colors.blue : Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Seek slider
          VideoSeekSlider(
            videoPlayer: _videoPlayer,
          ),
          
          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () async {
                  try {
                    if (_isPlaying) {
                      await _videoPlayer.pause();
                      _isPlaying = false;
                    } else {
                      await _videoPlayer.play();
                      _isPlaying = true;
                    }
                    if (mounted) {
                      setState(() {});
                  }
                  } catch (e) {
                    logError(_logTag, "Error toggling playback: $e");
                    // Sync the playing state with the actual player state
                    if (mounted) {
                      _isPlaying = await _videoPlayer.syncPlayingState();
                      setState(() {});
                    }
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.stop, color: Colors.white),
                onPressed: () async {
                  try {
                    await _videoPlayer.stop();
                    _isPlaying = false;
                    if (mounted) {
                      setState(() {});
                    }
                  } catch (e) {
                    logError(_logTag, "Error stopping playback: $e");
                  }
                },
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () => _videoPlayer.stop(),
            child: const Text('Stop'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _videoPlayer.testAudio();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Audio test initiated - check logs for details')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Audio test failed: $e')),
                );
              }
            },
            child: const Text('Test Audio'),
          ),
        ],
      ),
    );
  }
}
