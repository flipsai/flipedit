import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'video_decoder_service.dart';
import 'frame_buffer.dart';
import 'frame_renderer.dart';
import '../../models/decoded_frame.dart';
import '../../models/video_texture_model.dart';

class OptimizedVideoPlayerService {
  // Isolate communication
  Isolate? _decoderIsolate;
  final ReceivePort _decoderReceivePort = ReceivePort();
  SendPort? _decoderControlPort;
  
  // Frame management
  final FrameBuffer _frameBuffer = FrameBuffer(maxSize: 15);
  FrameRenderer? _frameRenderer;
  
  // Video info
  VideoInfo? _videoInfo;
  String? _currentVideoPath;
  
  // Playback state
  bool _isPlaying = false;
  int _currentFrame = 0;
  Timer? _playbackTimer;
  
  // Performance optimization
  static const int targetFps = 30;
  static const int frameIntervalUs = 1000000 ~/ targetFps;
  int _lastFrameTimeUs = 0;
  
  // Callbacks
  void Function(int frame)? onFrameChanged;
  void Function(String error)? onError;
  
  // Getters
  bool get isPlaying => _isPlaying;
  int get currentFrame => _currentFrame;
  VideoInfo? get videoInfo => _videoInfo;
  double get bufferHealth => _frameBuffer.currentSize / _frameBuffer.maxSize;
  
  OptimizedVideoPlayerService({
    this.onFrameChanged,
    this.onError,
  });
  
  Future<bool> loadVideo(String videoPath, VideoTextureModel textureModel, int display) async {
    debugPrint('OptimizedVideoPlayerService.loadVideo called with path: $videoPath');
    try {
      // Clean up previous session
      await dispose();
      
      _currentVideoPath = videoPath;
      _currentFrame = 0;
      
      // Create frame renderer
      _frameRenderer = FrameRenderer(
        textureModel: textureModel,
        display: display,
      );
      
      debugPrint('Starting decoder isolate...');
      // Start decoder isolate
      _decoderIsolate = await Isolate.spawn(
        VideoDecoderService.decoderEntryPoint,
        DecoderParams(videoPath, _decoderReceivePort.sendPort),
      );
      
      // Listen to decoder messages
      final completer = Completer<bool>();
      StreamSubscription? subscription;
      
      subscription = _decoderReceivePort.listen((message) {
        debugPrint('Received message from decoder: ${message.runtimeType}');
        if (message is VideoInfo) {
          _videoInfo = message;
          debugPrint('Video loaded: ${message.width}x${message.height}, ${message.frameCount} frames @ ${message.fps} fps');
        } else if (message is SendPort) {
          _decoderControlPort = message;
          debugPrint('Got decoder control port');
          completer.complete(true);
        } else if (message is List<DecodedFrame>) {
          debugPrint('Received ${message.length} decoded frames');
          _frameBuffer.addFrames(message);
        } else if (message is DecoderError) {
          debugPrint('Decoder error: ${message.message}');
          onError?.call(message.message);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        }
      });
      
      // Wait for initialization
      final success = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          subscription?.cancel();
          return false;
        },
      );
      
      if (success) {
        // Wait for initial buffer
        await _frameBuffer.waitForInitialBuffer();
      }
      
      return success;
    } catch (e) {
      onError?.call('Failed to load video: $e');
      return false;
    }
  }
  
  void play() {
    if (_isPlaying || _decoderControlPort == null || _frameRenderer == null) return;
    
    _isPlaying = true;
    _lastFrameTimeUs = DateTime.now().microsecondsSinceEpoch;
    
    // Start playback timer with microsecond precision
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(microseconds: 100), (_) {
      if (!_isPlaying) return;
      
      final now = DateTime.now().microsecondsSinceEpoch;
      if (now - _lastFrameTimeUs >= frameIntervalUs) {
        _renderNextFrame();
        _lastFrameTimeUs = now;
      }
    });
  }
  
  void pause() {
    _isPlaying = false;
    _playbackTimer?.cancel();
  }
  
  void seek(int frame) {
    if (_decoderControlPort == null || _videoInfo == null) return;
    
    // Clamp frame to valid range
    frame = frame.clamp(0, _videoInfo!.frameCount - 1);
    _currentFrame = frame;
    
    // Clear buffer and seek decoder
    _frameBuffer.clear();
    _decoderControlPort!.send(SeekCommand(frame));
    
    // Render current frame if paused
    if (!_isPlaying) {
      Timer(const Duration(milliseconds: 100), () {
        final decodedFrame = _frameBuffer.getFrame(_currentFrame);
        if (decodedFrame != null && _frameRenderer != null) {
          _frameRenderer!.renderFrame(decodedFrame);
        }
      });
    }
    
    onFrameChanged?.call(_currentFrame);
  }
  
  void _renderNextFrame() {
    if (_frameRenderer == null || _videoInfo == null) return;
    
    // Get frame from buffer
    final frame = _frameBuffer.getFrame(_currentFrame);
    
    if (frame != null) {
      final success = _frameRenderer!.renderFrame(frame);
      
      if (success) {
        _currentFrame++;
        
        // Loop at end
        if (_currentFrame >= _videoInfo!.frameCount) {
          _currentFrame = 0;
          seek(0);
        }
        
        onFrameChanged?.call(_currentFrame);
      }
    } else {
      // Buffer underrun - wait a bit
      debugPrint('Buffer underrun at frame $_currentFrame');
    }
  }
  
  Future<void> dispose() async {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null; // Explicitly nullify the timer

    debugPrint('OptimizedVideoPlayerService: Disposing...');

    if (_decoderControlPort != null && _decoderIsolate != null) {
      debugPrint('OptimizedVideoPlayerService: Sending StopCommand to decoder isolate.');
      _decoderControlPort!.send(StopCommand());
      // Give the isolate a moment to process the StopCommand and potentially clean up its cache.
      // This is a common pattern, but for true robustness, a confirmation message from the isolate is better.
      await Future.delayed(const Duration(milliseconds: 200)); // Adjust delay as needed
    }

    if (_decoderIsolate != null) {
      debugPrint('OptimizedVideoPlayerService: Killing decoder isolate.');
      _decoderIsolate!.kill(priority: Isolate.immediate);
      _decoderIsolate = null;
    }

    _decoderReceivePort.close(); // Close the main receive port
    // Re-initialize the receive port for the next loadVideo call, as it cannot be listened to after closing.
    // However, a new one is created in the constructor of this example, 
    // and loadVideo creates a new subscription each time. So, simply closing is fine.
    // If this service instance was to be reused without re-creating, we'd need a new ReceivePort here.

    _frameBuffer.dispose(); // Clears in-memory frames
    _frameRenderer?.reset(); // Resets texture model
    
    // Nullify references
    _decoderControlPort = null;
    _videoInfo = null;
    _currentVideoPath = null; // Clear the path
    _frameRenderer = null; // Explicitly nullify renderer
    
    debugPrint('OptimizedVideoPlayerService: Dispose complete.');
  }
  
  // Performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'fps': _frameRenderer?.currentFps ?? 0,
      'averageRenderTime': _frameRenderer?.averageRenderTime ?? 0,
      'bufferSize': _frameBuffer.currentSize,
      'bufferHealth': bufferHealth,
    };
  }
}
