import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/video/optimized_video_player_service.dart';
import '../models/video_texture_model.dart';

class VideoPlayerBenchmark {
  static Future<BenchmarkResult> runBenchmark({
    required String videoPath,
    required VideoTextureModel textureModel,
    required int display,
    required int durationSeconds,
  }) async {
    final result = BenchmarkResult();
    
    // Track frame updates
    int frameCount = 0;
    final frameUpdateTimes = <int>[];
    int lastFrameTime = DateTime.now().microsecondsSinceEpoch;
    
    final playerService = OptimizedVideoPlayerService(
      onFrameChanged: (frame) {
        final now = DateTime.now().microsecondsSinceEpoch;
        frameUpdateTimes.add(now - lastFrameTime);
        lastFrameTime = now;
        frameCount++;
      },
    );
    
    // Load video
    final loadStartTime = DateTime.now().millisecondsSinceEpoch;
    final success = await playerService.loadVideo(videoPath, textureModel, display);
    final loadEndTime = DateTime.now().millisecondsSinceEpoch;
    
    if (!success) {
      result.error = 'Failed to load video';
      return result;
    }
    
    result.loadTimeMs = loadEndTime - loadStartTime;
    
    // Start playback
    final playbackStartTime = DateTime.now().millisecondsSinceEpoch;
    playerService.play();
    
    // Run for specified duration
    await Future.delayed(Duration(seconds: durationSeconds));
    
    playerService.pause();
    final playbackEndTime = DateTime.now().millisecondsSinceEpoch;
    
    // Get final metrics
    final metrics = playerService.getPerformanceMetrics();
    
    // Calculate results
    result.totalFramesRendered = frameCount;
    result.totalPlaybackTimeMs = playbackEndTime - playbackStartTime;
    result.averageFps = frameCount / (result.totalPlaybackTimeMs / 1000.0);
    result.targetFps = 30.0;
    result.averageRenderTimeUs = metrics['averageRenderTime'] ?? 0;
    
    // Calculate frame timing consistency
    if (frameUpdateTimes.isNotEmpty) {
      frameUpdateTimes.sort();
      result.minFrameTimeUs = frameUpdateTimes.first;
      result.maxFrameTimeUs = frameUpdateTimes.last;
      result.medianFrameTimeUs = frameUpdateTimes[frameUpdateTimes.length ~/ 2];
      
      // Calculate standard deviation
      final avgFrameTime = frameUpdateTimes.reduce((a, b) => a + b) / frameUpdateTimes.length;
      double variance = 0;
      for (final time in frameUpdateTimes) {
        variance += (time - avgFrameTime) * (time - avgFrameTime);
      }
      result.frameTimeStdDev = math.sqrt(variance / frameUpdateTimes.length);
    }
    
    // Clean up
    await playerService.dispose();
    
    return result;
  }
  
  static Future<ComparisonResult> compareImplementations({
    required String videoPath,
    required VideoTextureModel textureModel,
    required int display,
    required int durationSeconds,
  }) async {
    // Run benchmark with optimized implementation
    debugPrint('Running optimized player benchmark...');
    final optimizedResult = await runBenchmark(
      videoPath: videoPath,
      textureModel: textureModel,
      display: display,
      durationSeconds: durationSeconds,
    );
    
    // For comparison, you would also run the old implementation here
    // final oldResult = await runOldBenchmark(...);
    
    return ComparisonResult(
      optimizedResult: optimizedResult,
      // oldResult: oldResult,
    );
  }
}

class BenchmarkResult {
  String? error;
  int loadTimeMs = 0;
  int totalFramesRendered = 0;
  int totalPlaybackTimeMs = 0;
  double averageFps = 0;
  double targetFps = 30;
  double averageRenderTimeUs = 0;
  int minFrameTimeUs = 0;
  int maxFrameTimeUs = 0;
  int medianFrameTimeUs = 0;
  double frameTimeStdDev = 0;
  
  double get fpsAccuracy => (averageFps / targetFps) * 100;
  double get frameDropPercentage => ((targetFps - averageFps) / targetFps) * 100;
  
  @override
  String toString() {
    if (error != null) {
      return 'Benchmark Error: $error';
    }
    
    return '''
Benchmark Results:
- Load Time: ${loadTimeMs}ms
- Total Frames: $totalFramesRendered
- Playback Time: ${totalPlaybackTimeMs}ms
- Average FPS: ${averageFps.toStringAsFixed(2)} (${fpsAccuracy.toStringAsFixed(1)}% accuracy)
- Frame Drops: ${frameDropPercentage.toStringAsFixed(1)}%
- Render Time: ${(averageRenderTimeUs / 1000).toStringAsFixed(2)}ms
- Frame Timing: ${(minFrameTimeUs / 1000).toStringAsFixed(2)}-${(maxFrameTimeUs / 1000).toStringAsFixed(2)}ms (median: ${(medianFrameTimeUs / 1000).toStringAsFixed(2)}ms)
- Timing StdDev: ${(frameTimeStdDev / 1000).toStringAsFixed(2)}ms
''';
  }
}

class ComparisonResult {
  final BenchmarkResult optimizedResult;
  // final BenchmarkResult oldResult;  // Uncomment when you have the old implementation
  
  ComparisonResult({
    required this.optimizedResult,
    // required this.oldResult,
  });
  
  // Add comparison methods here
}

