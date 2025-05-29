import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/src/rust/video/timeline_composer.dart';
import 'package:flipedit/utils/logger.dart';

enum CacheQuality {
  proxy(scale: 0.25, suffix: '_proxy'),
  low(scale: 0.5, suffix: '_low'),
  medium(scale: 0.75, suffix: '_medium'),
  high(scale: 1.0, suffix: '_high');

  const CacheQuality({required this.scale, required this.suffix});
  
  final double scale;
  final String suffix;
}

enum RenderPriority {
  immediate,    // Currently visible frame
  upcoming,     // Next few frames for smooth playback
  background,   // Frames ahead of playhead
  idle          // When system is idle
}

class CachedFrame {
  final int frameNumber;
  final CacheQuality quality;
  final Uint8List frameData;
  final int width;
  final int height;
  final DateTime timestamp;
  final Duration renderTime;
  int accessCount = 0;
  DateTime lastAccess;

  CachedFrame({
    required this.frameNumber,
    required this.quality,
    required this.frameData,
    required this.width,
    required this.height,
    required this.renderTime,
  }) : timestamp = DateTime.now(),
       lastAccess = DateTime.now();

  String get cacheKey => '${frameNumber}_${quality.suffix}';
  
  int get sizeBytes => frameData.length;
  
  void markAccessed() {
    lastAccess = DateTime.now();
    accessCount++;
  }
}

class FrameRenderRequest {
  final int frameNumber;
  final CacheQuality quality;
  final RenderPriority priority;
  final List<ClipModel> clips;
  final Completer<CachedFrame?> completer;
  final DateTime requestTime;

  FrameRenderRequest({
    required this.frameNumber,
    required this.quality,
    required this.priority,
    required this.clips,
  }) : completer = Completer<CachedFrame?>(),
       requestTime = DateTime.now();

  String get cacheKey => '${frameNumber}_${quality.suffix}';
}

class FrameCacheService {
  static const int _maxCacheSizeMB = 512; // 512MB max cache
  static const int _maxCacheEntries = 1000;
  static const int _prerollFrames = 30; // Frames to cache ahead
  static const Duration _cacheCleanupInterval = Duration(seconds: 30);

  final String _logTag = 'FrameCacheService';
  
  // LRU Cache using LinkedHashMap for O(1) access and ordering
  final LinkedHashMap<String, CachedFrame> _frameCache = LinkedHashMap();
  
  // Render queue with priority ordering
  final List<FrameRenderRequest> _renderQueue = [];
  
  // Background workers
  final List<_FrameRenderer> _renderers = [];
  
  // Cache statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalFramesRendered = 0;
  
  // Performance tracking
  final List<Duration> _recentRenderTimes = [];
  final ValueNotifier<double> _averageRenderTimeNotifier = ValueNotifier(0.0);
  final ValueNotifier<int> _cacheSizeBytesNotifier = ValueNotifier(0);
  
  // Cleanup timer
  Timer? _cleanupTimer;
  
  // Current playback context
  bool _isPlaying = false;
  int _currentFrame = 0;
  double _playbackSpeed = 1.0;

  FrameCacheService() {
    _initializeRenderers();
    _startCleanupTimer();
    logInfo(_logTag, 'FrameCacheService initialized with ${_renderers.length} renderers');
  }

  void _initializeRenderers() {
    // Create background rendering workers
    const int workerCount = 2; // Adjust based on target device capabilities
    
    for (int i = 0; i < workerCount; i++) {
      final renderer = _FrameRenderer(
        id: i,
        onFrameRendered: _onFrameRendered,
        onRenderError: _onRenderError,
      );
      _renderers.add(renderer);
      logDebug('Created FrameRenderer_$i', _logTag);
    }
    
    logInfo(_logTag, 'Initialized $workerCount frame renderers');
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(_cacheCleanupInterval, (_) => _cleanupCache());
  }

  // Main API methods

  /// Get frame with automatic quality fallback
  Future<CachedFrame?> getFrame(
    int frameNumber, 
    List<ClipModel> clips, {
    CacheQuality preferredQuality = CacheQuality.high,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    logDebug('Cache request for frame $frameNumber at ${preferredQuality.name} quality', _logTag);
    
    // Validate input parameters
    if (frameNumber < 0) {
      logError(_logTag, 'Invalid frame number: $frameNumber');
      return null;
    }
    
    if (clips.isEmpty) {
      logDebug('No clips provided for frame $frameNumber, skipping cache request', _logTag);
      return null;
    }
    
    // Calculate timeline bounds to validate frame request
    final timelineDurationMs = clips.map((c) => c.endTimeOnTrackMs).reduce((a, b) => a > b ? a : b);
    final maxFrames = ClipModel.msToFrames(timelineDurationMs);
    
    if (frameNumber >= maxFrames) {
      logDebug('Frame $frameNumber is beyond timeline duration (max: $maxFrames frames), skipping cache request', _logTag);
      return null;
    }
    
    final requestKey = '${frameNumber}_${preferredQuality.suffix}';
    
    // Check cache first
    if (_frameCache.containsKey(requestKey)) {
      final cached = _frameCache[requestKey]!;
      cached.markAccessed();
      _moveToHead(requestKey); // LRU update
      _cacheHits++;
      
      logDebug('Cache hit for frame $frameNumber at ${preferredQuality.name} quality', _logTag);
      return cached;
    }

    // Check for lower quality versions
    for (final quality in CacheQuality.values.reversed) {
      if (quality.scale < preferredQuality.scale) {
        final fallbackKey = '${frameNumber}_${quality.suffix}';
        if (_frameCache.containsKey(fallbackKey)) {
          final cached = _frameCache[fallbackKey]!;
          cached.markAccessed();
          _moveToHead(fallbackKey);
          _cacheHits++;
          
          logDebug('Cache hit with quality fallback: frame $frameNumber, ${quality.name} instead of ${preferredQuality.name}', _logTag);
          
          // Queue higher quality render in background
          _queueRender(frameNumber, preferredQuality, clips, RenderPriority.background);
          
          return cached;
        }
      }
    }

    _cacheMisses++;
    
    logDebug('Cache miss for frame $frameNumber, queuing for render (${clips.length} clips)', _logTag);
    
    // Not in cache - queue for immediate rendering
    final request = _queueRender(frameNumber, preferredQuality, clips, RenderPriority.immediate);
    
    logDebug('Queued frame $frameNumber for rendering, queue length: ${_renderQueue.length}', _logTag);
    
    try {
      return await request.completer.future.timeout(timeout);
    } catch (e) {
      logError(_logTag, 'Timeout waiting for frame $frameNumber: $e');
      return null;
    }
  }

  /// Update playback context for intelligent prerendering
  void updatePlaybackContext({
    required bool isPlaying,
    required int currentFrame,
    required List<ClipModel> clips,
    double playbackSpeed = 1.0,
  }) {
    _isPlaying = isPlaying;
    _currentFrame = currentFrame;
    _playbackSpeed = playbackSpeed;

    if (isPlaying) {
      _schedulePrerollFrames(currentFrame, clips);
    }
  }

  /// Prerender frames around the current position
  void _schedulePrerollFrames(int currentFrame, List<ClipModel> clips) {
    if (clips.isEmpty) {
      logDebug('No clips available for preroll scheduling', _logTag);
      return;
    }
    
    // Calculate timeline bounds
    final timelineDurationMs = clips.map((c) => c.endTimeOnTrackMs).reduce((a, b) => a > b ? a : b);
    final maxFrames = ClipModel.msToFrames(timelineDurationMs);
    
    final framesToCache = (_prerollFrames * _playbackSpeed).round();
    final quality = _getOptimalQualityForPlayback();

    // Cache upcoming frames
    for (int i = 1; i <= framesToCache; i++) {
      final frameNumber = currentFrame + i;
      
      // Skip frames beyond timeline
      if (frameNumber >= maxFrames) {
        break;
      }
      
      final cacheKey = '${frameNumber}_${quality.suffix}';
      
      if (!_frameCache.containsKey(cacheKey) && !_isFrameQueued(frameNumber, quality)) {
        _queueRender(frameNumber, quality, clips, RenderPriority.upcoming);
      }
    }

    // Cache a few frames behind for scrubbing
    for (int i = 1; i <= 5; i++) {
      final frameNumber = currentFrame - i;
      if (frameNumber >= 0) {
        final cacheKey = '${frameNumber}_${quality.suffix}';
        
        if (!_frameCache.containsKey(cacheKey) && !_isFrameQueued(frameNumber, quality)) {
          _queueRender(frameNumber, quality, clips, RenderPriority.background);
        }
      }
    }
  }

  /// Get optimal quality based on current performance and playback state
  CacheQuality _getOptimalQualityForPlayback() {
    if (!_isPlaying) {
      return CacheQuality.high; // Full quality when paused
    }

    final avgRenderTime = _averageRenderTimeNotifier.value;
    const targetFrameTime = 33.33; // 30fps = 33.33ms per frame

    if (avgRenderTime > targetFrameTime * 2) {
      return CacheQuality.proxy; // Very slow rendering
    } else if (avgRenderTime > targetFrameTime) {
      return CacheQuality.low; // Moderate performance
    } else {
      return CacheQuality.medium; // Good performance
    }
  }

  // Queue management

  FrameRenderRequest _queueRender(
    int frameNumber,
    CacheQuality quality,
    List<ClipModel> clips,
    RenderPriority priority,
  ) {
    final request = FrameRenderRequest(
      frameNumber: frameNumber,
      quality: quality,
      priority: priority,
      clips: clips,
    );
    
    // Insert request based on priority
    int insertIndex = _renderQueue.length;
    for (int i = 0; i < _renderQueue.length; i++) {
      if (request.priority.index < _renderQueue[i].priority.index) {
        insertIndex = i;
        break;
      }
    }
    
    _renderQueue.insert(insertIndex, request);
    logDebug('Queued frame $frameNumber (${quality.name}, ${priority.name}) at index $insertIndex. Queue length: ${_renderQueue.length}', _logTag);
    
    // Trigger work distribution
    _distributeWork();
    
    return request;
  }

  bool _isFrameQueued(int frameNumber, CacheQuality quality) {
    final cacheKey = '${frameNumber}_${quality.suffix}';
    return _renderQueue.any((req) => req.cacheKey == cacheKey);
  }

  void _distributeWork() {
    if (_renderQueue.isEmpty) {
      logDebug('No work to distribute - queue is empty', _logTag);
      return;
    }
    
    // Find available renderers
    final availableRenderers = _renderers.where((r) => !r.isBusy).toList();
    
    if (availableRenderers.isEmpty) {
      logDebug('No available renderers - all ${_renderers.length} are busy', _logTag);
      return;
    }
    
    logDebug('Distributing work: ${_renderQueue.length} queued, ${availableRenderers.length}/${_renderers.length} renderers available', _logTag);
    
    // Assign work to available renderers
    while (_renderQueue.isNotEmpty && availableRenderers.isNotEmpty) {
      final request = _renderQueue.removeAt(0);
      final renderer = availableRenderers.removeAt(0);
      
      logDebug('Assigning frame ${request.frameNumber} to renderer ${renderer.id}', _logTag);
      renderer.processRequest(request);
    }
  }

  // Callbacks from renderers

  void _onFrameRendered(FrameRenderRequest request, CachedFrame frame) {
    logInfo(_logTag, 'Frame ${frame.frameNumber} rendered and cached (${frame.sizeBytes} bytes, ${frame.renderTime.inMilliseconds}ms)');
    
    _addToCache(frame);
    _updateRenderStats(frame.renderTime);
    _totalFramesRendered++;
    
    if (!request.completer.isCompleted) {
      request.completer.complete(frame);
    }

    logDebug('Rendered frame ${frame.frameNumber} in ${frame.renderTime.inMilliseconds}ms', _logTag);
    
    // Continue processing queue
    _distributeWork();
  }

  void _onRenderError(FrameRenderRequest request, String error) {
    logError(_logTag, 'Failed to render frame ${request.frameNumber}: $error');
    
    if (!request.completer.isCompleted) {
      request.completer.complete(null);
    }
    
    // Continue processing queue
    _distributeWork();
  }

  // Cache management

  void _addToCache(CachedFrame frame) {
    final key = frame.cacheKey;
    
    logDebug('Adding frame ${frame.frameNumber} to cache with key: $key', _logTag);
    
    // Remove if already exists (update)
    if (_frameCache.containsKey(key)) {
      _frameCache.remove(key);
      logDebug('Replaced existing cached frame: $key', _logTag);
    }
    
    // Add to head (most recent)
    _frameCache[key] = frame;
    
    logInfo(_logTag, 'Frame ${frame.frameNumber} added to cache. Cache size: ${_frameCache.length} frames');
    
    // Enforce size limits
    _enforceCacheLimits();
    
    // Update statistics
    _updateCacheStats();
  }

  void _moveToHead(String key) {
    if (_frameCache.containsKey(key)) {
      final frame = _frameCache.remove(key)!;
      _frameCache[key] = frame;
    }
  }

  void _enforceCacheLimits() {
    // Remove oldest entries if cache is too large
    while (_frameCache.length > _maxCacheEntries || _getCurrentCacheSizeBytes() > _maxCacheSizeMB * 1024 * 1024) {
      if (_frameCache.isEmpty) break;
      
      final oldestKey = _frameCache.keys.first;
      final removed = _frameCache.remove(oldestKey);
      
      logDebug('Evicted frame from cache: $oldestKey (${removed?.sizeBytes} bytes)', _logTag);
    }
  }

  int _getCurrentCacheSizeBytes() {
    return _frameCache.values.fold(0, (sum, frame) => sum + frame.sizeBytes);
  }

  void _updateCacheStats() {
    _cacheSizeBytesNotifier.value = _getCurrentCacheSizeBytes();
  }

  void _updateRenderStats(Duration renderTime) {
    _recentRenderTimes.add(renderTime);
    
    // Keep only recent measurements
    if (_recentRenderTimes.length > 100) {
      _recentRenderTimes.removeAt(0);
    }
    
    // Update average
    final avgMs = _recentRenderTimes
        .map((d) => d.inMicroseconds)
        .reduce((a, b) => a + b) / 
        _recentRenderTimes.length / 1000.0;
    
    _averageRenderTimeNotifier.value = avgMs;
  }

  void _cleanupCache() {
    final now = DateTime.now();
    const maxAge = Duration(minutes: 10);
    
    final keysToRemove = <String>[];
    
    for (final entry in _frameCache.entries) {
      if (now.difference(entry.value.lastAccess) > maxAge) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _frameCache.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      logInfo(_logTag, 'Cleaned up ${keysToRemove.length} old cache entries');
      _updateCacheStats();
    }
  }

  // Public API for cache management

  void clearCache() {
    _frameCache.clear();
    _renderQueue.clear();
    
    for (final renderer in _renderers) {
      renderer.cancelCurrent();
    }
    
    _updateCacheStats();
    logInfo(_logTag, 'Cache cleared');
  }

  void warmupCache(List<ClipModel> clips, {int startFrame = 0, int frameCount = 60}) {
    if (clips.isEmpty) {
      logDebug('No clips available for cache warmup', _logTag);
      return;
    }
    
    // Calculate timeline bounds
    final timelineDurationMs = clips.map((c) => c.endTimeOnTrackMs).reduce((a, b) => a > b ? a : b);
    final maxFrames = ClipModel.msToFrames(timelineDurationMs);
    
    // Clamp start frame and frame count to valid range
    final validStartFrame = startFrame.clamp(0, maxFrames - 1);
    final validFrameCount = (frameCount).clamp(1, maxFrames - validStartFrame);
    
    final quality = CacheQuality.medium;
    
    for (int i = 0; i < validFrameCount; i++) {
      final frameNumber = validStartFrame + i;
      
      // Extra safety check
      if (frameNumber >= maxFrames) {
        break;
      }
      
      final cacheKey = '${frameNumber}_${quality.suffix}';
      
      if (!_frameCache.containsKey(cacheKey)) {
        _queueRender(frameNumber, quality, clips, RenderPriority.idle);
      }
    }
    
    logInfo(_logTag, 'Warming up cache for $validFrameCount frames starting from $validStartFrame (timeline has $maxFrames frames)');
  }

  // Statistics and monitoring

  Map<String, dynamic> getCacheStatistics() {
    final totalBytes = _getCurrentCacheSizeBytes();
    final hitRate = _cacheHits + _cacheMisses > 0 
        ? _cacheHits / (_cacheHits + _cacheMisses) 
        : 0.0;

    return {
      'cacheEntries': _frameCache.length,
      'cacheSizeBytes': totalBytes,
      'cacheSizeMB': totalBytes / (1024 * 1024),
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': hitRate,
      'averageRenderTimeMs': _averageRenderTimeNotifier.value,
      'totalFramesRendered': _totalFramesRendered,
      'activeRenderers': _renderers.where((r) => r.isBusy).length,
      'queueLength': _renderQueue.length,
    };
  }

  void dispose() {
    _cleanupTimer?.cancel();
    
    for (final renderer in _renderers) {
      renderer.dispose();
    }
    
    _frameCache.clear();
    _renderQueue.clear();
    _averageRenderTimeNotifier.dispose();
    _cacheSizeBytesNotifier.dispose();
    
    logInfo(_logTag, 'FrameCacheService disposed');
  }
}

class _FrameRenderer {
  final int id;
  final Function(FrameRenderRequest, CachedFrame) onFrameRendered;
  final Function(FrameRenderRequest, String) onRenderError;
  
  bool _isBusy = false;
  FrameRenderRequest? _currentRequest;
  
  bool get isBusy => _isBusy;

  _FrameRenderer({
    required this.id,
    required this.onFrameRendered,
    required this.onRenderError,
  });

  void processRequest(FrameRenderRequest request) {
    if (_isBusy) return;
    
    _isBusy = true;
    _currentRequest = request;
    
    _renderFrameAsync(request);
  }

  Future<void> _renderFrameAsync(FrameRenderRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    logDebug('FrameRenderer_$id: Starting render for frame ${request.frameNumber} at ${request.quality.name} quality', 'FrameRenderer');
    
    try {
      // Validate clips before proceeding
      if (request.clips.isEmpty) {
        onRenderError(request, 'No clips provided for rendering');
        return;
      }
      
      // Validate frame number
      if (request.frameNumber < 0) {
        onRenderError(request, 'Invalid frame number: ${request.frameNumber}');
        return;
      }
      
      // Integrate with TimelineComposer for actual rendering
      final composerHandle = timelineComposerCreate();
      logDebug('FrameRenderer_$id: Created composer handle: $composerHandle', 'FrameRenderer');
      
      try {
        // Convert clips to timeline data
        final timelineClips = request.clips.map((clip) => TimelineClipData(
          id: clip.databaseId ?? 0,
          trackId: clip.trackId,
          sourcePath: clip.sourcePath,
          startTimeOnTrackMs: clip.startTimeOnTrackMs,
          endTimeOnTrackMs: clip.endTimeOnTrackMs,
          startTimeInSourceMs: clip.startTimeInSourceMs,
          endTimeInSourceMs: clip.endTimeInSourceMs,
          sourceDurationMs: clip.sourceDurationMs,
        )).toList();
        
        logDebug('FrameRenderer_$id: Converted ${request.clips.length} clips to timeline data', 'FrameRenderer');
        
        // Validate clips have valid paths
        for (final clip in timelineClips) {
          if (clip.sourcePath.isEmpty) {
            onRenderError(request, 'Clip has empty source path');
            return;
          }
        }
        
        // Update timeline with clips
        await timelineComposerUpdateTimeline(
          handle: composerHandle,
          clips: timelineClips,
        );
        
        logDebug('FrameRenderer_$id: Updated timeline composer with clips', 'FrameRenderer');
        
        // Give the timeline composer time to fully process the clips
        await Future.delayed(Duration(milliseconds: 50));
        
        // Calculate seek position and validate it
        final timeMs = ClipModel.framesToMs(request.frameNumber);
        
        // Check if the seek position is within the timeline bounds
        final timelineDurationMs = request.clips.isEmpty ? 0 : 
          request.clips.map((c) => c.endTimeOnTrackMs).reduce((a, b) => a > b ? a : b);
        
        // Don't attempt to render if timeline is empty or has zero duration
        if (timelineDurationMs <= 0) {
          logDebug('FrameRenderer_$id: Timeline has zero duration, skipping render for frame ${request.frameNumber}', 'FrameRenderer');
          onRenderError(request, 'Timeline has zero duration');
          return;
        }
        
        // Additional validation for GStreamer segment constraints
        if (timeMs < 0) {
          logError('FrameRenderer_$id', 'Invalid seek position: ${timeMs}ms is negative');
          onRenderError(request, 'Invalid seek position: negative time');
          return;
        }
        
        if (timeMs > timelineDurationMs) {
          logWarning('FrameRenderer_$id', 'Seek position ${timeMs}ms is beyond timeline duration ${timelineDurationMs}ms, clamping to end');
          // Don't render frames beyond the timeline
          onRenderError(request, 'Frame ${request.frameNumber} is beyond timeline duration');
          return;
        }
        
        // Ensure minimum duration for GStreamer segments (at least 1ms)
        final clampedTimeMs = timeMs.clamp(0, timelineDurationMs - 1).round();
        
        logDebug('FrameRenderer_$id: Seeking to ${clampedTimeMs}ms (frame ${request.frameNumber}), timeline duration: ${timelineDurationMs}ms', 'FrameRenderer');
        
        // Perform the seek with error handling
        try {
          // First ensure the pipeline is in a proper state (not Null)
          // Set to paused state to ensure it can accept seek commands
          await timelineComposerPause(handle: composerHandle);
          
          // Small delay to allow state change
          await Future.delayed(Duration(milliseconds: 20));
          
          await timelineComposerSeek(handle: composerHandle, positionMs: clampedTimeMs);
          logDebug('FrameRenderer_$id: Seek completed successfully to ${clampedTimeMs}ms', 'FrameRenderer');
        } catch (seekError) {
          logError('FrameRenderer_$id', 'Seek failed for frame ${request.frameNumber} at ${clampedTimeMs}ms: $seekError');
          onRenderError(request, 'Seek failed: $seekError');
          return;
        }
        
        // Wait a moment for the seek to take effect
        await Future.delayed(Duration(milliseconds: 50));
        
        // Get the frame data
        final frameData = timelineComposerGetLatestFrame(handle: composerHandle);
        
        if (frameData != null) {
          logDebug('FrameRenderer_$id: Got frame data: ${frameData.width}x${frameData.height}, ${frameData.data.length} bytes', 'FrameRenderer');
          
          // Apply quality scaling if needed
          final originalWidth = frameData.width;
          final originalHeight = frameData.height;
          final scaledWidth = (originalWidth * request.quality.scale).round();
          final scaledHeight = (originalHeight * request.quality.scale).round();
          
          final cachedFrame = CachedFrame(
            frameNumber: request.frameNumber,
            quality: request.quality,
            frameData: Uint8List.fromList(frameData.data),
            width: scaledWidth,
            height: scaledHeight,
            renderTime: stopwatch.elapsed,
          );
          
          stopwatch.stop();
          logInfo('FrameRenderer_$id', 'Successfully rendered frame ${request.frameNumber} in ${stopwatch.elapsedMilliseconds}ms');
          onFrameRendered(request, cachedFrame);
          
        } else {
          stopwatch.stop();
          logWarning('FrameRenderer_$id', 'No frame data received for frame ${request.frameNumber}');
          onRenderError(request, 'No frame data received from timeline composer');
        }
        
        return;
        
      } finally {
        // Always dispose the temporary composer
        try {
          timelineComposerDispose(handle: composerHandle);
          logDebug('FrameRenderer_$id: Disposed composer handle $composerHandle', 'FrameRenderer');
        } catch (disposeError) {
          logError('FrameRenderer_$id', 'Error disposing composer: $disposeError');
        }
      }
      
    } catch (e) {
      stopwatch.stop();
      logError('FrameRenderer_$id', 'Render error for frame ${request.frameNumber}: $e');
      onRenderError(request, e.toString());
    } finally {
      _isBusy = false;
      _currentRequest = null;
    }
  }

  void cancelCurrent() {
    _currentRequest = null;
    _isBusy = false;
  }

  void dispose() {
    cancelCurrent();
  }
} 