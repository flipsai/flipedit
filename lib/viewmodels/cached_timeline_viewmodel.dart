import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flipedit/services/cached_timeline_composer.dart';
import 'package:flipedit/services/frame_cache_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

class CachedTimelineViewModel {
  final String _logTag = 'CachedTimelineViewModel';
  
  late final CachedTimelineComposer _composer;
  late final TimelineNavigationViewModel _navigationViewModel;
  late final TimelineStateViewModel _stateViewModel;
  
  // Performance and cache status
  final ValueNotifier<bool> _isOptimizedPlaybackEnabledNotifier = ValueNotifier(true);
  final ValueNotifier<CacheQuality> _preferredQualityNotifier = ValueNotifier(CacheQuality.high);
  final ValueNotifier<String> _cacheStatusNotifier = ValueNotifier('Initializing...');
  
  // Frame data for UI
  final ValueNotifier<bool> _hasFrameDataNotifier = ValueNotifier(false);
  
  // Listeners
  VoidCallback? _playbackListener;
  VoidCallback? _frameListener;
  VoidCallback? _clipsListener;
  
  // State tracking
  bool _isDisposed = false;
  Timer? _statusUpdateTimer;

  CachedTimelineViewModel() {
    _initializeViewModel();
  }

  // Public getters
  ValueListenable<bool> get isOptimizedPlaybackEnabledNotifier => _isOptimizedPlaybackEnabledNotifier;
  ValueListenable<CacheQuality> get preferredQualityNotifier => _preferredQualityNotifier;
  ValueListenable<String> get cacheStatusNotifier => _cacheStatusNotifier;
  ValueListenable<bool> get hasFrameDataNotifier => _hasFrameDataNotifier;
  ValueListenable<bool> get isRenderingNotifier => _composer.isRenderingNotifier;
  ValueListenable<String> get performanceStatusNotifier => _composer.performanceStatusNotifier;
  
  Map<String, dynamic> get cacheStatistics => _composer.cacheStatistics;

  void _initializeViewModel() {
    try {
      // Initialize composer
      _composer = CachedTimelineComposer();
      
      // Get dependencies
      _navigationViewModel = di<TimelineNavigationViewModel>();
      _stateViewModel = di<TimelineStateViewModel>();
      
      // Set up listeners
      _setupListeners();
      
      // Start status updates
      _startStatusUpdates();
      
      logInfo(_logTag, 'Cached timeline viewmodel initialized');
      
    } catch (e) {
      logError(_logTag, 'Failed to initialize cached timeline viewmodel: $e');
      _cacheStatusNotifier.value = 'Initialization failed: $e';
    }
  }

  void _setupListeners() {
    // Listen to playback state changes
    _playbackListener = _onPlaybackStateChanged;
    _navigationViewModel.isPlayingNotifier.addListener(_playbackListener!);
    
    // Listen to frame changes
    _frameListener = _onFrameChanged;
    _navigationViewModel.currentFrameNotifier.addListener(_frameListener!);
    
    // Listen to clips changes
    _clipsListener = _onClipsChanged;
    _stateViewModel.clipsNotifier.addListener(_clipsListener!);
    
    // Initial state sync
    _syncInitialState();
  }

  void _syncInitialState() {
    // Update composer with current state
    _updateComposerPlaybackState();
    _onClipsChanged(); // Sync current clips
    
    // Immediately start caching if we have clips
    final clips = _stateViewModel.clipsNotifier.value;
    if (clips.isNotEmpty) {
      final currentFrame = _navigationViewModel.currentFrameNotifier.value;
      
      // Trigger initial frame caching
      Future.delayed(Duration(milliseconds: 500), () {
        if (!_isDisposed) {
          warmupCurrentRegion(frameRadius: 60); // Cache a larger area initially
          logInfo(_logTag, 'Started initial cache warmup');
        }
      });
    }
  }

  void _onPlaybackStateChanged() {
    if (_isDisposed) return;
    _updateComposerPlaybackState();
  }

  void _onFrameChanged() {
    if (_isDisposed) return;
    _updateComposerPlaybackState();
    _updateFrameDataStatus();
  }

  void _onClipsChanged() {
    if (_isDisposed) return;
    
    final clips = _stateViewModel.clipsNotifier.value;
    _composer.updateTimeline(clips).then((_) {
      if (!_isDisposed) {
        _updateComposerPlaybackState();
        logDebug('Updated timeline with ${clips.length} clips', _logTag);
      }
    }).catchError((e) {
      logError(_logTag, 'Failed to update timeline: $e');
    });
  }

  void _updateComposerPlaybackState() {
    if (_isDisposed) return;
    
    _composer.updatePlaybackState(
      isPlaying: _navigationViewModel.isPlayingNotifier.value,
      currentFrame: _navigationViewModel.currentFrameNotifier.value,
      playbackSpeed: 1.0, // TODO: Get from navigation viewmodel if available
    );
  }

  void _updateFrameDataStatus() {
    _hasFrameDataNotifier.value = _composer.hasFrameData();
  }

  void _startStatusUpdates() {
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateCacheStatus());
  }

  void _updateCacheStatus() {
    if (_isDisposed) return;
    
    final stats = _composer.cacheStatistics;
    final hitRate = stats['hitRate'] as double;
    final cacheSize = (stats['cacheSizeMB'] as double).toStringAsFixed(1);
    final cacheEntries = stats['cacheEntries'] as int;
    
    _cacheStatusNotifier.value = 
        '${cacheEntries} frames cached • ${cacheSize}MB • ${(hitRate * 100).toStringAsFixed(1)}% hit rate';
  }

  // Public API methods

  Future<void> setTexturePtr(int ptr) async {
    try {
      await _composer.setTexturePtr(ptr);
      logDebug('Set texture pointer: $ptr', _logTag);
    } catch (e) {
      logError(_logTag, 'Failed to set texture pointer: $e');
    }
  }

  /// Get latest frame data for texture rendering
  ({Uint8List? data, int width, int height}) getLatestFrameData() {
    return (
      data: _composer.getLatestFrameData(),
      width: _composer.getLatestFrameWidth(),
      height: _composer.getLatestFrameHeight(),
    );
  }

  /// Enable or disable optimized playback
  void setOptimizedPlaybackEnabled(bool enabled) {
    _isOptimizedPlaybackEnabledNotifier.value = enabled;
    
    if (enabled) {
      logInfo(_logTag, 'Optimized playback enabled');
    } else {
      logInfo(_logTag, 'Optimized playback disabled - using direct rendering');
      _composer.clearCache();
    }
  }

  /// Set preferred cache quality
  void setPreferredQuality(CacheQuality quality) {
    _preferredQualityNotifier.value = quality;
    _composer.setQualityMode(quality);
    logInfo(_logTag, 'Set preferred quality to ${quality.name}');
  }

  /// Pre-render a specific region for smooth playback
  void preRenderRegion(int startFrame, int endFrame, {CacheQuality? quality}) {
    final targetQuality = quality ?? _preferredQualityNotifier.value;
    _composer.preRenderRegion(startFrame, endFrame, quality: targetQuality);
    logInfo(_logTag, 'Pre-rendering frames $startFrame to $endFrame');
  }

  /// Warm up cache around current position
  void warmupCurrentRegion({int frameRadius = 30}) {
    final currentFrame = _navigationViewModel.currentFrameNotifier.value;
    final startFrame = (currentFrame - frameRadius).clamp(0, double.infinity).toInt();
    final endFrame = currentFrame + frameRadius;
    
    preRenderRegion(startFrame, endFrame);
  }

  /// Clear all cached frames
  void clearCache() {
    _composer.clearCache();
    logInfo(_logTag, 'Cache cleared manually');
  }

  /// Debug method to force cache frames around current position
  void debugForceCacheFrames({int frameRadius = 30}) {
    final currentFrame = _navigationViewModel.currentFrameNotifier.value;
    final clips = _stateViewModel.clipsNotifier.value;
    
    if (clips.isNotEmpty) {
      logInfo(_logTag, 'Debug: Force caching ${frameRadius * 2} frames around $currentFrame');
      
      // Force cache frames immediately
      for (int i = -frameRadius; i <= frameRadius; i++) {
        final frame = currentFrame + i;
        if (frame >= 0) {
          _composer.preRenderRegion(frame, frame, quality: CacheQuality.medium);
        }
      }
    }
  }

  /// Seek with cache optimization
  Future<void> seekToFrame(int frameNumber) async {
    try {
      await _composer.seekToFrame(frameNumber);
      
      // Update navigation viewmodel
      _navigationViewModel.currentFrame = frameNumber;
      
      logDebug('Seeked to frame $frameNumber with cache optimization', _logTag);
    } catch (e) {
      logError(_logTag, 'Failed to seek to frame $frameNumber: $e');
    }
  }

  /// Get performance recommendations based on current system performance
  List<String> getPerformanceRecommendations() {
    final stats = _composer.cacheStatistics;
    final recommendations = <String>[];
    
    final hitRate = stats['hitRate'] as double;
    final avgRenderTime = stats['averageRenderTimeMs'] as double;
    final cacheSize = stats['cacheSizeMB'] as double;
    
    if (hitRate < 0.7) {
      recommendations.add('Low cache hit rate (${(hitRate * 100).toStringAsFixed(1)}%). Consider pre-rendering or reducing playback speed.');
    }
    
    if (avgRenderTime > 50) {
      recommendations.add('Slow rendering (${avgRenderTime.toStringAsFixed(1)}ms/frame). Try lowering quality or simplifying effects.');
    }
    
    if (cacheSize > 400) {
      recommendations.add('Large cache size (${cacheSize.toStringAsFixed(1)}MB). Consider reducing cache size or clearing unused frames.');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Performance is optimal.');
    }
    
    return recommendations;
  }

  /// Export cache statistics for debugging
  Map<String, dynamic> getDetailedStatistics() {
    final stats = _composer.cacheStatistics;
    final navigation = {
      'currentFrame': _navigationViewModel.currentFrameNotifier.value,
      'isPlaying': _navigationViewModel.isPlayingNotifier.value,
    };
    
    final clips = {
      'clipCount': _stateViewModel.clipsNotifier.value.length,
      'totalDuration': _stateViewModel.clipsNotifier.value.fold(0, (sum, clip) => sum + clip.durationOnTrackMs),
    };
    
    return {
      'cache': stats,
      'navigation': navigation,
      'clips': clips,
      'optimizations': {
        'optimizedPlaybackEnabled': _isOptimizedPlaybackEnabledNotifier.value,
        'preferredQuality': _preferredQualityNotifier.value.name,
      },
      'recommendations': getPerformanceRecommendations(),
    };
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    logInfo(_logTag, 'Disposing cached timeline viewmodel');
    
    // Remove listeners
    if (_playbackListener != null) {
      _navigationViewModel.isPlayingNotifier.removeListener(_playbackListener!);
    }
    if (_frameListener != null) {
      _navigationViewModel.currentFrameNotifier.removeListener(_frameListener!);
    }
    if (_clipsListener != null) {
      _stateViewModel.clipsNotifier.removeListener(_clipsListener!);
    }
    
    // Cancel timers
    _statusUpdateTimer?.cancel();
    
    // Dispose composer
    _composer.dispose();
    
    // Dispose notifiers
    _isOptimizedPlaybackEnabledNotifier.dispose();
    _preferredQualityNotifier.dispose();
    _cacheStatusNotifier.dispose();
    _hasFrameDataNotifier.dispose();
  }
} 