import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
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
      
      await _compositor.initialize(
        video1Path: widget.video1Path,
        video2Path: widget.video2Path,
      );

      if (widget.onCompositorCreated != null) {
        widget.onCompositorCreated!(_compositor);
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      logger.logInfo('Compositor initialized successfully', _logTag);
    } catch (e) {
      logger.logError('Error initializing compositor: $e', _logTag);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
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
            child: ValueListenableBuilder<int>(
              valueListenable: _compositor.playerService.textureIdNotifier,
              builder: (context, textureId, _) {
                logger.logInfo('Texture ID updated: $textureId', _logTag);
                if (textureId <= 0) {
                  return const Center(
                    child: fluent_ui.ProgressRing(),
                  );
                }
                return Texture(textureId: textureId);
              },
            ),
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
  
  final MdkPlayerService _playerService = MdkPlayerService();

  MdkPlayerService get playerService => _playerService;

  int get width => _width;
  int get height => _height;
  int get textureId => _playerService.textureId;
  
  MdkVideoCompositor();

  Future<void> initialize({
    required String video1Path, 
    required String video2Path,
  }) async {
    try {
      _videoFiles.clear();
      _videoFiles.add(video1Path);
      _videoFiles.add(video2Path);
      
      logger.logInfo('Video paths to use: $_videoFiles', _logTag);
      
      final firstVideoExists = await _checkFileExists(_videoFiles[0]);
      logger.logInfo('First video exists: $firstVideoExists at path: ${_videoFiles[0]}', _logTag);
      
      final mediaSetupSuccess = await _playerService.setAndPrepareMedia(
        _videoFiles[0], 
        type: mdk.MediaType.video
      );
      
      if (!mediaSetupSuccess) {
        throw Exception('Failed to set up media in player service');
      }
      
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
      
      // await _setupCompositing();
      
      // If texture ID is still invalid after setup, try to force texture creation
      if (_playerService.textureId <= 0) {
        logger.logInfo('Texture ID still invalid after setup, attempting reset and retry...', _logTag);
        final forcedId = await resetAndRetryVideoSetup(); // Use the renamed method
        
        if (forcedId <= 0) {
          logger.logWarning('Failed to force texture creation', _logTag);
        } else {
          logger.logInfo('Successfully forced texture creation with ID: $forcedId', _logTag);
        }
      }
      
      logger.logInfo('Compositor initialized with dimensions: ${_width}x$_height, texture ID: ${_playerService.textureId}', _logTag);
    } catch (e) {
      logger.logError('Failed to initialize compositor: $e', _logTag);
      rethrow;
    }
  }

  Future<bool> _checkFileExists(String path) async {
    if (path.startsWith('assets/') || path.startsWith('/assets/')) {
      return true;
    }
    return File(path).existsSync();
  }

  String _getProperPath(String originalPath) {
    // Already has the asset:/// prefix
    if (originalPath.startsWith('asset:///')) {
      return originalPath;
    }
    
    // Needs the asset:/// prefix
    if (originalPath.startsWith('assets/')) {
      return 'asset:///' + originalPath;
    }
    
    // Check if it's a file path
    if (File(originalPath).existsSync()) {
      return originalPath;
    }
    
    // Last resort, try it as an asset
    logger.logWarning('Path not found as file: $originalPath, trying as asset', _logTag);
    return 'asset:///' + (originalPath.startsWith('/') ? originalPath.substring(1) : originalPath);
  }

  // Future<void> _setupCompositing() async {
  //   if (_videoFiles.length < 2 || _playerService.player == null) return;
    
  //   try {
  //     final player = _playerService.player!;
      
  //     logger.logInfo('Player state before setup: ${player.state}', _logTag);
      
  //     final previousState = player.state;
      
  //     // Configure the player for better performance
  //     player.setProperty('video.decoder.thread_count', '4');
  //     player.setProperty('buffer_range', '8');
  //     player.setActiveTracks(mdk.MediaType.audio, []);
      
  //     // Ensure the second video path is correctly formatted
  //     final secondVideoPath = _getProperPath(_videoFiles[1]);
  //     logger.logInfo('Using second video path: $secondVideoPath', _logTag);
      
  //     // Set the second input source first before configuring filters
  //     player.setProperty('video.input.1', secondVideoPath);
      
  //     // Wait for the second input to be recognized
  //     await Future.delayed(const Duration(milliseconds: 200));
      
  //     // Configure an FFmpeg filter for compositing
  //     // Note: [0] is the first video input, [1] is the second video input
  //     // This uses the overlay filter which takes two inputs and overlays one on top of the other
  //     // Format: [main_video][overlay_video]overlay=x:y:format=auto:alpha=0.5
  //     final filterString = '[0:v][1:v]overlay=x=W/4:y=H/4:format=auto:alpha=0.7';
      
  //     player.setProperty('video.filters', filterString);
  //     logger.logInfo('Video filter set: ${player.getProperty('video.filters')}', _logTag);
      
  //     // Play to ensure media is decoded and filter is applied
  //     player.state = mdk.PlaybackState.playing;
  //     await Future.delayed(const Duration(milliseconds: 500));
  //     player.state = mdk.PlaybackState.paused;
  //     await Future.delayed(const Duration(milliseconds: 100));
      
  //     // Create/update texture for rendering
  //     final textureId = await player.updateTexture(width: _width, height: _height);
  //     logger.logInfo('Texture updated with ID: $textureId', _logTag);
      
  //     // Manually update texture ID notifier if needed
  //     if (textureId > 0 && _playerService.textureId < 0) {
  //       // Access the internal notifier and force update
  //       _playerService.textureIdNotifier.value = textureId;
  //       logger.logInfo('Manually updated textureIdNotifier to: $textureId', _logTag);
  //     }
      
  //     // Explicitly render a frame to make sure the composite is visible
  //     player.renderVideo();
      
  //     // Log the filter chain to verify it's correct
  //     logger.logInfo('Current filter chain: ${player.getProperty('video.filters')}', _logTag);
  //     logger.logInfo('Input 1 path: ${player.getProperty('video.input.1')}', _logTag);
      
  //     // Apply previous state if needed
  //     if (previousState == mdk.PlaybackState.playing) {
  //       player.state = previousState;
  //     }
      
  //     logger.logInfo('Compositing setup complete with texture ID: ${_playerService.textureId}', _logTag);
  //   } catch (e) {
  //     logger.logError('Error setting up compositing: $e', _logTag);
  //   }
  // }

  void dispose() {
    if (_isDisposed) return;
    
    try {
      _playerService.clearMedia();
      _videoFiles.clear();
      _isDisposed = true;
      logger.logInfo('Compositor disposed', _logTag);
    } catch (e) {
      logger.logError('Error disposing compositor: $e', _logTag);
    }
  }

  /// Resets filters and inputs, re-applies compositing setup, and attempts texture creation.
  Future<int> resetAndRetryVideoSetup() async {
    if (_playerService.player == null || _width <= 0 || _height <= 0) {
      logger.logWarning('Cannot reset/retry video setup - invalid state (player null or dimensions invalid)', _logTag);
      return -1;
    }
     if (_isDisposed) {
      logger.logWarning('Cannot reset/retry video setup - compositor is disposed', _logTag);
      return -1;
    }

    try {
      logger.logInfo('Forcing texture creation with size: ${_width}x$_height', _logTag);
      
      // Temporarily pause if playing
      final currentState = _playerService.player!.state;
      if (currentState == mdk.PlaybackState.playing) {
        _playerService.player!.state = mdk.PlaybackState.paused;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // Log current state before reset
      final player = _playerService.player!;
      logger.logInfo('State before reset: filters="${player.getProperty('video.filters')}", avfilter="${player.getProperty('video.avfilter')}", input1="${player.getProperty('video.input.1')}"', _logTag);

      // Explicitly clear custom avfilter
      logger.logInfo('Clearing video.avfilter...', _logTag);
      player.setProperty('video.avfilter', '');

      // Re-apply the compositing setup
      logger.logInfo('Re-applying compositing setup via _setupCompositing()...', _logTag);
      // await _setupCompositing(); // This should reset video.filters and video.input.1

      // First, try setting the surface size explicitly
      _playerService.player!.setVideoSurfaceSize(_width, _height);
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Get current texture ID
      int currentId = _playerService.textureId;
      
      // If we already have a valid texture ID, just return it
      if (currentId > 0) {
        logger.logInfo('Already have valid texture ID: $currentId', _logTag);
        
        // Restore state if needed
        if (currentState == mdk.PlaybackState.playing) {
          _playerService.player!.state = currentState;
        }
        
        return currentId;
      }
      
      // Force update texture
      final newId = await _playerService.player!.updateTexture(width: _width, height: _height);
      logger.logInfo('Force updated texture with result: $newId', _logTag);
      
      // Manually update texture ID notifier if needed
      if (newId > 0 && _playerService.textureId < 0) {
        _playerService.textureIdNotifier.value = newId;
        logger.logInfo('Manual override of textureIdNotifier to: $newId', _logTag);
      }
      
      // Render a frame
      _playerService.player!.renderVideo();
      
      // Restore state if needed
      if (currentState == mdk.PlaybackState.playing) {
        _playerService.player!.state = currentState;
      } else {
        // Ensure a frame is rendered even if paused
        player.renderVideo();
      }
      
      return _playerService.textureId;
    } catch (e) {
      logger.logError('Error forcing texture creation: $e', _logTag);
      return -1;
    }
  }

  /// Apply a custom FFmpeg video filter graph string using the 'video.avfilter' property.
  Future<void> applyVideoFilterGraph(String userFilterGraph) async {
    if (_playerService.player == null) {
      logger.logWarning('Cannot apply filter graph, player is null', _logTag);
      return;
    }
    if (_isDisposed) {
      logger.logWarning('Cannot apply filter graph, compositor is disposed', _logTag);
       return;
    }

    try {
      final player = _playerService.player!;
      
      // Log state before applying
      String filtersBefore = player.getProperty('video.filters') ?? 'null';
      String avfilterBefore = player.getProperty('video.avfilter') ?? 'null';
      logger.logInfo('Before applying user filter: video.filters="$filtersBefore", video.avfilter="$avfilterBefore"', _logTag);

      // Apply the filter using video.avfilter
      logger.logInfo('Applying user filter graph to video.avfilter: "$userFilterGraph"', _logTag);
      player.setProperty('video.avfilter', userFilterGraph); // Use the documented property

      // Log state after applying
      String filtersAfter = player.getProperty('video.filters') ?? 'null';
      String avfilterAfter = player.getProperty('video.avfilter') ?? 'null';
      logger.logInfo('After applying user filter: video.filters="$filtersAfter", video.avfilter="$avfilterAfter"', _logTag);

      // Re-render if paused to potentially show immediate effect
      if (player.state != mdk.PlaybackState.playing) {
        player.renderVideo();
      }

    } catch (e) {
      logger.logError('Error applying video filter graph: $e', _logTag);
    }
  }
}