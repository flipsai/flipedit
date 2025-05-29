import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/cached_timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class CachedTimelineVideoPlayerWidget extends StatefulWidget {
  final List<ClipModel> clips;
  final TimelineNavigationViewModel timelineNavViewModel;
  
  const CachedTimelineVideoPlayerWidget({
    super.key, 
    required this.clips,
    required this.timelineNavViewModel,
  });

  @override
  State<CachedTimelineVideoPlayerWidget> createState() => _CachedTimelineVideoPlayerWidgetState();
}

class _CachedTimelineVideoPlayerWidgetState extends State<CachedTimelineVideoPlayerWidget> {
  final _textureRenderer = TextureRgbaRenderer();
  int? _textureId;
  int _textureKey = -1;
  bool _isInitialized = false;
  String? _errorMessage;
  double _aspectRatio = 16 / 9;
  Timer? _frameUpdateTimer;
  Timer? _statusUpdateTimer;
  
  // Cache status for UI
  String _cacheStatus = 'Initializing...';
  String _performanceStatus = 'Ready';
  bool _hasFrameData = false;
  
  String get _logTag => 'CachedTimelineVideoPlayerWidget';
  
  @override
  void initState() {
    super.initState();
    _initializeCachedPlayer();
    _startStatusUpdates();
  }

  @override
  void didUpdateWidget(CachedTimelineVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if clips have changed
    if (widget.clips != oldWidget.clips) {
      _updateTimelineClips();
    }
  }
  
  Future<void> _initializeCachedPlayer() async {
    try {
      logDebug("Initializing cached timeline video player", _logTag);
      
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
      
      // Get texture pointer and pass to cached viewmodel
      final texturePtr = await _textureRenderer.getTexturePtr(_textureKey);
      final cachedViewModel = di<CachedTimelineViewModel>();
      await cachedViewModel.setTexturePtr(texturePtr);
      
      logDebug("Set texture pointer: $texturePtr", _logTag);
      
      if (texturePtr == 0) {
        throw Exception("Invalid texture pointer received");
      }
      
      // Update timeline with current clips
      await _updateTimelineClips();
      
      setState(() {
        _isInitialized = true;
      });
      
      // Start frame update timer
      _frameUpdateTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        _updateTexture();
      });
      
      logDebug("Cached timeline video player initialized successfully", _logTag);
      
    } catch (e) {
      logError(_logTag, "Failed to initialize cached timeline video player: $e");
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }
  
  Future<void> _updateTimelineClips() async {
    try {
      final cachedViewModel = di<CachedTimelineViewModel>();
      
      // Timeline clips are automatically updated via listeners in the cached viewmodel
      // Just trigger an update to ensure composer is synced
      await cachedViewModel.seekToFrame(widget.timelineNavViewModel.currentFrame);
      
      logDebug("Updated timeline clips: ${widget.clips.length} clips", _logTag);
      
    } catch (e) {
      logError(_logTag, "Failed to update timeline clips: $e");
    }
  }
  
  void _updateTexture() {
    if (!_isInitialized || _textureId == null) return;
    
    try {
      final cachedViewModel = di<CachedTimelineViewModel>();
      
      // Get latest frame data
      final frameData = cachedViewModel.getLatestFrameData();
      
      if (frameData.data != null) {
        logDebug("Updating texture with cached frame: ${frameData.width}x${frameData.height}, ${frameData.data!.length} bytes", _logTag);
        
        _textureRenderer.onRgba(
          _textureKey,
          frameData.data!,
          frameData.height,
          frameData.width,
          1,
        );
        
        final newAspectRatio = frameData.width / frameData.height;
        if (_aspectRatio != newAspectRatio) {
          setState(() {
            _aspectRatio = newAspectRatio;
          });
          logDebug("Updated aspect ratio to: $newAspectRatio", _logTag);
        }
      }
    } catch (e) {
      logError(_logTag, "Error updating texture: $e");
    }
  }
  
  void _startStatusUpdates() {
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateCacheStatus();
    });
  }
  
  void _updateCacheStatus() {
    try {
      final cachedViewModel = di<CachedTimelineViewModel>();
      setState(() {
        _cacheStatus = cachedViewModel.cacheStatusNotifier.value;
        _performanceStatus = cachedViewModel.hasFrameDataNotifier.value ? 'Active' : 'Loading';
        _hasFrameData = cachedViewModel.hasFrameDataNotifier.value;
      });
    } catch (e) {
      logError(_logTag, "Error updating cache status: $e");
    }
  }
  
  void _debugCacheStatus() {
    try {
      final cachedViewModel = di<CachedTimelineViewModel>();
      final stats = cachedViewModel.cacheStatistics;
      
      logInfo(_logTag, '=== CACHE DEBUG STATUS ===');
      logInfo(_logTag, 'Cache entries: ${stats['cacheEntries']}');
      logInfo(_logTag, 'Cache size: ${stats['cacheSizeMB']} MB');
      logInfo(_logTag, 'Cache hits: ${stats['cacheHits']}');
      logInfo(_logTag, 'Cache misses: ${stats['cacheMisses']}');
      logInfo(_logTag, 'Hit rate: ${(stats['hitRate'] * 100).toStringAsFixed(1)}%');
      logInfo(_logTag, 'Active renderers: ${stats['activeRenderers']}');
      logInfo(_logTag, 'Queue length: ${stats['queueLength']}');
      logInfo(_logTag, 'Total frames rendered: ${stats['totalFramesRendered']}');
      logInfo(_logTag, 'Avg render time: ${stats['averageRenderTimeMs']} ms');
      
      // Check current state
      final currentFrame = widget.timelineNavViewModel.currentFrameNotifier.value;
      final isPlaying = widget.timelineNavViewModel.isPlayingNotifier.value;
      logInfo(_logTag, 'Current frame: $currentFrame');
      logInfo(_logTag, 'Is playing: $isPlaying');
      logInfo(_logTag, 'Clips count: ${widget.clips.length}');
      
      // Check frame data
      final frameData = cachedViewModel.getLatestFrameData();
      logInfo(_logTag, 'Has frame data: ${frameData.data != null}');
      if (frameData.data != null) {
        logInfo(_logTag, 'Frame size: ${frameData.width}x${frameData.height}');
        logInfo(_logTag, 'Frame data length: ${frameData.data!.length} bytes');
      }
      
      logInfo(_logTag, '=== END CACHE DEBUG ===');
      
    } catch (e) {
      logError(_logTag, 'Error during cache debug: $e');
    }
  }
  
  Future<void> _testSingleFrameRender() async {
    try {
      logInfo(_logTag, '=== TESTING SINGLE FRAME RENDER ===');
      
      if (widget.clips.isEmpty) {
        logError(_logTag, 'No clips available for test render');
        return;
      }
      
      final cachedViewModel = di<CachedTimelineViewModel>();
      final currentFrame = widget.timelineNavViewModel.currentFrameNotifier.value;
      
      logInfo(_logTag, 'Testing render for frame $currentFrame with ${widget.clips.length} clips');
      
      // Force an immediate cache attempt
      await cachedViewModel.seekToFrame(currentFrame);
      
      // Wait a moment and check results
      await Future.delayed(Duration(milliseconds: 2000));
      
      final stats = cachedViewModel.cacheStatistics;
      logInfo(_logTag, 'After test render:');
      logInfo(_logTag, '  Cache entries: ${stats['cacheEntries']}');
      logInfo(_logTag, '  Queue length: ${stats['queueLength']}');
      logInfo(_logTag, '  Active renderers: ${stats['activeRenderers']}');
      
      final frameData = cachedViewModel.getLatestFrameData();
      logInfo(_logTag, '  Has frame data: ${frameData.data != null}');
      
      logInfo(_logTag, '=== END TEST RENDER ===');
      
    } catch (e) {
      logError(_logTag, 'Error during test render: $e');
    }
  }
  
  @override
  void dispose() {
    logDebug("Disposing cached timeline video player widget", _logTag);
    
    _frameUpdateTimer?.cancel();
    _statusUpdateTimer?.cancel();
    
    if (_textureId != null) {
      _textureRenderer.closeTexture(_textureKey);
    }
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Video Player Error',
                style: fluent.FluentTheme.of(context).typography.title,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: fluent.FluentTheme.of(context).typography.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _textureId == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const fluent.ProgressRing(),
              const SizedBox(height: 16),
              Text(
                'Initializing Cached Player...',
                style: fluent.FluentTheme.of(context).typography.body,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Main video texture
          Center(
            child: AspectRatio(
              aspectRatio: _aspectRatio,
              child: Texture(textureId: _textureId!),
            ),
          ),
          
          // Performance overlay (top-right)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Cached Player',
                    style: fluent.FluentTheme.of(context).typography.caption?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _cacheStatus,
                    style: fluent.FluentTheme.of(context).typography.caption?.copyWith(
                      color: Colors.white70,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    _performanceStatus,
                    style: fluent.FluentTheme.of(context).typography.caption?.copyWith(
                      color: _hasFrameData ? Colors.green : Colors.orange,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Cache controls (bottom-left)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First row of controls
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.refresh, size: 16),
                        onPressed: () {
                          final cachedViewModel = di<CachedTimelineViewModel>();
                          cachedViewModel.warmupCurrentRegion();
                          logInfo(_logTag, 'Manual cache warmup triggered');
                        },
                      ),
                      fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.play, size: 16),
                        onPressed: () {
                          final cachedViewModel = di<CachedTimelineViewModel>();
                          cachedViewModel.debugForceCacheFrames(frameRadius: 30);
                          logInfo(_logTag, 'Force cache frames triggered');
                        },
                      ),
                      fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.delete, size: 16),
                        onPressed: () {
                          final cachedViewModel = di<CachedTimelineViewModel>();
                          cachedViewModel.clearCache();
                          logInfo(_logTag, 'Cache cleared manually');
                        },
                      ),
                    ],
                  ),
                  
                  // Debug row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.info, size: 16),
                        onPressed: () => _debugCacheStatus(),
                      ),
                      fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.test_case, size: 16),
                        onPressed: () => _testSingleFrameRender(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 