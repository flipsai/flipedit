import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/player/websocket_frame_player_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

/// A widget that displays video frames received via WebSocket with client-side caching
class WebSocketFramePlayer extends StatelessWidget with WatchItMixin {
  /// The WebSocket URL
  final String websocketUrl;
  
  /// Whether to autoplay the video
  final bool autoPlay;
  
  /// Whether to show controls
  final bool showControls;
  
  /// Constructor
  const WebSocketFramePlayer({
    Key? key,
    required this.websocketUrl,
    this.autoPlay = true,
    this.showControls = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    logDebug("Building WebSocketFramePlayer...", 'WebSocketFramePlayer');
    
    return ChangeNotifierProvider(
      create: (_) => WebSocketFramePlayerViewModel(),
      child: _WebSocketFramePlayerContent(
        websocketUrl: websocketUrl,
        autoPlay: autoPlay,
        showControls: showControls,
      ),
    );
  }
}

class _WebSocketFramePlayerContent extends StatefulWidget {
  final String websocketUrl;
  final bool autoPlay;
  final bool showControls;

  const _WebSocketFramePlayerContent({
    Key? key,
    required this.websocketUrl,
    required this.autoPlay,
    required this.showControls,
  }) : super(key: key);

  @override
  _WebSocketFramePlayerContentState createState() => _WebSocketFramePlayerContentState();
}

class _WebSocketFramePlayerContentState extends State<_WebSocketFramePlayerContent> {
  late WebSocketFramePlayerViewModel _viewModel;
  bool _connecting = true;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _viewModel = Provider.of<WebSocketFramePlayerViewModel>(context, listen: false);
    _connectToServer();
  }
  
  Future<void> _connectToServer() async {
    try {
      setState(() {
        _connecting = true;
        _errorMessage = null;
      });
      
      await _viewModel.connect(widget.websocketUrl);
      
      setState(() {
        _connecting = false;
      });
      
      if (widget.autoPlay) {
        _viewModel.play();
      }
    } catch (e) {
      setState(() {
        _connecting = false;
        _errorMessage = 'Failed to connect: $e';
      });
      logDebug("Error connecting to WebSocket: $e", 'WebSocketFramePlayer');
    }
  }
  
  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<WebSocketFramePlayerViewModel>(
      builder: (context, viewModel, child) {
        // Show loading indicator while connecting
        if (_connecting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        // Show error message if connection failed
        if (_errorMessage != null) {
          return Center(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        
        // Show "No media loaded" if not connected
        if (!viewModel.isConnected) {
          return Container(
            color: const Color(0xFF333333),
            child: const Center(
              child: Text(
                'No media loaded',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        
        return Column(
          children: [
            Expanded(
              child: _buildFrameDisplay(viewModel),
            ),
            if (widget.showControls) _buildControls(viewModel),
          ],
        );
      },
    );
  }
  
  Widget _buildFrameDisplay(WebSocketFramePlayerViewModel viewModel) {
    // Show black container if no frame is available
    if (viewModel.currentFrameBytes == null) {
      return Container(color: Colors.black);
    }
    
    // Display current frame
    return Image.memory(
      viewModel.currentFrameBytes!,
      fit: BoxFit.contain,
      gaplessPlayback: true, // Important for smooth playback
    );
  }
  
  Widget _buildControls(WebSocketFramePlayerViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  viewModel.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                onPressed: () {
                  if (viewModel.isPlaying) {
                    viewModel.pause();
                  } else {
                    viewModel.play();
                  }
                },
              ),
              if (viewModel.totalFrames > 0)
                Expanded(
                  child: Slider(
                    value: viewModel.currentFrameIndex.toDouble(),
                    min: 0,
                    max: (viewModel.totalFrames - 1).toDouble(),
                    onChanged: (value) {
                      final frameIndex = value.toInt();
                      viewModel.seekToFrame(frameIndex);
                    },
                  ),
                ),
              Text(
                '${viewModel.currentFrameIndex} / ${viewModel.totalFrames}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => viewModel.clearCache(),
                child: const Text('Clear Cache'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => viewModel.refreshFromDatabase(),
                child: const Text('Refresh DB'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}