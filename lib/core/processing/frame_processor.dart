import 'dart:async';

import 'package:flipedit/models/interfaces/clip_interface.dart';

/// Handles frame processing and caching for the video editor
class FrameProcessor {
  /// In-memory frame cache
  final Map<String, Map<int, Map<String, dynamic>>> _frameCache = {};
  
  /// Maximum number of frames to keep in cache per clip
  final int maxCacheSize;
  
  FrameProcessor({
    this.maxCacheSize = 30, // Cache about 1 second at 30fps
  });
  
  /// Process a frame from a clip and cache the result
  Future<Map<String, dynamic>> getProcessedFrame(IClip clip, int framePosition) async {
    final cacheKey = _getCacheKey(clip, framePosition);
    
    // Check if frame is already in cache
    if (_isFrameCached(clip.id, framePosition)) {
      return _getCachedFrame(clip.id, framePosition);
    }
    
    // Process the frame
    final processedFrame = await clip.getProcessedFrame(framePosition);
    
    // Store in cache
    _cacheFrame(clip.id, framePosition, processedFrame);
    
    return processedFrame;
  }
  
  /// Pre-cache a range of frames for smoother playback
  Future<void> preloadFrames(IClip clip, int startFrame, int endFrame) async {
    // Process frames in the background
    final List<Future<void>> futures = [];
    for (int i = startFrame; i <= endFrame; i++) {
      if (!_isFrameCached(clip.id, i)) {
        // Use compute to run in a separate isolate for heavy processing
        futures.add(_processAndCacheFrame(clip, i));
      }
    }
    // Wait for all preloaded frames to complete
    await Future.wait(futures);
  }
  
  Future<void> _processAndCacheFrame(IClip clip, int framePosition) async {
    try {
      // In a production app, you would use compute() here:
      // final processedFrame = await compute(_isolateProcessFrame, {clip, framePosition});
      final processedFrame = await clip.getProcessedFrame(framePosition);
      _cacheFrame(clip.id, framePosition, processedFrame);
    } catch (e, stackTrace) {
      Logger.e('FrameProcessor', 'Error preloading frame at position $framePosition for clip ${clip.id}', e, stackTrace);
      // Don't rethrow for preloading - just log the error
    }
  }
  
  /// Clear cache for a specific clip
  void clearCache(String clipId) {
    _frameCache.remove(clipId);
  }
  
  /// Clear all cached frames
  void clearAllCache() {
    _frameCache.clear();
  }
  
  /// Generate a unique key for frame caching
  String _getCacheKey(IClip clip, int framePosition) {
    return '${clip.id}_$framePosition';
  }
  
  /// Check if a frame is in the cache
  bool _isFrameCached(String clipId, int framePosition) {
    return _frameCache.containsKey(clipId) && 
           _frameCache[clipId]!.containsKey(framePosition);
  }
  
  /// Get a cached frame
  Map<String, dynamic> _getCachedFrame(String clipId, int framePosition) {
    return Map<String, dynamic>.from(_frameCache[clipId]![framePosition]!);
  }
  
  /// Store a frame in the cache
  void _cacheFrame(String clipId, int framePosition, Map<String, dynamic> frameData) {
    // Initialize clip entry if it doesn't exist
    _frameCache[clipId] ??= {};
    
    // Add the frame
    _frameCache[clipId]![framePosition] = frameData;
    
    // Manage cache size
    _pruneCache(clipId);
  }
  
  /// Remove oldest frames if cache exceeds maximum size
  void _pruneCache(String clipId) {
    final clipCache = _frameCache[clipId]!;
    
    if (clipCache.length > maxCacheSize) {
      // Sort frames by position
      final framePositions = clipCache.keys.toList()..sort();
      
      // Remove oldest frames
      final framesToRemove = framePositions.length - maxCacheSize;
      for (int i = 0; i < framesToRemove; i++) {
        clipCache.remove(framePositions[i]);
      }
    }
  }
}
