import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:watch_it/watch_it.dart'; // Import watch_it
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Import ViewModel

/// PreviewPanel displays the video stream from the Python WebSocket server.
class PreviewPanel extends StatefulWidget with WatchItStatefulWidgetMixin { // Apply mixin here
  const PreviewPanel({super.key});

  @override
  _PreviewPanelState createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> { // Remove mixin from State
  // WebSocket connection parameters
  final String _wsUrl = 'ws://localhost:8080'; // Default URL
  
  WebSocketChannel? _channel;
  late TimelineNavigationViewModel _timelineNavViewModel; // Add ViewModel instance
  ui.Image? _currentFrame;
  bool _isConnected = false;
  String _status = 'Disconnected';
  
  // Performance tracking
  int _framesReceived = 0;
  int _fps = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  
  // Controls
  bool _autoConnect = true; // Automatically connect on widget init
  Timer? _fpsTimer;
  
  // Listener for playback state changes
  VoidCallback? _isPlayingListener;
  
  @override
  void initState() {
    super.initState();
    
    _timelineNavViewModel = di<TimelineNavigationViewModel>(); // Get ViewModel instance
    
    // Update FPS counter once per second
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) { // Check if the widget is still mounted
        setState(() {
          _fps = _framesReceived;
          _framesReceived = 0;
        });
      }
    });
    
    // Auto-connect if enabled
    if (_autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { // Ensure widget is mounted before connecting
          _connectToWebSocket();
        }
      });
    }
    
    // Add listener for playback state changes
    _isPlayingListener = () {
      final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
      _sendPlaybackCommand(isPlaying);
    };
    _timelineNavViewModel.isPlayingNotifier.addListener(_isPlayingListener!);
  }
  
  @override
  void dispose() {
    // Remove listener
    if (_isPlayingListener != null) {
      _timelineNavViewModel.isPlayingNotifier.removeListener(_isPlayingListener!);
    }
    _fpsTimer?.cancel(); // Cancel the timer
    _disconnectWebSocket();
    super.dispose();
  }
  
  // Method to send play/pause command
  void _sendPlaybackCommand(bool isPlaying) {
    if (_channel != null && _isConnected) {
      final command = isPlaying ? "play" : "pause";
      debugPrint('Sending command to Python server: $command');
      try {
        _channel!.sink.add(command);
      } catch (e) {
        debugPrint('Error sending command: $e');
        // Handle potential errors, e.g., if the connection is closing
      }
    }
  }
  
  void _connectToWebSocket() {
    if (_isConnected) {
      _disconnectWebSocket();
    }
    
    if (mounted) {
      setState(() {
        _status = 'Connecting...';
      });
    }
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      // Immediately send current playback state upon connection
      _sendPlaybackCommand(_timelineNavViewModel.isPlayingNotifier.value);
      
      _channel!.stream.listen(
        (dynamic message) {
          _handleIncomingFrame(message);
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _status = 'Error: $error';
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _status = 'Disconnected';
            });
          }
          // Attempt to reconnect after a delay if autoConnect is true
          if (_autoConnect) {
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted && !_isConnected) {
                _connectToWebSocket();
              }
            });
          }
        },
        cancelOnError: true, // Close the stream on error
      );
      
      if (mounted) {
        setState(() {
          _isConnected = true;
          _status = 'Connected';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _status = 'Connection Error: $e';
        });
      }
    }
  }
  
  void _disconnectWebSocket() {
    _channel?.sink.close();
    _channel = null; // Ensure channel is nullified
    if (mounted) {
      setState(() {
        _isConnected = false;
        _status = 'Disconnected';
        _currentFrame = null; // Clear frame on disconnect
      });
    }
  }
  
  void _handleIncomingFrame(dynamic message) {
    if (message is String) {
      try {
        // Decode base64 image
        final Uint8List bytes = base64Decode(message);
        _processImageBytes(bytes);
      } catch (e) {
        debugPrint('Error decoding frame: $e');
      }
    } else if (message is List<int>) {
      // Handle binary frame (though server sends base64 string)
      final Uint8List bytes = Uint8List.fromList(message);
      _processImageBytes(bytes);
    }
  }
  
  void _processImageBytes(Uint8List bytes) {
    // Use decodeImageFromList for better performance and error handling
    ui.decodeImageFromList(bytes, (ui.Image result) {
      if (mounted) {
        setState(() {
          _currentFrame = result;
          _framesReceived++;
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluentTheme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            color: _isConnected ? Colors.green.lighter : Colors.red.lighter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Preview Stream: $_status'),
                Text('FPS: $_fps'),
              ],
            ),
          ),
          
          // Video display
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _currentFrame != null
                    ? VideoFrameWidget(image: _currentFrame!)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const ProgressRing(),
                          const SizedBox(height: 10),
                          Text(
                            _status,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to render the video frame using CustomPainter
class VideoFrameWidget extends StatelessWidget {
  final ui.Image image;
  
  const VideoFrameWidget({super.key, required this.image});
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: VideoFramePainter(image),
      size: Size.infinite, // Takes available space
    );
  }
}

/// CustomPainter to draw the video frame, maintaining aspect ratio
class VideoFramePainter extends CustomPainter {
  final ui.Image image;
  
  VideoFramePainter(this.image);
  
  @override
  void paint(Canvas canvas, Size size) {
    // Calculate aspect ratios
    final double imageRatio = image.width / image.height;
    final double screenRatio = size.width / size.height;
    
    double drawWidth;
    double drawHeight;
    
    // Determine drawing dimensions to fit the image within the bounds
    if (imageRatio > screenRatio) {
      // Image is wider than the available space
      drawWidth = size.width;
      drawHeight = drawWidth / imageRatio;
    } else {
      // Image is taller than the available space
      drawHeight = size.height;
      drawWidth = drawHeight * imageRatio;
    }
    
    // Calculate the position to center the image
    final Offset position = Offset(
      (size.width - drawWidth) / 2,
      (size.height - drawHeight) / 2,
    );
    
    // Define the source rectangle (entire image)
    final Rect sourceRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    
    // Define the destination rectangle (where to draw on canvas)
    final Rect destRect = position & Size(drawWidth, drawHeight);
    
    // Draw the image
    canvas.drawImageRect(
      image,
      sourceRect,
      destRect,
      Paint(), // Use default Paint settings
    );
  }
  
  @override
  bool shouldRepaint(VideoFramePainter oldDelegate) {
    // Repaint only if the image object itself has changed
    return image != oldDelegate.image;
  }
}
