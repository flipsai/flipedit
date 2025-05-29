# Frame Cache Integration Guide

## Overview

The FlipEdit frame cache system provides intelligent prerendering and caching strategies to solve slow compositing during video playback. This system implements common video editor optimization techniques including background rendering, quality-adaptive playback, and smart cache management.

## Architecture

### Components

1. **FrameCacheService** - Core caching engine with LRU cache and background workers
2. **CachedTimelineComposer** - Enhanced timeline composer with cache integration
3. **CachedTimelineViewModel** - MVVM layer for UI integration

### Cache Quality Levels

- **Proxy (25%)** - Fastest rendering for very slow systems
- **Low (50%)** - Good performance/quality balance for slower systems  
- **Medium (75%)** - Good quality for normal performance
- **High (100%)** - Full quality when paused or high-performance systems

### Render Priorities

- **Immediate** - Currently visible frame (highest priority)
- **Upcoming** - Next few frames for smooth playback
- **Background** - Frames ahead of playhead
- **Idle** - When system is idle

## Integration Steps

### 1. Register the Service

Add to your dependency injection setup:

```dart
// In lib/di/dependencies.dart
void setupDependencies() {
  // ... existing dependencies
  
  // Register cached timeline viewmodel
  di.registerSingleton<CachedTimelineViewModel>(CachedTimelineViewModel());
}
```

### 2. Replace Timeline Video Player

Update your player widget to use the cached system:

```dart
// In lib/widgets/cached_timeline_video_player_widget.dart
class CachedTimelineVideoPlayerWidget extends StatefulWidget with WatchItMixin {
  const CachedTimelineVideoPlayerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final cachedViewModel = di<CachedTimelineViewModel>();
    final hasFrameData = watchValue((CachedTimelineViewModel vm) => vm.hasFrameDataNotifier);
    
    return Container(
      color: Colors.black,
      child: hasFrameData ? 
        CachedFrameDisplay(viewModel: cachedViewModel) :
        const Center(child: Text('Loading...')),
    );
  }
}

class CachedFrameDisplay extends StatefulWidget {
  final CachedTimelineViewModel viewModel;
  
  const CachedFrameDisplay({super.key, required this.viewModel});

  @override
  State<CachedFrameDisplay> createState() => _CachedFrameDisplayState();
}

class _CachedFrameDisplayState extends State<CachedFrameDisplay> {
  final _textureRenderer = TextureRgbaRenderer();
  int? _textureId;
  int _textureKey = -1;
  Timer? _frameUpdateTimer;

  @override
  void initState() {
    super.initState();
    _initializeTexture();
  }

  Future<void> _initializeTexture() async {
    _textureKey = DateTime.now().millisecondsSinceEpoch;
    final textureId = await _textureRenderer.createTexture(_textureKey);
    
    if (textureId != -1) {
      setState(() => _textureId = textureId);
      
      final texturePtr = await _textureRenderer.getTexturePtr(_textureKey);
      await widget.viewModel.setTexturePtr(texturePtr);
      
      _startFrameUpdates();
    }
  }

  void _startFrameUpdates() {
    _frameUpdateTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final frameData = widget.viewModel.getLatestFrameData();
      
      if (frameData.data != null && _textureId != null) {
        _textureRenderer.onRgba(
          _textureKey,
          frameData.data!,
          frameData.height,
          frameData.width,
          1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _textureId != null
        ? Texture(textureId: _textureId!)
        : const SizedBox();
  }

  @override
  void dispose() {
    _frameUpdateTimer?.cancel();
    if (_textureId != null) {
      _textureRenderer.closeTexture(_textureKey);
    }
    super.dispose();
  }
}
```

### 3. Add Performance Controls

Create UI controls for cache management:

```dart
// In lib/widgets/cache_performance_panel.dart
class CachePerformancePanel extends StatelessWidget with WatchItMixin {
  const CachePerformancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cachedViewModel = di<CachedTimelineViewModel>();
    final cacheStatus = watchValue((CachedTimelineViewModel vm) => vm.cacheStatusNotifier);
    final performanceStatus = watchValue((CachedTimelineViewModel vm) => vm.performanceStatusNotifier);
    final preferredQuality = watchValue((CachedTimelineViewModel vm) => vm.preferredQualityNotifier);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cache Status: $cacheStatus'),
        Text('Performance: $performanceStatus'),
        
        const SizedBox(height: 8),
        
        // Quality selector
        ComboBox<CacheQuality>(
          value: preferredQuality,
          items: CacheQuality.values.map((quality) =>
            ComboBoxItem(
              value: quality,
              child: Text('${quality.name} (${(quality.scale * 100).toInt()}%)'),
            ),
          ).toList(),
          onChanged: (quality) {
            if (quality != null) {
              cachedViewModel.setPreferredQuality(quality);
            }
          },
        ),
        
        const SizedBox(height: 8),
        
        // Cache controls
        Row(
          children: [
            Button(
              onPressed: () => cachedViewModel.warmupCurrentRegion(),
              child: const Text('Warm Cache'),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: () => cachedViewModel.clearCache(),
              child: const Text('Clear Cache'),
            ),
          ],
        ),
      ],
    );
  }
}
```

## Performance Tuning

### Cache Settings

Adjust cache parameters based on your target hardware:

```dart
// In FrameCacheService constructor
class FrameCacheService {
  // For lower-end devices
  static const int _maxCacheSizeMB = 256;
  static const int _maxCacheEntries = 500;
  static const int _prerollFrames = 15;
  
  // For high-end devices  
  static const int _maxCacheSizeMB = 1024;
  static const int _maxCacheEntries = 2000;
  static const int _prerollFrames = 60;
}
```

### Quality Adaptation

The system automatically adapts quality based on render performance:

- If rendering takes >50ms per frame → switches to Proxy quality
- If rendering takes >30ms per frame → switches to Low quality
- Otherwise uses Medium quality during playback

### Pre-rendering Strategies

1. **Warmup on Load**: Pre-render first 60 frames when timeline loads
2. **Playback Lookahead**: Always cache 30 frames ahead during playback
3. **Scrubbing Cache**: Keep 5 frames behind current position for smooth scrubbing

## Monitoring and Debugging

### Performance Statistics

Access detailed performance data:

```dart
final stats = cachedViewModel.getDetailedStatistics();
print('Cache hit rate: ${stats['cache']['hitRate']}');
print('Average render time: ${stats['cache']['averageRenderTimeMs']}ms');
print('Recommendations: ${stats['recommendations']}');
```

### Common Issues and Solutions

1. **Low Cache Hit Rate (<70%)**
   - Increase cache size or pre-render more frames
   - Reduce playback speed temporarily
   - Check if timeline changes too frequently

2. **Slow Rendering (>50ms/frame)**
   - Reduce quality settings
   - Simplify effects in timeline
   - Check system resources

3. **High Memory Usage**
   - Reduce max cache size
   - Clear cache more frequently
   - Use lower quality for background frames

## Best Practices

1. **Initialization**: Set up cache early in app lifecycle
2. **Quality Management**: Start with Medium quality, adapt based on performance
3. **Cache Warming**: Pre-render visible regions before playback
4. **Resource Cleanup**: Always dispose viewmodels and services properly
5. **User Feedback**: Show cache status and performance metrics to users

## Migration from Direct Rendering

To migrate existing timeline video players:

1. Replace `TimelineVideoPlayerWidget` with `CachedTimelineVideoPlayerWidget`
2. Update dependency injection to include `CachedTimelineViewModel`
3. Add performance monitoring UI
4. Test with various quality settings
5. Monitor memory usage and adjust cache limits

This cache system should significantly improve playback performance, especially for complex timelines with effects and multiple clips. 