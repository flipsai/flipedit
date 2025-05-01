import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:ffi/ffi.dart';
import 'package:watch_it/watch_it.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:flipedit/services/mdk_player_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// A widget that demonstrates compositing two videos using MDK directly
class CompositeVideoPreview extends StatefulWidget {
  final String video1Path;
  final String video2Path;
  final Function(MdkVideoCompositor)? onCompositorCreated;
  
  const CompositeVideoPreview({
    Key? key,
    required this.video1Path,
    required this.video2Path,
    this.onCompositorCreated,
  }) : super(key: key);

  @override
  State<CompositeVideoPreview> createState() => _CompositeVideoPreviewState();
}

class _CompositeVideoPreviewState extends State<CompositeVideoPreview> {
  final _logTag = 'CompositeVideoPreview';
  late MdkVideoCompositor _compositor;
  int _textureId = -1;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _compositor = MdkVideoCompositor();
    _initializeCompositor();
  }

  Future<void> _initializeCompositor() async {
    try {
      logger.logInfo('Initializing compositor with videos: ${widget.video1Path}, ${widget.video2Path}', _logTag);
      
      // Initialize the compositor with both video paths
      await _compositor.initialize(
        video1Path: widget.video1Path,
        video2Path: widget.video2Path,
      );

      // Notify if callback exists
      if (widget.onCompositorCreated != null) {
        widget.onCompositorCreated!(_compositor);
      }

      // Get the texture ID for rendering
      final textureId = await _compositor.prepareCompositeTexture();
      
      if (textureId > 0) {
        setState(() {
          _textureId = textureId;
          _isInitialized = true;
        });
        logger.logInfo('Compositor initialized successfully with texture ID: $_textureId', _logTag);
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to get valid texture ID';
        });
        logger.logError('Failed to get valid texture ID', _logTag);
      }
    } catch (e) {
      logger.logError('Error initializing compositor: $e', _logTag);
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _compositor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Text('Error: $_errorMessage', 
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: fluent_ui.ProgressRing(),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _compositor.width.toDouble(),
            height: _compositor.height.toDouble(),
            child: Texture(textureId: _textureId),
          ),
        ),
      ),
    );
  }
}

/// A class that handles compositing videos using MDK directly
class MdkVideoCompositor {
  final String _logTag = 'MdkVideoCompositor';
  final List<String> _videoFiles = [];
  int _width = 0;
  int _height = 0;
  bool _isDisposed = false;
  
  // Use the MdkPlayerService to handle media playback and texture creation
  final MdkPlayerService _playerService = MdkPlayerService();

  // Expose player service for external control
  MdkPlayerService get playerService => _playerService;

  int get width => _width;
  int get height => _height;
  
  MdkVideoCompositor();

  Future<void> initialize({
    required String video1Path, 
    required String video2Path,
  }) async {
    try {
      _videoFiles.clear(); // Clear any existing entries
      _videoFiles.add(video1Path);
      _videoFiles.add(video2Path);
      
      logger.logInfo('Video paths to use: $_videoFiles', _logTag);
      
      // Check if files exist
      final firstVideoExists = await _checkFileExists(_videoFiles[0]);
      logger.logInfo('First video exists: $firstVideoExists at path: ${_videoFiles[0]}', _logTag);
      
      // Set up the media in the playerService
      final mediaSetupSuccess = await _playerService.setAndPrepareMedia(
        _videoFiles[0], 
        type: mdk.MediaType.video
      );
      
      if (!mediaSetupSuccess) {
        throw Exception('Failed to set up media in player service');
      }
      
      // Initialize the player and check its state
      final playerInitialized = await _initializePlayer();
      if (!playerInitialized) {
        throw Exception('Failed to initialize player in ready state');
      }
      
      // Get dimensions from the first video
      final player = _playerService.player;
      if (player == null) {
        throw Exception('Player is null after media setup');
      }
      
      final mediaInfo = player.mediaInfo;
      final videoInfo = mediaInfo.video?.firstOrNull?.codec;
      _width = videoInfo?.width ?? 0;
      _height = videoInfo?.height ?? 0;
      
      if (_width <= 0 || _height <= 0) {
        throw Exception('Invalid video dimensions: ${_width}x$_height');
      }
      
      // Configure the player with our compositing settings using appropriate properties
      _setupCompositing();
      
      logger.logInfo('Compositor initialized with dimensions: ${_width}x$_height', _logTag);
    } catch (e) {
      logger.logError('Failed to initialize compositor: $e', _logTag);
      rethrow;
    }
  }

  /// Check if a file exists, handling asset paths specially
  Future<bool> _checkFileExists(String path) async {
    if (path.startsWith('assets/') || path.startsWith('/assets/')) {
      // For assets, we need to handle this specially 
      // Assets should exist but we can't check directly with File().exists()
      return true;
    }
    return File(path).existsSync();
  }

  String _getProperPath(String originalPath) {
    // Check if this is an asset path
    if (originalPath.startsWith('assets/')) {
      // Use asset:/// for flutter assets
      return 'asset:///${originalPath}';
    } else if (File(originalPath).existsSync()) {
      // Absolute file path that exists
      return originalPath;
    } else {
      // Try as an asset as fallback
      logger.logWarning('File not found at $originalPath, trying as asset', _logTag);
      return 'asset:///$originalPath';
    }
  }

  void _setupCompositing() {
    if (_videoFiles.length < 2 || _playerService.player == null) return;
    
    try {
      final player = _playerService.player!;
      
      // Log player state before changing properties
      logger.logInfo('Player state before setup: ${player.state}', _logTag);
      
      // Ensure player is stopped temporarily while we configure it
      final previousState = player.state;
      if (previousState != mdk.PlaybackState.stopped) {
        player.state = mdk.PlaybackState.stopped;
        // Brief pause to let the player react to state change
        Future.delayed(const Duration(milliseconds: 20));
      }
      
      // Set up basic player properties for optimal compositing performance
      player.setProperty('video.decoder.thread_count', '4');
      player.setProperty('buffer_range', '8');
      player.setProperty('continue_at_end', '1');
      player.setProperty('video.clear_on_stop', '0');
      player.setProperty('gpu.priority', 'high'); // Prioritize GPU use for compositing
      player.setActiveTracks(mdk.MediaType.audio, []); // Disable audio
      
      // Handle path for second video correctly
      final secondVideoPath = _getProperPath(_videoFiles[1]);
      logger.logInfo('Using second video path: $secondVideoPath', _logTag);
      
      // Create a complex filter string for MDK
      // This example uses blend_mode=overlay and opacity=0.5
      final filterString = 'overlay=x=0:y=0:blend_mode=overlay:opacity=0.5';
      
      // Apply the filter to set up compositing
      player.setProperty('video.filters', filterString);
      
      // Add the second video as a source
      player.setProperty('video.input.1', secondVideoPath);
      
      // Restore previous state if it was playing/paused
      if (previousState == mdk.PlaybackState.playing || previousState == mdk.PlaybackState.paused) {
        player.state = previousState;
      } else {
        // Otherwise start playback to activate filters/compositing
        player.state = mdk.PlaybackState.playing;
        // Then immediately pause to keep the frame static if needed
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_playerService.player != null) {
            _playerService.player!.state = mdk.PlaybackState.paused;
          }
        });
      }
      
      logger.logInfo('Compositing setup complete', _logTag);
    } catch (e) {
      logger.logError('Error setting up compositing: $e', _logTag);
    }
  }

  /// Get a texture ID for Flutter rendering
  Future<int> prepareCompositeTexture() async {
    if (_isDisposed) {
      logger.logWarning('Attempted to prepare texture after disposal', _logTag);
      return -1;
    }
    
    try {
      // Initialize player if needed
      await _initializePlayer();
      
      // Prepare the frame for display using the service
      final frameDisplaySuccess = await _playerService.prepareFrameForDisplay();
      if (!frameDisplaySuccess) {
        logger.logError('Failed to prepare frame for display', _logTag);
        return -1;
      }
      
      // Get the texture ID from the service
      final textureId = _playerService.textureId;
      
      if (textureId > 0) {
        logger.logInfo('Using texture ID: $textureId', _logTag);
        
        // Make sure we have a visible frame by starting playback
        final player = _playerService.player;
        if (player != null) {
          // Force a playing state to ensure compositing is active
          logger.logInfo('Setting player to playing state to activate compositing', _logTag);
          player.state = mdk.PlaybackState.playing;
          
          // Give the player a moment to render the first frame with compositing
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Pause to keep the frame static
          player.state = mdk.PlaybackState.paused;
        }
        
        return textureId;
      } else {
        logger.logError('Failed to get valid texture ID', _logTag);
        return -1;
      }
    } catch (e) {
      logger.logError('Error preparing composite texture: $e', _logTag);
      return -1;
    }
  }

  void dispose() {
    if (_isDisposed) return;
    
    try {
      // Clean up resources
      _playerService.clearMedia();
      _videoFiles.clear();
      _isDisposed = true;
      logger.logInfo('Compositor disposed', _logTag);
    } catch (e) {
      logger.logError('Error disposing compositor: $e', _logTag);
    }
  }

  // Add initializePlayer method to explicitly ensure the player is ready before compositing
  Future<bool> _initializePlayer() async {
    if (_playerService.player == null) {
      logger.logError('Player is null after media setup', _logTag);
      return false;
    }

    try {
      final player = _playerService.player!;
      
      // Ensure player is in a proper state
      logger.logInfo('Initializing player, current state: ${player.state}', _logTag);
      
      // Reset player if in a problematic state
      if (player.state == mdk.PlaybackState.stopped || player.state == mdk.PlaybackState.notRunning) {
        logger.logWarning('Player in problematic state, resetting', _logTag);
        player.state = mdk.PlaybackState.stopped;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      
      // Ensure we're ready to compose
      final mediaStatus = player.mediaStatus;
      if (mediaStatus.test(mdk.MediaStatus.invalid) || mediaStatus.test(mdk.MediaStatus.noMedia)) {
        logger.logError('Media status is not valid: $mediaStatus', _logTag);
        return false;
      }
      
      logger.logInfo('Player initialized successfully', _logTag);
      return true;
    } catch (e) {
      logger.logError('Error initializing player: $e', _logTag);
      return false;
    }
  }
} 