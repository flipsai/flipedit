# Video Player Optimization Migration Guide

This guide explains how to migrate from the old timer-based player to the new optimized player with isolates.

## Key Improvements

1. **Parallel Video Decoding**: Uses isolates to decode frames in parallel
2. **Frame Buffering**: Pre-decodes frames for smooth playback
3. **Direct FFI Rendering**: Bypasses unnecessary abstraction layers
4. **Better Timing**: Microsecond-precision timing instead of timer-based
5. **Performance Monitoring**: Built-in metrics and benchmarking

## Architecture Changes

### Old Architecture
```
Main Thread:
  - Video decoding
  - Frame rendering
  - UI updates
  - Timeline sync
  → Everything sequential, blocking
```

### New Architecture
```
Decoder Isolate:
  - Video decoding
  - Frame buffering
  - Ahead-of-time processing

Main Thread:
  - UI updates
  - Timeline sync
  - Frame rendering (optimized)
  → Parallel processing, non-blocking
```

## Migration Steps

### 1. Update Dependencies

Add required imports:
```dart
import 'package:your_app/services/video/optimized_video_player_service.dart';
import 'package:your_app/services/video/video_decoder_service.dart';
import 'package:your_app/services/video/frame_buffer.dart';
import 'package:your_app/services/video/frame_renderer.dart';
```

### 2. Replace VideoPlayerController

Old:
```dart
class VideoPlayerController {
  cv.VideoCapture? capture;
  // ... manual frame reading
}
```

New:
```dart
OptimizedVideoPlayerService? _playerService;

// Initialize
_playerService = OptimizedVideoPlayerService(
  onFrameChanged: _onFrameChanged,
  onError: _onError,
);
```

### 3. Update Video Loading

Old:
```dart
controller.capture = cv.VideoCapture.fromFile(videoPath);
controller.frameCount = controller.capture!.get(cv.CAP_PROP_FRAME_COUNT).toInt();
```

New:
```dart
final success = await _playerService!.loadVideo(
  videoPath,
  _textureModel,
  _displayIndex,
);
```

### 4. Update Playback Logic

Old:
```dart
_playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
  // Read frame
  final (success, mat) = capture.read();
  // Process and render
});
```

New:
```dart
_playerService!.play();  // Handles everything automatically
```

### 5. Update Frame Rendering

Old:
```dart
final pic = cv.cvtColor(mat, cv.COLOR_RGB2RGBA);
_textureModel.renderFrame(display, picAddr, len, width, height);
```

New:
```dart
// Handled automatically by the service
// Direct FFI rendering for better performance
```

### 6. Update Timeline Integration

Old:
```dart
// Manual sync in timer callback
_navigationViewModel.currentFrame = frame;
```

New:
```dart
// Automatic sync with callbacks
_playerService = OptimizedVideoPlayerService(
  onFrameChanged: (frame) {
    _navigationViewModel.currentFrame = frame;
  },
);
```

## Performance Monitoring

The new player includes built-in performance metrics:

```dart
final metrics = _playerService!.getPerformanceMetrics();
// Returns: fps, renderTime, bufferHealth, etc.
```

## Benchmarking

Use the included benchmark tool to measure improvements:

```dart
final result = await VideoPlayerBenchmark.runBenchmark(
  videoPath: videoPath,
  textureModel: textureModel,
  display: 0,
  durationSeconds: 10,
);
```

## Common Issues & Solutions

### Issue: Video won't load
- Check file permissions
- Ensure video format is supported
- Check isolate spawn errors

### Issue: Frame drops
- Increase buffer size in FrameBuffer
- Check system resources
- Verify texture is ready before rendering

### Issue: Timeline sync issues
- Use the callback system instead of manual polling
- Check for feedback loops in sync logic

## Performance Tips

1. **Buffer Size**: Adjust based on your needs
   ```dart
   final FrameBuffer _frameBuffer = FrameBuffer(maxSize: 15);
   ```

2. **Batch Decoding**: Modify BATCH_SIZE in decoder
   ```dart
   static const int BATCH_SIZE = 3; // Decode 3 frames at once
   ```

3. **Texture Management**: Ensure proper lifecycle
   ```dart
   await _textureModel.createSession(_textureModelId, numDisplays: 1);
   ```

## Testing

1. Run the benchmark screen to measure performance
2. Compare FPS, frame drops, and timing consistency
3. Monitor buffer health during playback
4. Check memory usage with Flutter DevTools

## Rollback Plan

If you need to rollback:
1. Keep the old player implementation
2. Use a feature flag to switch between implementations
3. Gradually migrate features

## Example Implementation

See `OptimizedPlayerTest` widget for a complete example of the new player implementation.
