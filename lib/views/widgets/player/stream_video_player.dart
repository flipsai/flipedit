import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flipedit/utils/logger.dart';

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
  }) {
    return StreamVideoPlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isError: isError ?? this.isError,
      errorMessage: errorMessage ?? this.errorMessage,
      frame: frame ?? this.frame,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      frameIndex: frameIndex ?? this.frameIndex,
      totalFrames: totalFrames ?? this.totalFrames,
    );
  }
}

// Controller for managing the video player
class StreamVideoPlayerController extends ValueNotifier<StreamVideoPlayerValue> {
  final String serverBaseUrl;
  final int? targetDisplayFps; // Optional target display FPS
  MjpegStream? _mjpegStream;
  StreamSubscription<ui.Image>? _streamSubscription;
  int _currentFrameIndex = 0; // Tracks the frame index we *want* to be at or start from
  int _actualStreamFrameIndex = 0; // Tracks frame index *received* from stream if playing

  Timer? _displayFpsTimer;
  ui.Image? _latestDecodedFrame;
  bool _isProcessingFrame = false; // To prevent concurrent processing

  StreamVideoPlayerController({
    this.serverBaseUrl = 'http://localhost:8085',
    this.targetDisplayFps,
  }) : super(const StreamVideoPlayerValue()) {
    // if (targetDisplayFps != null && targetDisplayFps! > 0) {
    //   _displayFpsTimer = Timer.periodic(Duration(milliseconds: 1000 ~/ targetDisplayFps!), _onDisplayTick);
    // }
  }

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
    
    try {
      value = value.copyWith(isBuffering: true, isPlaying: false); // Ensure isPlaying is false during init
      
      await _streamSubscription?.cancel();
      _mjpegStream?.dispose();
      _mjpegStream = null;
      _latestDecodedFrame = null; // Clear any held frame
      
      // _currentFrameIndex is already set by seekTo or is 0 initially.
      // This will be the frame the stream starts from.
      _actualStreamFrameIndex = _currentFrameIndex; 
      
      logInfo("Initializing stream player with URL: $streamUrl, targetDisplayFps: $targetDisplayFps", "StreamVideoPlayerController");
      
      _mjpegStream = MjpegStream(streamUrl);
      
      _streamSubscription = _mjpegStream!.stream.listen(
        (image) {
          _latestDecodedFrame = image; // Keep this for now, though direct update is next
          // If not using targetDisplayFps, update immediately. << REVERT TO THIS BEHAVIOR
          // if (targetDisplayFps == null) { 
          if (value.isPlaying) { // Only update frame if actually playing
            value = value.copyWith(
              isInitialized: true,
              isBuffering: false,
              frame: _latestDecodedFrame, // Use the latest frame
              frameIndex: _actualStreamFrameIndex, 
              isError: false,
              errorMessage: null,
            );
          }
          // }
           // If using targetDisplayFps, _onDisplayTick would handle updating the value.
           // We increment _actualStreamFrameIndex regardless, as it represents what the stream is producing.
          if (value.isPlaying) { // Increment only if playing
             _actualStreamFrameIndex++;
          }
        },
        onError: (error, stackTrace) {
          logError("Stream error", error, stackTrace, "StreamVideoPlayerController");
          value = value.copyWith(
            isBuffering: false,
            isError: true,
            errorMessage: "Stream error: $error",
            isPlaying: false,
          );
        },
        onDone: () {
          logInfo("Stream closed", "StreamVideoPlayerController");
          if (!value.isError) { // Only show as error if not already in an error state
            value = value.copyWith(
              isBuffering: false,
              // Consider if this is an error or just end of stream
              // isError: true, 
              // errorMessage: "Stream closed unexpectedly",
              isPlaying: false, // Stream has ended, so not playing
            );
          }
        },
      );
      
      // Don't auto-play here; play() method should be explicit
      // or initial autoPlay prop in StreamVideoPlayer widget should call play().
      // For now, initialize just sets up the stream.
      // If it was playing before re-init, it should resume.
      value = value.copyWith(isInitialized: true, isBuffering: false, frameIndex: _currentFrameIndex);
      if (wasPlayingBeforeInit) { // A new flag to track if we should resume play
          play();
      }

    } catch (e, stackTrace) {
      logError("Failed to initialize stream", e, stackTrace, "StreamVideoPlayerController");
      value = value.copyWith(
        isBuffering: false,
        isError: true,
        errorMessage: "Failed to initialize stream: $e",
        isPlaying: false,
      );
    } finally {
      _isProcessingFrame = false;
    }
  }

  bool wasPlayingBeforeInit = false;

  void play() {
    if (!isInitialized && !value.isBuffering && !_isProcessingFrame) {
      wasPlayingBeforeInit = true; // Set intent to play
      initialize(); 
    } else if (isInitialized) {
      value = value.copyWith(isPlaying: true);
      // if (targetDisplayFps != null && _displayFpsTimer == null) {
      //    _displayFpsTimer = Timer.periodic(Duration(milliseconds: 1000 ~/ targetDisplayFps!), _onDisplayTick);
      // }
    }
  }

  void pause() {
    value = value.copyWith(isPlaying: false);
    // _displayFpsTimer?.cancel();
    // _displayFpsTimer = null;
    wasPlayingBeforeInit = false; // Clear intent
  }

  void seekTo(int frameIndex) {
    if (_isProcessingFrame && frameIndex == _currentFrameIndex) return; // Avoid seek spam if already processing for this frame

    logInfo("SeekTo called: $frameIndex. Current _currentFrameIndex: $_currentFrameIndex, isPlaying: ${value.isPlaying}", "StreamVideoPlayerController");
    
    bool needsReInit = _currentFrameIndex != frameIndex || !isInitialized;
    _currentFrameIndex = frameIndex;
    _actualStreamFrameIndex = frameIndex; // Reset actual stream frame to seek target
    _latestDecodedFrame = null; // Clear held frame on seek

    value = value.copyWith(frameIndex: _currentFrameIndex, frame: null); // Update displayed frame index immediately, clear frame

    if (needsReInit && !_isProcessingFrame) {
      logInfo("SeekTo: Re-initializing stream for frame $_currentFrameIndex", "StreamVideoPlayerController");
      wasPlayingBeforeInit = value.isPlaying; // Preserve play state
      if(value.isPlaying) pause(); // Pause briefly to prevent race conditions with init.
      initialize();
    } else if (isInitialized && !value.isPlaying) {
      // If paused and initialized, we want to fetch and display the single seeked frame
      // This might require a different mechanism if the stream only sends on play.
      // For now, re-init is the most robust way to get a specific frame if not playing.
      // Consider a getFrame(frameIndex) on MjpegStream if possible in future.
      logInfo("SeekTo: Paused, re-initializing to fetch specific frame $_currentFrameIndex", "StreamVideoPlayerController");
      wasPlayingBeforeInit = false; // Not resuming play
      initialize();
    } else {
      logInfo("SeekTo: Stream already initialized and playing, or no re-init needed.", "StreamVideoPlayerController");
    }
  }
  
  // void _onDisplayTick(Timer timer) {
  //   if (value.isPlaying && _latestDecodedFrame != null) {
  //     value = value.copyWith(
  //       frame: _latestDecodedFrame,
  //       frameIndex: _actualStreamFrameIndex -1, // because _actualStreamFrameIndex was already incremented
  //       isBuffering: false,
  //       isInitialized: true,
  //       isError: false,
  //     );
  //     _latestDecodedFrame = null; // Consume the frame
  //   }
  // }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _mjpegStream?.dispose();
    // _displayFpsTimer?.cancel();
    super.dispose();
  }
}

class StreamVideoPlayer extends StatefulWidget {
  final String serverBaseUrl;
  final bool autoPlay;
  final bool showControls;
  final int initialFrame;
  final int? targetDisplayFps; // Add targetDisplayFps

  const StreamVideoPlayer({
    super.key,
    this.serverBaseUrl = 'http://localhost:8085',
    this.autoPlay = true,
    this.showControls = true,
    this.initialFrame = 0,
    this.targetDisplayFps = 30, // Default to 30 FPS for display
  });

  @override
  State<StreamVideoPlayer> createState() => _StreamVideoPlayerState();
}

class _StreamVideoPlayerState extends State<StreamVideoPlayer> {
  late StreamVideoPlayerController _controller;
  double _sliderPosition = 0.0;
  bool _isUserDraggingSlider = false;
  
  @override
  void initState() {
    super.initState();
    _controller = StreamVideoPlayerController(
      serverBaseUrl: widget.serverBaseUrl,
      targetDisplayFps: widget.targetDisplayFps, // Pass targetDisplayFps
    );
    _sliderPosition = widget.initialFrame.toDouble();
    
    // Set initial frame correctly before deciding to play
    // This ensures initialize() in play() uses the correct start_frame
    _controller.value = _controller.value.copyWith(frameIndex: widget.initialFrame);
    _controller._currentFrameIndex = widget.initialFrame; // Explicitly set internal index too

    if (widget.autoPlay) {
      _controller.play();
    } else if (widget.initialFrame > 0) {
       // If not autoPlay but initialFrame is set, we should still "show" this frame.
       // The controller's seekTo logic or initialize might handle fetching it.
       // For now, initializing and then pausing might be one way if stream is not playing.
       _controller.seekTo(widget.initialFrame);
    } else {
       // Ensure a default state, perhaps ensure a frame is loaded if possible or show 'paused'.
       // If initialFrame is 0 and not autoPlay, just initialize to show frame 0 paused.
       _controller.initialize();
    }
  }

  @override
  void didUpdateWidget(StreamVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    bool controllerNeedsRecreation = false;
    if (widget.serverBaseUrl != oldWidget.serverBaseUrl || widget.targetDisplayFps != oldWidget.targetDisplayFps) {
      controllerNeedsRecreation = true;
    }

    if (controllerNeedsRecreation) {
      _controller.dispose();
      _controller = StreamVideoPlayerController(
        serverBaseUrl: widget.serverBaseUrl,
        targetDisplayFps: widget.targetDisplayFps, // Pass targetDisplayFps
      );
      // When controller is recreated, it starts fresh.
      // We need to apply initialFrame and autoPlay again.
      _sliderPosition = widget.initialFrame.toDouble();
      _controller.value = _controller.value.copyWith(frameIndex: widget.initialFrame);
      _controller._currentFrameIndex = widget.initialFrame;

      if (widget.autoPlay) {
        _controller.play();
      } else {
        _controller.seekTo(widget.initialFrame); // Seek to show the correct frame if not auto-playing
      }
    } else {
      // Controller exists, just update relevant properties
      if (widget.initialFrame != oldWidget.initialFrame && !_isUserDraggingSlider) {
        // Only seek if the external initialFrame has changed and user is not dragging.
        // This handles external seeks (e.g., from main timeline).
        _controller.seekTo(widget.initialFrame);
        // _sliderPosition will be updated by the ValueListenableBuilder listening to controller value changes.
      }
      if (widget.autoPlay != oldWidget.autoPlay) {
        if (widget.autoPlay) {
          _controller.play();
        } else {
          _controller.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: VideoPlayerWidget(controller: _controller),
          ),
        ),
        if (widget.showControls) _buildControls(),
      ],
    );
  }

  Widget _buildControls() {
    return ValueListenableBuilder<StreamVideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, child) {
        if (!_isUserDraggingSlider) {
          // Sync _sliderPosition with the actual frameIndex from the controller
          // when the user is not actively dragging the slider.
          // Use WidgetsBinding.instance.addPostFrameCallback to avoid setState during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isUserDraggingSlider && _sliderPosition != value.frameIndex.toDouble()) {
              setState(() {
                _sliderPosition = value.frameIndex.toDouble();
              });
            }
          });
        }

        return Container(
          padding: const EdgeInsets.all(8.0),
          color: Colors.black.withOpacity(0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (value.isPlaying) {
                        _controller.pause();
                      } else {
                        _controller.play();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () {
                      _controller.initialize();
                    },
                  ),
                  Text(
                    'Frame: ${value.frameIndex}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              Slider(
                value: _sliderPosition,
                min: 0,
                max: value.totalFrames > 0 ? value.totalFrames.toDouble() : (_sliderPosition > 0 ? _sliderPosition + 1 : 100.0),
                onChangeStart: (double startValue) {
                  setState(() {
                    _isUserDraggingSlider = true;
                  });
                },
                onChanged: (newValue) {
                  setState(() {
                    _sliderPosition = newValue;
                  });
                },
                onChangeEnd: (double endValue) {
                  // Ensure slider position is updated before seeking, then unlock dragging.
                  // setState is called inside onChangeEnd to reflect the final value before _isUserDraggingSlider is set to false.
                  // This helps if the controller.value update is delayed.
                  setState(() {
                    _sliderPosition = endValue; 
                    _isUserDraggingSlider = false;
                  });
                  _controller.seekTo(endValue.toInt());
                },
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
              ),
            ],
          ),
        );
      },
    );
  }
}

class VideoPlayerWidget extends StatelessWidget {
  final StreamVideoPlayerController controller;

  const VideoPlayerWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StreamVideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value.isBuffering) {
          return const Center(child: CircularProgressIndicator());
        }

        if (value.isError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 10),
                Text(
                  value.errorMessage ?? "Unknown error",
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => controller.initialize(),
                  child: const Text("Retry"),
                )
              ],
            ),
          );
        }

        return value.frame != null
            ? AspectRatio(
                aspectRatio: value.aspectRatio,
                child: _VideoSurface(image: value.frame!),
              )
            : Container(
                color: Colors.black,
                child: const Center(
                  child: Text(
                    "Waiting for stream...",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              );
      },
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
  final StreamController<ui.Image> _controller = StreamController<ui.Image>();
  http.Client? _client;
  bool _isActive = true;
  final String _instanceId; // Unique ID for logging
  
  Stream<ui.Image> get stream => _controller.stream;
  
  MjpegStream(this.url) : _instanceId = DateTime.now().millisecondsSinceEpoch.toRadixString(36) {
    logInfo("MjpegStream[\\$_instanceId] created for URL: \\$url", "MjpegStream");
    _startStreaming();
  }
  
  void _startStreaming() async {
    if (!_isActive) {
      logInfo("MjpegStream[\\$_instanceId] _startStreaming: called but already inactive. URL: \\$url", "MjpegStream");
      return;
    }
    
    try {
      logInfo("MjpegStream[\\$_instanceId] _startStreaming: Starting for URL: \\$url", "MjpegStream");
      _client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      
      final response = await _client!.send(request)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        logWarning("MjpegStream[\\$_instanceId] _startStreaming: Connection timed out for \\$url", "MjpegStream");
        throw TimeoutException('Connection timed out for \\$url');
      });
      
      if (!_isActive) {
        logInfo("MjpegStream[\\$_instanceId] _startStreaming: Became inactive during/after _client.send() for \\$url. Draining and returning.", "MjpegStream");
        try {
          await response.stream.drain();
        } catch (e) {
          logWarning("MjpegStream[\\$_instanceId] _startStreaming: Error draining response stream during abort for \\$url: \\$e", "MjpegStream");
        }
        return;
      }
      
      if (response.statusCode != 200) {
        final errorMsg = 'Failed to connect to stream: \\${response.statusCode} for \\$url';
        logError("MjpegStream[\\$_instanceId] _startStreaming: HTTP error", errorMsg, null, "MjpegStream");
        if (_isActive && !_controller.isClosed) {
          _controller.addError(Exception(errorMsg));
        }
        return;
      }
      logInfo("MjpegStream[\\$_instanceId] _startStreaming: Connected, status \\${response.statusCode} for \\$url", "MjpegStream");
      
      List<int> buffer = [];
      // Use raw strings for byte sequence definitions to avoid escaping issues with backslashes
      final boundaryBytes = Uint8List.fromList(r'--frame\r\n'.codeUnits);
      final headerEndBytes = Uint8List.fromList(r'\r\n\r\n'.codeUnits);
      int searchStartIndex = 0;

      await for (final chunk in response.stream) {
        if (!_isActive) {
          logInfo("MjpegStream[\\$_instanceId] Processing chunk: Stream became inactive for \\$url. Breaking from chunk loop.", "MjpegStream");
          break;
        }
        buffer.addAll(chunk);

        while (_isActive) {
          // 1. Find the start of a frame boundary
          int boundaryPos = _findBytes(buffer, boundaryBytes, searchStartIndex);
          if (boundaryPos == -1) {
            searchStartIndex = buffer.length > boundaryBytes.length ? buffer.length - boundaryBytes.length : 0;
            break; // Need more data
          }

          // Headers start after this boundary.
          int headersStartPos = boundaryPos + boundaryBytes.length;

          // 2. Find the end of the headers (\\r\\n\\r\\n)
          int headersEndPos = _findBytes(buffer, headerEndBytes, headersStartPos);
          if (headersEndPos == -1) {
            searchStartIndex = buffer.length > headerEndBytes.length ? buffer.length - headerEndBytes.length : headersStartPos;
            break; // Need more data for headers
          }

          int imageDataStartPos = headersEndPos + headerEndBytes.length;

          // 3. Parse Content-Length from headers
          String headersStr = String.fromCharCodes(buffer.sublist(headersStartPos, headersEndPos));
          int contentLength = -1;
          // Regex for Content-Length, case-insensitive
          final clRegex = RegExp(r"Content-Length:\s*(\d+)", caseSensitive: false, multiLine: true);
          final match = clRegex.firstMatch(headersStr);

          if (match != null && match.groupCount >= 1) {
            try {
              contentLength = int.parse(match.group(1)!);
            } catch (e) {
              logWarning("MjpegStream[\\$_instanceId] Failed to parse Content-Length from '\\${match.group(1)}' for \\$url: \\$e", "MjpegStream");
            }
          } else {
             logWarning("MjpegStream[\\$_instanceId] Content-Length header not found or invalid in frame headers for \\$url. Headers: '''\\$headersStr'''", "MjpegStream");
             // If CL is missing, we can't reliably know the frame end. Consume up to where image data would have started and look for next boundary.
             buffer = buffer.sublist(imageDataStartPos); 
             searchStartIndex = 0;
             continue; 
          }
          
          if (contentLength <= 0) {
            logWarning("MjpegStream[\\$_instanceId] Invalid Content-Length (\\${contentLength}) for \\$url. Advancing buffer past this frame's headers.", "MjpegStream");
            buffer = buffer.sublist(imageDataStartPos);
            searchStartIndex = 0;
            continue;
          }
          
          // 4. Extract image data using Content-Length
          if (buffer.length >= imageDataStartPos + contentLength) {
            Uint8List imageData = Uint8List.fromList(buffer.sublist(imageDataStartPos, imageDataStartPos + contentLength));
            
            // Advance the buffer past the image data.
            // The trailing \\r\\n from the server (if any, after the image content itself)
            // will be handled by the next boundary search.
            buffer = buffer.sublist(imageDataStartPos + contentLength);
            searchStartIndex = 0; 

            // 5. Decode and add image
            if (imageData.isNotEmpty) {
              if (_isActive) {
                try {
                  final codec = await ui.instantiateImageCodec(imageData);
                  final frameInfo = await codec.getNextFrame();
                  if (!_controller.isClosed && _isActive) {
                    _controller.add(frameInfo.image);
                  }
                } catch (e, s) {
                  logError("MjpegStream[\\$_instanceId] Failed to decode image. Length: \\${imageData.length}. Content-Length: \\$contentLength. URL: \\$url", e, s, "MjpegStream");
                  // Optionally, add an error to the stream or simply skip the frame if it's a common issue
                }
              }
            } else {
                logWarning("MjpegStream[\\$_instanceId] Extracted empty image data despite CL=\\$contentLength for \\$url.", "MjpegStream");
            }
          } else {
            // Not enough data for the image body based on Content-Length
            // Reset searchStartIndex to boundaryPos to re-evaluate when more data arrives.
            searchStartIndex = boundaryPos; 
            break; // Need more data for this frame's image body
          }

          if (!_isActive) { 
            logInfo("MjpegStream[\\$_instanceId] Post-frame processing: Stream became inactive for \\$url. Breaking from inner loop.", "MjpegStream");
            break;
          }

          // Safety check for excessive buffer growth if something goes wrong with parsing frames.
          if (buffer.length > 20 * 1024 * 1024) { // 20MB limit
            logError("MjpegStream[\\$_instanceId] MJPEG buffer exceeded 20MB for \\$url, clearing to prevent OOM.", null, null, "MjpegStream");
            buffer = []; // Clear buffer
            searchStartIndex = 0; // Reset search
            if (_isActive && !_controller.isClosed) {
                _controller.addError(Exception("MJPEG buffer overflow for \\$url"));
            }
            break; // Exit inner loop to reassess or terminate
          }
        }
      }
      
      // End of response.stream loop
      if (_isActive && !_controller.isClosed) {
        logInfo("MjpegStream[\\$_instanceId] _startStreaming: HTTP response stream ended for \\$url.", "MjpegStream");
        // Server closed the connection or stream ended.
        // We should close our controller as there will be no more data.
        await _controller.close(); 
      } else {
        logInfo("MjpegStream[\\$_instanceId] _startStreaming: Stream processing loop exited. _isActive: \\$_isActive, _controller.isClosed: \\${_controller.isClosed} for \\$url.", "MjpegStream");
      }

    } catch (e, stackTrace) {
      // Catch-all for errors during streaming setup or processing
      logInfo("MjpegStream[\\$_instanceId] _startStreaming: CATCH BLOCK. _isActive: \\$_isActive. Error for \\$url: \\$e", "MjpegStream");
      if (_isActive && !_controller.isClosed) {
        logError("MjpegStream[\\$_instanceId] _startStreaming: Error in active stream for \\$url", e, stackTrace, "MjpegStream");
        _controller.addError(e);
        await _controller.close(); // Close controller on error if active
      } else {
        logInfo("MjpegStream[\\$_instanceId] _startStreaming: Caught error but stream already inactive or controller closed for \\$url: \\$e", "MjpegStream");
      }
    } finally {
        // Ensure the HTTP client is always closed
        if (_client != null) {
            _client!.close();
            logInfo("MjpegStream[\\$_instanceId] _startStreaming: Finally block closed HTTP client for \\$url.", "MjpegStream");
        }
        _client = null; 
        
        // If the stream became inactive (due to dispose) but controller wasn't closed yet.
        if (!_isActive && !_controller.isClosed) {
           logInfo("MjpegStream[\\$_instanceId] _startStreaming: Finally block, stream was inactive, ensuring controller is closed for \\$url.", "MjpegStream");
           await _controller.close();
        }
        logInfo("MjpegStream[\\$_instanceId] _startStreaming: Finally block executed for \\$url. _isActive: \\$_isActive, controller closed: \\${_controller.isClosed}", "MjpegStream");
    }
  }

  // Helper to find a byte sequence in a list of bytes
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
    logInfo("MjpegStream[\$_instanceId] dispose() called. Current _isActive: \$_isActive, URL: \$url", "MjpegStream");
    if (!_isActive) {
      logInfo("MjpegStream[\$_instanceId] dispose(): Already inactive for \$url. Skipping.", "MjpegStream");
      return;
    }

    _isActive = false;
    logInfo("MjpegStream[\$_instanceId] dispose(): Set _isActive to false for \$url.", "MjpegStream");
    
    _client?.close();
    _client = null;
    logInfo("MjpegStream[\$_instanceId] dispose(): Client closed and nulled for \$url.", "MjpegStream");

    if (!_controller.isClosed) {
      _controller.close().catchError((e, s) {
        logWarning("MjpegStream[\$_instanceId] dispose(): Error closing controller for \$url: \$e", "MjpegStream");
      });
      logInfo("MjpegStream[\$_instanceId] dispose(): Controller close initiated for \$url.", "MjpegStream");
    } else {
      logInfo("MjpegStream[\$_instanceId] dispose(): Controller already closed for \$url.", "MjpegStream");
    }
    logInfo("MjpegStream[\$_instanceId] dispose(): Fully disposed for \$url.", "MjpegStream");
  }
}