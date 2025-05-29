import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/frame_cache_service.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/src/rust/video/timeline_composer.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

class CachedTimelineComposer {
  static const Duration _frameUpdateInterval = Duration(milliseconds: 33); // ~30fps
  static const Duration _cacheWarmupDelay = Duration(milliseconds: 100);

  final String _logTag = 'CachedTimelineComposer';
  
  late final FrameCacheService _frameCache;
  int? _timelineComposerHandle;
  
  // Current state
  List<ClipModel> _currentClips = [];
  bool _isPlaying = false;
  int _currentFrame = 0;
  double _playbackSpeed = 1.0;
  
  // Performance monitoring
  final ValueNotifier<bool> _isRenderingNotifier = ValueNotifier(false);
  final ValueNotifier<String> _performanceStatusNotifier = ValueNotifier('Ready');
  
  // Timers
  Timer? _frameUpdateTimer;
  Timer? _cacheWarmupTimer;
  
  // Latest frame data for texture updates
  Uint8List? _latestFrameData;
  int _latestFrameWidth = 0;
  int _latestFrameHeight = 0;

  CachedTimelineComposer() {
    _frameCache = FrameCacheService();
    _initialize();
  }

  // Public getters
  ValueListenable<bool> get isRenderingNotifier => _isRenderingNotifier;
  ValueListenable<String> get performanceStatusNotifier => _performanceStatusNotifier;
  Map<String, dynamic> get cacheStatistics => _frameCache.getCacheStatistics();

  Future<void> _initialize() async {
    try {
      _timelineComposerHandle = timelineComposerCreate();
      logInfo(_logTag, 'Created timeline composer handle: $_timelineComposerHandle');
      
      _startFrameUpdateLoop();
      
    } catch (e) {
      logError(_logTag, 'Failed to initialize cached timeline composer: $e');
    }
  }

  void _startFrameUpdateLoop() {
    _frameUpdateTimer = Timer.periodic(_frameUpdateInterval, (_) => _updateCurrentFrame());
  }

  // Main API methods

  Future<void> setTexturePtr(int ptr) async {
    if (_timelineComposerHandle != null) {
      timelineComposerSetTexturePtr(handle: _timelineComposerHandle!, ptr: ptr);
      logDebug('Set texture pointer: $ptr', _logTag);
    }
  }

  Future<void> updateTimeline(List<ClipModel> clips) async {
    if (_timelineComposerHandle == null) return;

    try {
      _isRenderingNotifier.value = true;
      _performanceStatusNotifier.value = 'Updating timeline...';

      // Update the timeline composer
      await timelineComposerUpdateTimeline(
        handle: _timelineComposerHandle!,
        clips: clips.map(_clipToTimelineData).toList(),
      );

      _currentClips = List.from(clips);
      
      // Ensure timeline is in a proper state after update
      if (_currentClips.isNotEmpty) {
        // Set to paused state to ensure pipeline is ready
        await timelineComposerPause(handle: _timelineComposerHandle!);
        
        // Give the timeline time to process
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      // Clear cache when timeline changes significantly
      if (_hasSignificantTimelineChange(clips)) {
        _frameCache.clearCache();
        logInfo(_logTag, 'Cleared cache due to significant timeline change');
      }

      // Immediately start caching current frame and nearby frames
      if (_currentClips.isNotEmpty) {
        // Cache current frame first (high priority)
        _frameCache.getFrame(
          _currentFrame,
          _currentClips,
          preferredQuality: CacheQuality.high,
        );
        
        // Cache surrounding frames for smooth playback
        _cacheFrameRange(_currentFrame - 5, _currentFrame + 30);
      }

      // Warm up cache for current area
      _scheduleWarmupCache();
      
      _performanceStatusNotifier.value = 'Timeline updated';
      
    } catch (e) {
      logError(_logTag, 'Failed to update timeline: $e');
      _performanceStatusNotifier.value = 'Update failed: $e';
    } finally {
      _isRenderingNotifier.value = false;
    }
  }

  bool _hasSignificantTimelineChange(List<ClipModel> newClips) {
    if (newClips.length != _currentClips.length) return true;
    
    // Check if any clip sources or positions changed significantly
    for (int i = 0; i < newClips.length; i++) {
      final newClip = newClips[i];
      final oldClip = _currentClips[i];
      
      if (newClip.sourcePath != oldClip.sourcePath ||
          newClip.startTimeOnTrackMs != oldClip.startTimeOnTrackMs ||
          newClip.effects.length != oldClip.effects.length) {
        return true;
      }
    }
    
    return false;
  }

  TimelineClipData _clipToTimelineData(ClipModel clip) {
    return TimelineClipData(
      id: clip.databaseId ?? 0,
      trackId: clip.trackId,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: clip.startTimeOnTrackMs,
      endTimeOnTrackMs: clip.endTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
      sourceDurationMs: clip.sourceDurationMs,
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required int currentFrame,
    double playbackSpeed = 1.0,
  }) {
    final stateChanged = _isPlaying != isPlaying || 
                        _currentFrame != currentFrame || 
                        _playbackSpeed != playbackSpeed;

    _isPlaying = isPlaying;
    _currentFrame = currentFrame;
    _playbackSpeed = playbackSpeed;

    if (stateChanged) {
      // Update timeline composer
      _syncTimelineComposerState();
      
      // Update frame cache context
      _frameCache.updatePlaybackContext(
        isPlaying: isPlaying,
        currentFrame: currentFrame,
        clips: _currentClips,
        playbackSpeed: playbackSpeed,
      );

      // Actively cache frames when position changes
      if (_currentClips.isNotEmpty) {
        // Cache current frame immediately
        _frameCache.getFrame(
          currentFrame,
          _currentClips,
          preferredQuality: _getTargetQuality(),
        );
        
        // If playing, cache ahead; if seeking, cache around position
        if (isPlaying) {
          _cacheFrameRange(currentFrame, currentFrame + 30);
        } else {
          _cacheFrameRange(currentFrame - 5, currentFrame + 15);
        }
      }

      logDebug('Updated playback state: playing=$isPlaying, frame=$currentFrame, speed=$playbackSpeed', _logTag);
    }
  }

  void _syncTimelineComposerState() {
    if (_timelineComposerHandle == null) return;

    try {
      // First ensure the pipeline is in a proper state (not Null)
      // We need to set it to paused or playing before we can seek
      if (_isPlaying) {
        timelineComposerPlay(handle: _timelineComposerHandle!);
      } else {
        timelineComposerPause(handle: _timelineComposerHandle!);
      }
      
      // Small delay to allow state change to take effect
      Future.delayed(Duration(milliseconds: 10), () {
        try {
          final currentTimeMs = ClipModel.framesToMs(_currentFrame);
          timelineComposerSeek(handle: _timelineComposerHandle!, positionMs: currentTimeMs);
          logDebug('Timeline composer sync completed: playing=$_isPlaying, frame=$_currentFrame', _logTag);
        } catch (seekError) {
          logError(_logTag, 'Failed to seek during sync: $seekError');
        }
      });
      
    } catch (e) {
      logError(_logTag, 'Failed to sync timeline composer state: $e');
    }
  }

  void _updateCurrentFrame() {
    if (_currentClips.isEmpty) return;

    _updateFrameFromCache();
    _updatePerformanceStatus();
  }

  Future<void> _updateFrameFromCache() async {
    if (_isRenderingNotifier.value) return; // Skip if already rendering

    final quality = _getTargetQuality();
    
    try {
      final cachedFrame = await _frameCache.getFrame(
        _currentFrame,
        _currentClips,
        preferredQuality: quality,
        timeout: const Duration(milliseconds: 100), // Quick timeout during playback
      );

      if (cachedFrame != null) {
        _latestFrameData = cachedFrame.frameData;
        _latestFrameWidth = cachedFrame.width;
        _latestFrameHeight = cachedFrame.height;
        
        logDebug('Using cached frame ${cachedFrame.frameNumber} at ${cachedFrame.quality.name} quality', _logTag);
      } else {
        // Fallback to direct timeline composer if cache fails
        await _fallbackToDirectRender();
      }
    } catch (e) {
      logError(_logTag, 'Error getting frame from cache: $e');
      await _fallbackToDirectRender();
    }
  }

  CacheQuality _getTargetQuality() {
    if (!_isPlaying) {
      return CacheQuality.high; // Full quality when paused
    }

    final stats = _frameCache.getCacheStatistics();
    final avgRenderTime = stats['averageRenderTimeMs'] as double;
    
    // Adaptive quality based on performance
    if (avgRenderTime > 50) {
      return CacheQuality.proxy;
    } else if (avgRenderTime > 30) {
      return CacheQuality.low;
    } else {
      return CacheQuality.medium;
    }
  }

  Future<void> _fallbackToDirectRender() async {
    if (_timelineComposerHandle == null) return;

    try {
      final frameData = timelineComposerGetLatestFrame(handle: _timelineComposerHandle!);
      if (frameData != null) {
        _latestFrameData = Uint8List.fromList(frameData.data);
        _latestFrameWidth = frameData.width;
        _latestFrameHeight = frameData.height;
        
        logDebug('Used direct render fallback for frame $_currentFrame', _logTag);
      }
    } catch (e) {
      logError(_logTag, 'Direct render fallback failed: $e');
    }
  }

  void _updatePerformanceStatus() {
    final stats = _frameCache.getCacheStatistics();
    final hitRate = stats['hitRate'] as double;
    final cacheSize = (stats['cacheSizeMB'] as double).toStringAsFixed(1);
    final activeRenderers = stats['activeRenderers'] as int;
    
    if (_isPlaying) {
      _performanceStatusNotifier.value = 
          'Playing • Cache: ${(hitRate * 100).toStringAsFixed(1)}% hit rate • ${cacheSize}MB • $activeRenderers active renderers';
    } else {
      _performanceStatusNotifier.value = 
          'Paused • Cache: ${cacheSize}MB • ${stats['cacheEntries']} frames cached';
    }
  }

  void _scheduleWarmupCache() {
    _cacheWarmupTimer?.cancel();
    _cacheWarmupTimer = Timer(_cacheWarmupDelay, () {
      if (_currentClips.isNotEmpty) {
        // More aggressive warmup - cache a larger range
        _frameCache.warmupCache(
          _currentClips,
          startFrame: (_currentFrame - 10).clamp(0, double.infinity).toInt(),
          frameCount: 120, // 4 seconds at 30fps
        );
        
        logInfo(_logTag, 'Warmed up cache around frame $_currentFrame');
      }
    });
  }

  void _cacheFrameRange(int startFrame, int endFrame) {
    final actualStart = startFrame.clamp(0, double.infinity).toInt();
    final quality = _getTargetQuality();
    
    for (int frame = actualStart; frame <= endFrame; frame++) {
      _frameCache.getFrame(
        frame,
        _currentClips,
        preferredQuality: quality,
      );
    }
    
    logDebug('Caching frame range $actualStart to $endFrame at ${quality.name} quality', _logTag);
  }

  // Public API for getting latest frame data (for texture updates)
  
  Uint8List? getLatestFrameData() => _latestFrameData;
  int getLatestFrameWidth() => _latestFrameWidth;
  int getLatestFrameHeight() => _latestFrameHeight;
  
  bool hasFrameData() => _latestFrameData != null;

  // Seek operations with cache optimization

  /// Seek to frame with cache optimization
  Future<void> seekToFrame(int frameNumber) async {
    // Validate frame number
    if (frameNumber < 0) {
      logError(_logTag, 'Cannot seek to negative frame: $frameNumber');
      return;
    }
    
    // Check if we have clips
    if (_currentClips.isEmpty) {
      logDebug('No clips available for seek to frame $frameNumber', _logTag);
      return;
    }
    
    // Calculate timeline bounds
    final timelineDurationMs = _currentClips.map((c) => c.endTimeOnTrackMs).reduce((a, b) => a > b ? a : b);
    final maxFrames = ClipModel.msToFrames(timelineDurationMs);
    
    if (frameNumber >= maxFrames) {
      logWarning(_logTag, 'Cannot seek to frame $frameNumber, beyond timeline duration (max: $maxFrames frames)');
      return;
    }
    
    _currentFrame = frameNumber;
    
    // Try to get frame from cache immediately
    final cachedFrame = await _frameCache.getFrame(
      frameNumber,
      _currentClips,
      preferredQuality: CacheQuality.high,
      timeout: const Duration(milliseconds: 500),
    );

    if (cachedFrame != null) {
      _latestFrameData = cachedFrame.frameData;
      _latestFrameWidth = cachedFrame.width;
      _latestFrameHeight = cachedFrame.height;
    }

    // Update timeline composer position
    if (_timelineComposerHandle != null) {
      try {
        final timeMs = ClipModel.framesToMs(frameNumber);
        
        // Additional validation for timeline composer and GStreamer constraints
        if (timeMs < 0) {
          logError(_logTag, 'Cannot seek to negative time: ${timeMs}ms');
          return;
        }
        
        if (timeMs > timelineDurationMs) {
          logWarning(_logTag, 'Seek time ${timeMs}ms exceeds timeline duration ${timelineDurationMs}ms');
          return;
        }
        
        // Ensure minimum duration for GStreamer segments and clamp to valid range
        final clampedTimeMs = timeMs.clamp(0, (timelineDurationMs - 1).clamp(0, double.infinity)).round();
        
        // Additional safety check for empty timeline
        if (timelineDurationMs <= 0) {
          logWarning(_logTag, 'Cannot seek on empty timeline');
          return;
        }
        
        // Ensure pipeline is in a proper state before seeking
        // Set to paused state first to ensure it's not in Null state
        await timelineComposerPause(handle: _timelineComposerHandle!);
        
        // Small delay to allow state change
        await Future.delayed(Duration(milliseconds: 20));
        
        await timelineComposerSeek(handle: _timelineComposerHandle!, positionMs: clampedTimeMs);
        logDebug('Timeline composer seek completed for frame $frameNumber (${clampedTimeMs}ms)', _logTag);
      } catch (e) {
        logError(_logTag, 'Seek failed for frame $frameNumber: $e');
      }
    }
  }

  // Quality and performance controls

  void setQualityMode(CacheQuality quality) {
    // Clear cache to force re-render at new quality
    _frameCache.clearCache();
    logInfo(_logTag, 'Set quality mode to ${quality.name}');
  }

  void clearCache() {
    _frameCache.clearCache();
    logInfo(_logTag, 'Cache cleared');
  }

  void preRenderRegion(int startFrame, int endFrame, {CacheQuality quality = CacheQuality.medium}) {
    for (int frame = startFrame; frame <= endFrame; frame++) {
      _frameCache.getFrame(frame, _currentClips, preferredQuality: quality);
    }
    logInfo(_logTag, 'Pre-rendering frames $startFrame to $endFrame at ${quality.name} quality');
  }

  // Lifecycle management

  void dispose() {
    logInfo(_logTag, 'Disposing cached timeline composer');
    
    _frameUpdateTimer?.cancel();
    _cacheWarmupTimer?.cancel();
    
    _frameCache.dispose();
    
    if (_timelineComposerHandle != null) {
      try {
        timelineComposerDispose(handle: _timelineComposerHandle!);
      } catch (e) {
        logError(_logTag, 'Error disposing timeline composer: $e');
      }
    }
    
    _isRenderingNotifier.dispose();
    _performanceStatusNotifier.dispose();
  }
} 