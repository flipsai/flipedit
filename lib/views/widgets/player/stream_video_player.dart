import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flipedit/utils/logger.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// Enum to represent the source of the current frame
enum FrameSource { none, cache, server, unknown }

// Helper function to generate cache keys
String _getFrameCacheKey(String baseUrl, int frameIndex) {
  return '${baseUrl}_frame_$frameIndex';
}

// Data class to hold frame image, its index, and raw bytes
class FrameData {
  final ui.Image image;
  final int frameIndex;
  final Uint8List rawJpegBytes; // For caching

  FrameData({required this.image, required this.frameIndex, required this.rawJpegBytes});
}

// A value class to represent the current state of the player
class StreamVideoPlayerValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isError;
  final String? errorMessage;
  final ui.Image? frame;
  final double aspectRatio;
  final int frameIndex;
  final int totalFrames;
  final FrameSource frameSource;

  const StreamVideoPlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isError = false,
    this.errorMessage,
    this.frame,
    this.aspectRatio = 16 / 9,
    this.frameIndex = 0,
    this.totalFrames = 0,
    this.frameSource = FrameSource.unknown,
  });

  StreamVideoPlayerValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isError,
    String? errorMessage,
    ui.Image? frame,
    double? aspectRatio,
    int? frameIndex,
    int? totalFrames,
    FrameSource? frameSource,
    bool forceClearFrame = false,
  }) {
    return StreamVideoPlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      frame: forceClearFrame ? null : frame ?? this.frame,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      frameIndex: frameIndex ?? this.frameIndex,
      totalFrames: totalFrames ?? this.totalFrames,
      frameSource: frameSource ?? this.frameSource,
    );
  }
}

// Controller for managing the video player
class StreamVideoPlayerController extends ValueNotifier<StreamVideoPlayerValue> {
  final String serverBaseUrl;
  final int? targetDisplayFps;
  MjpegStream? _mjpegStream;
  StreamSubscription<FrameData>? _streamSubscription;
  int _currentFrameIndex = 0;
  int _actualStreamFrameIndex = 0;

  Timer? _displayFpsTimer;
  ui.Image? _latestDecodedFrame;
  bool _isProcessingFrame = false;

  StreamVideoPlayerController({
    this.serverBaseUrl = 'http://localhost:8085',
    this.targetDisplayFps,
  }) : super(const StreamVideoPlayerValue(frameSource: FrameSource.none));

  String get streamUrl => '$serverBaseUrl/stream?start_frame=$_currentFrameIndex';

  bool get isInitialized => value.isInitialized;
  bool get isPlaying => value.isPlaying;
  bool get isBuffering => value.isBuffering;
  bool get hasError => value.isError;
  ui.Image? get currentFrame => value.frame;
  double get aspectRatio => value.aspectRatio;
  int get currentFrameIndex => value.frameIndex;

  Future<void> initialize() async {
    if (_isProcessingFrame) {
      logInfo("Initialize called while already processing, returning.", "StreamVideoPlayerController");
      return;
    }
    _isProcessingFrame = true;
    value = value.copyWith(isBuffering: true, isPlaying: false, frameIndex: _currentFrameIndex, frameSource: FrameSource.none, frame: null, forceClearFrame: true);
      
      await _streamSubscription?.cancel();
      _mjpegStream?.dispose();
      _mjpegStream = null;
      
      _actualStreamFrameIndex = _currentFrameIndex; 
      
    final String cacheKey = _getFrameCacheKey(serverBaseUrl, _currentFrameIndex);
    bool RETAIN_isProcessingFrameFalse = false;
    bool RETAIN_callPlayIfWasPlaying = false;
    FrameSource loadedFrameSource = FrameSource.none;

    try {
      logInfo("Attempting to load frame $_currentFrameIndex from cache with key: $cacheKey", "StreamVideoPlayerController");
      final fileInfo = await DefaultCacheManager().getFileFromCache(cacheKey);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        logInfo("Cache HIT for frame $_currentFrameIndex. Decoding...", "StreamVideoPlayerController");
        final Uint8List imageBytes = await fileInfo.file.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(imageBytes);
        final ui.FrameInfo uiFrameInfo = await codec.getNextFrame();
        _latestDecodedFrame = uiFrameInfo.image;
        
        loadedFrameSource = FrameSource.cache;
        value = value.copyWith(
          isInitialized: true,
          isBuffering: false,
          frame: _latestDecodedFrame,
          frameIndex: _currentFrameIndex,
          aspectRatio: _latestDecodedFrame != null ? _latestDecodedFrame!.width / _latestDecodedFrame!.height : value.aspectRatio,
          isError: false,
          errorMessage: null,
          frameSource: loadedFrameSource,
        );
        logInfo("Frame $_currentFrameIndex loaded from cache and displayed.", "StreamVideoPlayerController");
        RETAIN_isProcessingFrameFalse = false;
        RETAIN_callPlayIfWasPlaying = wasPlayingBeforeInit;

      } else {
        logInfo("Cache MISS for frame $_currentFrameIndex.", "StreamVideoPlayerController");
        loadedFrameSource = FrameSource.none; 
        value = value.copyWith(frameSource: loadedFrameSource, frame: null, forceClearFrame: true);
      }
    } catch (e, s) {
      logError("Error loading frame $_currentFrameIndex from cache", e, s, "StreamVideoPlayerController");
       loadedFrameSource = FrameSource.none;
       value = value.copyWith(isError: true, errorMessage: "Cache error: $e", isBuffering: false, frameSource: loadedFrameSource);
    }

    logInfo("Proceeding to MJPEG stream setup for frame $_currentFrameIndex. URL: $streamUrl", "StreamVideoPlayerController");
    
    try {
      _mjpegStream = MjpegStream(
        streamUrl, 
        serverBaseUrl, 
        _currentFrameIndex 
      );
      
      _streamSubscription = _mjpegStream!.stream.listen(
        (frameData) { 
          _latestDecodedFrame = frameData.image; 
          _actualStreamFrameIndex = frameData.frameIndex;

          if (value.isPlaying || (_actualStreamFrameIndex == _currentFrameIndex && !value.isPlaying && isInitialized)) { 
            value = value.copyWith(
              isInitialized: true,
              isBuffering: false,
              frame: _latestDecodedFrame, 
              frameIndex: _actualStreamFrameIndex, 
              aspectRatio: _latestDecodedFrame != null ? _latestDecodedFrame!.width / _latestDecodedFrame!.height : value.aspectRatio,
              isError: false, errorMessage: null,
              frameSource: FrameSource.server,
            );
          }
        },
        onError: (error, stackTrace) {
          logError("Stream error", error, stackTrace, "StreamVideoPlayerController");
          value = value.copyWith(
            isBuffering: false,
            isError: true,
            errorMessage: "Stream error: $error",
            isPlaying: false,
            frameSource: FrameSource.none,
          );
        },
        onDone: () {
          logInfo("Stream closed", "StreamVideoPlayerController");
          if (!value.isError) {
            value = value.copyWith(
              isBuffering: false,
              isPlaying: false,
              frameSource: FrameSource.none,
            );
          } else {
            value = value.copyWith(frameSource: FrameSource.none);
          }
        },
      );
      
      bool finalIsPlaying = RETAIN_callPlayIfWasPlaying || wasPlayingBeforeInit || value.isPlaying;
      value = value.copyWith(
        isInitialized: true, 
        isBuffering: value.frame == null,
        isPlaying: finalIsPlaying,
        frameSource: value.frame != null ? value.frameSource : FrameSource.none,
      );

      if (finalIsPlaying && !this.value.isPlaying) {
          logInfo("Initialize: Triggering play() to ensure playback state.", "StreamVideoPlayerController");
          play();
      }
      wasPlayingBeforeInit = false; 

    } catch (e, stackTrace) {
      logError("Failed to initialize stream", e, stackTrace, "StreamVideoPlayerController");
      value = value.copyWith(
        isBuffering: false,
        isError: true,
        errorMessage: "Failed to initialize stream: $e",
        isPlaying: false,
        isInitialized: true,
        frameSource: FrameSource.none,
      );
    } finally {
      if(!RETAIN_isProcessingFrameFalse) {
      _isProcessingFrame = false;
      }
    }
  }

  bool wasPlayingBeforeInit = false;

  void play() {
    if (value.isPlaying && _mjpegStream != null && _mjpegStream!._isActive) return;

    value = value.copyWith(isPlaying: true, isError: false, errorMessage: null);

    if (_isProcessingFrame) {
        logInfo("Play: Initialize in progress, isPlaying set.", "StreamVideoPlayerController");
        wasPlayingBeforeInit = true;
        return;
    }

    if (!isInitialized || _mjpegStream == null || !_mjpegStream!._isActive) {
      logInfo("Play: Stream not ready. Calling initialize.", "StreamVideoPlayerController");
      wasPlayingBeforeInit = true;
      initialize(); 
    } else {
      logInfo("Play: Stream ready. Player set to playing.", "StreamVideoPlayerController");
    }
  }

  void pause() {
    value = value.copyWith(isPlaying: false);
    wasPlayingBeforeInit = false;
    logInfo("Pause: Playback paused.", "StreamVideoPlayerController");
  }

  void seekTo(int frameIndex) {
    if (_isProcessingFrame && frameIndex == _currentFrameIndex) {
        logInfo("SeekTo: Busy with the same frame $frameIndex. Ignoring.", "StreamVideoPlayerController");
        return;
    }

    logInfo("SeekTo called: $frameIndex. Current: $_currentFrameIndex, Playing: ${value.isPlaying}", "StreamVideoPlayerController");
    
    bool playAfterSeek = value.isPlaying;
    _currentFrameIndex = frameIndex;
    
    value = value.copyWith(
      frameIndex: _currentFrameIndex, 
      frame: null, 
      forceClearFrame: true, 
      isPlaying: false,
      isBuffering: true,
      isError: false, errorMessage: null,
      frameSource: FrameSource.none,
    );
    
    wasPlayingBeforeInit = playAfterSeek;

    if (!_isProcessingFrame) {
      initialize();
    } else {
      logWarning("SeekTo: Controller is busy. Frame index updated to $_currentFrameIndex. Current init will finish first.", "StreamVideoPlayerController");
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _mjpegStream?.dispose();
    super.dispose();
  }
}

class StreamVideoPlayer extends StatefulWidget {
  final String serverBaseUrl;
  final bool autoPlay;
  final bool showControls;
  final int initialFrame;
  final int? targetDisplayFps;
  final void Function(FrameSource newSource)? onFrameSourceChanged;

  const StreamVideoPlayer({
    super.key,
    this.serverBaseUrl = 'http://localhost:8085',
    this.autoPlay = true,
    this.showControls = true,
    this.initialFrame = 0,
    this.targetDisplayFps = 30,
    this.onFrameSourceChanged,
  });

  @override
  State<StreamVideoPlayer> createState() => _StreamVideoPlayerState();
}

class _StreamVideoPlayerState extends State<StreamVideoPlayer> {
  late StreamVideoPlayerController _controller;
  StreamVideoPlayerValue? _previousValue;
  
  @override
  void initState() {
    super.initState();
    _controller = StreamVideoPlayerController(
      serverBaseUrl: widget.serverBaseUrl,
      targetDisplayFps: widget.targetDisplayFps,
    );
    _previousValue = _controller.value;
    _controller.addListener(_onControllerUpdate);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.seekTo(widget.initialFrame);
        if (widget.autoPlay && !_controller.isPlaying) {
      _controller.play();
        }
      }
    });
  }

  void _onControllerUpdate() {
    if (mounted) {
      final currentValue = _controller.value;
      if (_previousValue?.frameSource != currentValue.frameSource && widget.onFrameSourceChanged != null) {
        widget.onFrameSourceChanged!(currentValue.frameSource);
      }
      _previousValue = currentValue;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant StreamVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool controllerRecreated = false;
    if (widget.serverBaseUrl != oldWidget.serverBaseUrl || 
        widget.targetDisplayFps != oldWidget.targetDisplayFps) {
      final currentFrame = _controller.currentFrameIndex;
      final isPlaying = _controller.isPlaying;

      _controller.removeListener(_onControllerUpdate);
      _controller.dispose();
      
      _controller = StreamVideoPlayerController(
        serverBaseUrl: widget.serverBaseUrl,
        targetDisplayFps: widget.targetDisplayFps,
      );
      _previousValue = _controller.value;
      _controller.addListener(_onControllerUpdate);
      _controller.seekTo(currentFrame);
      if (isPlaying) _controller.play();
      controllerRecreated = true;
    }
    
    if (widget.onFrameSourceChanged != oldWidget.onFrameSourceChanged && !controllerRecreated) {
      final currentSource = _controller.value.frameSource;
      if (widget.onFrameSourceChanged != null) {
           WidgetsBinding.instance.addPostFrameCallback((_) { 
            if(mounted) {
                 widget.onFrameSourceChanged!(currentSource);
            }
           });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: value.isInitialized && value.frame != null
                ? AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: _VideoSurface(image: value.frame!),
                  )
                : value.isBuffering
                    ? const CircularProgressIndicator()
                    : value.isError
                        ? Text(
                            value.errorMessage ?? 'An error occurred',
                            style: const TextStyle(color: Colors.red),
                          )
                        : const Center(child: Text("Initializing Player...", style: TextStyle(color: Colors.white))),
          ),
        ),
        if (widget.showControls)
          Padding(
          padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
                  IconButton(
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: () {
                      if (value.isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                    },
                  ),
                  IconButton(
                  icon: const Icon(Icons.skip_previous),
                    onPressed: () {
                    final prevFrame = (value.frameIndex - 30).clamp(0, value.totalFrames);
                     _controller.seekTo(prevFrame);
                  },
                ),
                Text('Frame: ${value.frameIndex}', style: const TextStyle(color: Colors.white)),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () {
                     final nextFrame = (value.frameIndex + 30).clamp(0, value.totalFrames);
                    _controller.seekTo(nextFrame);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _VideoSurface extends StatelessWidget {
  final ui.Image image;

  const _VideoSurface({required this.image});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _VideoSurfacePainter(image),
      size: Size.infinite,
    );
  }
}

class _VideoSurfacePainter extends CustomPainter {
  final ui.Image image;

  _VideoSurfacePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: BoxFit.contain,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoSurfacePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

class MjpegStream {
  final String url;
  final String serverBaseUrl;
  final int initialFrameIndex;

  final StreamController<FrameData> _controller = StreamController<FrameData>();
  http.Client? _client;
  bool _isActive = true;
  final String _instanceId; 
  int _framesProcessedThisInstance = 0;
  
  Stream<FrameData> get stream => _controller.stream;
  
  MjpegStream(this.url, this.serverBaseUrl, this.initialFrameIndex) 
      : _instanceId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) {
    logInfo("MjpegStream[$_instanceId] created for URL: $url, initialFrameIndex: $initialFrameIndex", "MjpegStream");
    _startStreaming();
  }
  
  void _startStreaming() async {
    if (!_isActive) {
      logInfo("MjpegStream[$_instanceId] _startStreaming: called but already inactive. URL: $url", "MjpegStream");
      return;
    }
    
    try {
      logInfo("MjpegStream[$_instanceId] _startStreaming: Starting for URL: $url", "MjpegStream");
      _client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      
      final response = await _client!.send(request)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        logWarning("MjpegStream[$_instanceId] _startStreaming: Connection timed out for $url", "MjpegStream");
        throw TimeoutException('Connection timed out for $url');
      });
      
      if (!_isActive) {
        logInfo("MjpegStream[$_instanceId] _startStreaming: Became inactive during/after _client.send() for $url. Draining and returning.", "MjpegStream");
        try {
          await response.stream.drain();
        } catch (e) {
          logWarning("MjpegStream[$_instanceId] _startStreaming: Error draining response stream during abort for $url: $e", "MjpegStream");
        }
        return;
      }
      
      if (response.statusCode != 200) {
        final errorMsg = 'Failed to connect to stream: ${response.statusCode} for $url';
        logError("MjpegStream[$_instanceId] _startStreaming: HTTP error", errorMsg, null, "MjpegStream");
        if (_isActive && !_controller.isClosed) {
          _controller.addError(Exception(errorMsg));
        }
        return;
      }
      logInfo("MjpegStream[$_instanceId] _startStreaming: Connected, status ${response.statusCode} for $url", "MjpegStream");
      
      List<int> buffer = [];
      final boundaryBytes = Uint8List.fromList(r'--frame\r\n'.codeUnits);
      final headerEndBytes = Uint8List.fromList(r'\r\n\r\n'.codeUnits);
      int searchStartIndex = 0;

      await for (final chunk in response.stream) {
        if (!_isActive) {
          logInfo("MjpegStream[$_instanceId] Processing chunk: Stream became inactive for $url. Breaking from chunk loop.", "MjpegStream");
          break;
        }
        buffer.addAll(chunk);

        while (_isActive) {
          int boundaryPos = _findBytes(buffer, boundaryBytes, searchStartIndex);
          if (boundaryPos == -1) {
            searchStartIndex = buffer.length > boundaryBytes.length ? buffer.length - boundaryBytes.length : 0;
            break; 
          }

          int headersStartPos = boundaryPos + boundaryBytes.length;
          int headersEndPos = _findBytes(buffer, headerEndBytes, headersStartPos);
          if (headersEndPos == -1) {
            searchStartIndex = buffer.length > headerEndBytes.length ? buffer.length - headerEndBytes.length : headersStartPos;
            break; 
          }

          int imageDataStartPos = headersEndPos + headerEndBytes.length;
          String headersStr = String.fromCharCodes(buffer.sublist(headersStartPos, headersEndPos));
          int contentLength = -1;
          final clRegex = RegExp(r"Content-Length:\s*(\d+)", caseSensitive: false, multiLine: true);
          final match = clRegex.firstMatch(headersStr);

          if (match != null && match.groupCount >= 1) {
            try {
              contentLength = int.parse(match.group(1)!);
            } catch (e) {
              logWarning("MjpegStream[$_instanceId] Failed to parse Content-Length from '${match.group(1)}' for $url: $e", "MjpegStream");
            }
          }
          
          if (contentLength <= 0) {
             logWarning("MjpegStream[$_instanceId] Content-Length header not found or invalid ($contentLength) in frame headers for $url. Headers: '''$headersStr'''", "MjpegStream");
            buffer = buffer.sublist(imageDataStartPos);
            searchStartIndex = 0;
            continue;
          }
          
          if (buffer.length >= imageDataStartPos + contentLength) {
            Uint8List imageData = Uint8List.fromList(buffer.sublist(imageDataStartPos, imageDataStartPos + contentLength));
            buffer = buffer.sublist(imageDataStartPos + contentLength);
            searchStartIndex = 0; 

            if (imageData.isNotEmpty) {
              if (_isActive) {
                try {
                  final int currentActualFrameInStream = initialFrameIndex + _framesProcessedThisInstance;
                  final String frameCacheKey = _getFrameCacheKey(serverBaseUrl, currentActualFrameInStream);
                  
                  DefaultCacheManager().putFile(frameCacheKey, imageData, fileExtension: "jpg")
                    .then((_) => logInfo("MjpegStream[$_instanceId] Frame $currentActualFrameInStream cached with key $frameCacheKey", "MjpegStream"))
                    .catchError((e, s) {
                      logError("MjpegStream[$_instanceId] Error caching frame $currentActualFrameInStream with key $frameCacheKey", e, s, "MjpegStream");
                    });

                  final codec = await ui.instantiateImageCodec(imageData);
                  final frameInfo = await codec.getNextFrame();
                  if (!_controller.isClosed && _isActive) {
                    _controller.add(FrameData(
                      image: frameInfo.image, 
                      frameIndex: currentActualFrameInStream,
                      rawJpegBytes: imageData
                    ));
                    _framesProcessedThisInstance++;
                  }
                } catch (e, s) {
                  logError("MjpegStream[$_instanceId] Failed to decode image. Length: ${imageData.length}. Content-Length: $contentLength. URL: $url", e, s, "MjpegStream");
                }
              }
            } else {
                logWarning("MjpegStream[$_instanceId] Extracted empty image data despite CL=$contentLength for $url.", "MjpegStream");
            }
          } else {
            searchStartIndex = boundaryPos; 
            break; 
          }

          if (!_isActive) { 
            logInfo("MjpegStream[$_instanceId] Post-frame processing: Stream became inactive for $url. Breaking from inner loop.", "MjpegStream");
            break;
          }

          if (buffer.length > 20 * 1024 * 1024) { 
            logError("MjpegStream[$_instanceId] MJPEG buffer exceeded 20MB for $url, clearing to prevent OOM.", null, null, "MjpegStream");
            buffer = []; 
            searchStartIndex = 0; 
            if (_isActive && !_controller.isClosed) {
                _controller.addError(Exception("MJPEG buffer overflow for $url"));
            }
            break; 
          }
        }
      }
      
      if (_isActive && !_controller.isClosed) {
        logInfo("MjpegStream[$_instanceId] _startStreaming: HTTP response stream ended for $url.", "MjpegStream");
        await _controller.close(); 
      } else {
        logInfo("MjpegStream[$_instanceId] _startStreaming: Stream processing loop exited. _isActive: $_isActive, _controller.isClosed: ${_controller.isClosed} for $url.", "MjpegStream");
      }

    } catch (e, stackTrace) {
      logInfo("MjpegStream[$_instanceId] _startStreaming: CATCH BLOCK. _isActive: $_isActive. Error for $url: $e", "MjpegStream");
      if (_isActive && !_controller.isClosed) {
        logError("MjpegStream[$_instanceId] _startStreaming: Error in active stream for $url", e, stackTrace, "MjpegStream");
        _controller.addError(e);
        await _controller.close(); 
      } else {
        logInfo("MjpegStream[$_instanceId] _startStreaming: Caught error but stream already inactive or controller closed for $url: $e", "MjpegStream");
      }
    } finally {
        if (_client != null) {
            _client!.close();
            logInfo("MjpegStream[$_instanceId] _startStreaming: Finally block closed HTTP client for $url.", "MjpegStream");
        }
        _client = null; 
        
        if (!_isActive && !_controller.isClosed) {
           logInfo("MjpegStream[$_instanceId] _startStreaming: Finally block, stream was inactive, ensuring controller is closed for $url.", "MjpegStream");
           await _controller.close();
        }
        logInfo("MjpegStream[$_instanceId] _startStreaming: Finally block executed for $url. _isActive: $_isActive, controller closed: ${_controller.isClosed}", "MjpegStream");
    }
  }

  int _findBytes(List<int> source, List<int> find, int startIndex) {
    if (find.isEmpty) return startIndex;
    for (int i = startIndex; i <= source.length - find.length; i++) {
      bool found = true;
      for (int j = 0; j < find.length; j++) {
        if (source[i + j] != find[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }
  
  void dispose() {
    logInfo("MjpegStream[$_instanceId] dispose() called. Current _isActive: $_isActive, URL: $url", "MjpegStream");
    if (!_isActive) {
      logInfo("MjpegStream[$_instanceId] dispose(): Already inactive for $url. Skipping.", "MjpegStream");
      return;
    }

    _isActive = false;
    logInfo("MjpegStream[$_instanceId] dispose(): Set _isActive to false for $url.", "MjpegStream");
    
    _client?.close();
    _client = null;
    logInfo("MjpegStream[$_instanceId] dispose(): Client closed and nulled for $url.", "MjpegStream");

    if (!_controller.isClosed) {
      _controller.close().catchError((e, s) {
        logWarning("MjpegStream[$_instanceId] dispose(): Error closing controller for $url: $e", "MjpegStream");
      });
      logInfo("MjpegStream[$_instanceId] dispose(): Controller close initiated for $url.", "MjpegStream");
    } else {
      logInfo("MjpegStream[$_instanceId] dispose(): Controller already closed for $url.", "MjpegStream");
    }
    logInfo("MjpegStream[$_instanceId] dispose(): Fully disposed for $url.", "MjpegStream");
  }
}