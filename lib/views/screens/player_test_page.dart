import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:watch_it/watch_it.dart';
import '../../models/video_texture_model.dart';
import '../../services/video_texture_service.dart';

class PlayerTestPage extends StatefulWidget {
  const PlayerTestPage({super.key});

  @override
  State<PlayerTestPage> createState() => _PlayerTestPageState();
}

class VideoPlayerController {
  final String id;
  final int displayIndex;
  cv.VideoCapture? capture;
  String? videoPath;
  int currentFrame = 0;
  int frameCount = 0;
  bool isPlaying = false;
  
  VideoPlayerController({required this.id, this.displayIndex = 0});
  
  void dispose() {
    capture?.release();
  }
}

class _PlayerTestPageState extends State<PlayerTestPage> {
  late final VideoTextureService _textureService;
  late final VideoTextureModel _textureModel;
  final Map<int, VideoPlayerController> _controllers = {};
  
  Timer? _playbackTimer;
  int renderTime = 0;
  int _currentDisplay = 0;
  
  // Configuration
  final int _numDisplays = 1; // Can be increased for multi-video support
  final String _textureModelId = 'player_test';

  @override
  void initState() {
    super.initState();
    
    // Get the service from DI
    _textureService = di.get<VideoTextureService>();
    
    // Create or get existing texture model
    _textureModel = _textureService.createTextureModel(_textureModelId);
    
    _initializeTextures();
  }

  Future<void> _initializeTextures() async {
    await _textureModel.createSession(_textureModelId, numDisplays: _numDisplays);
    
    // Create controllers for each display
    for (int i = 0; i < _numDisplays; i++) {
      _controllers[i] = VideoPlayerController(id: 'video_$i', displayIndex: i);
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  VideoPlayerController? get _currentController => _controllers[_currentDisplay];

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    
    if (result != null) {
      final file = result.files.single;
      final path = file.path;
      
      if (path != null && mounted) {
        // Stop current playback
        _stopPlayback();
        
        // Update current controller
        final controller = _currentController;
        if (controller != null) {
          controller.videoPath = path;
          controller.capture?.release();
          controller.capture = null;
          controller.currentFrame = 0;
          controller.frameCount = 0;
          
          _initVideoCapture(controller);
        }
        
        setState(() {});
      }
    }
  }

  void _initVideoCapture(VideoPlayerController controller) {
    if (controller.videoPath == null) {
      debugPrint("Video path is null for display ${controller.displayIndex}");
      return;
    }
    
    if (!File(controller.videoPath!).existsSync()) {
      debugPrint("Video file not found: ${controller.videoPath}");
      _showError('Video file not found');
      return;
    }

    try {
      controller.capture?.release();
      controller.capture = cv.VideoCapture.fromFile(controller.videoPath!);
      
      if (controller.capture!.isOpened) {
        controller.frameCount = controller.capture!.get(cv.CAP_PROP_FRAME_COUNT).toInt();
        controller.currentFrame = 0;
        debugPrint("Video capture initialized for display ${controller.displayIndex}. Frame count: ${controller.frameCount}");
      } else {
        debugPrint("Failed to open video: ${controller.videoPath}");
        _showError('Could not open video');
        controller.capture = null;
      }
    } catch (e) {
      debugPrint("Error initializing VideoCapture: $e");
      _showError('Error initializing video: ${e.toString()}');
      controller.capture = null;
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _startPlayback() {
    // Check if current display is ready
    if (!_textureModel.isReady(_currentDisplay)) {
      _showError('Texture not ready for display $_currentDisplay');
      return;
    }

    final controller = _currentController;
    if (controller == null || controller.capture == null || !controller.capture!.isOpened) {
      _showError('Please pick a video file first');
      return;
    }

    debugPrint("Starting playback on display $_currentDisplay");
    controller.isPlaying = true;

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 1000 ~/ 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Render frames for all playing controllers
      bool anyPlaying = false;
      
      for (final entry in _controllers.entries) {
        final display = entry.key;
        final controller = entry.value;
        
        if (controller.isPlaying && controller.capture != null) {
          anyPlaying = true;
          _renderFrame(display, controller);
        }
      }
      
      if (!anyPlaying) {
        timer.cancel();
      }
    });
    
    setState(() {});
  }

  void _renderFrame(int display, VideoPlayerController controller) {
    if (!_textureModel.isReady(display)) {
      return;
    }

    final capture = controller.capture;
    if (capture == null || !capture.isOpened) {
      return;
    }

    // Loop video if needed
    if (controller.currentFrame >= controller.frameCount && controller.frameCount > 0) {
      capture.set(cv.CAP_PROP_POS_FRAMES, 0);
      controller.currentFrame = 0;
    }

    final result = capture.read();
    final success = result.$1;
    final mat = result.$2;

    if (success && !mat.isEmpty) {
      final width = mat.cols;
      final height = mat.rows;

      final pic = cv.cvtColor(mat, cv.COLOR_RGB2RGBA);
      final picAddr = pic.dataPtr;
      final len = pic.total * pic.elemSize;
      
      final t1 = DateTime.now().microsecondsSinceEpoch;
      
      // Render to the specific display
      _textureModel.renderFrame(display, picAddr, len, width, height);
      
      final t2 = DateTime.now().microsecondsSinceEpoch;
      
      mat.dispose();
      pic.dispose();

      if (mounted && display == _currentDisplay) {
        setState(() {
          renderTime = t2 - t1;
          controller.currentFrame += 1;
        });
      }
    }
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    
    for (final controller in _controllers.values) {
      controller.isPlaying = false;
    }
    
    setState(() {});
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    
    // The texture model is managed by the service, so we don't dispose it directly
    // Just notify the service that we're done with it
    _textureService.disposeTextureModel(_textureModelId);
    
    super.dispose();
  }

  Widget _buildVideoDisplay(int display) {
    // Watch the texture ID changes using ValueListenableBuilder
    final textureIdNotifier = _textureModel.getTextureId(display);
    
    return ValueListenableBuilder<int>(
      valueListenable: textureIdNotifier,
      builder: (context, textureId, child) {
        if (textureId == -1) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        return Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Texture(textureId: textureId),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _currentController;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('FlipEdit Video Player - Display $_currentDisplay'),
        actions: [
          if (_numDisplays > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.monitor),
              onSelected: (display) {
                setState(() {
                  _currentDisplay = display;
                });
              },
              itemBuilder: (context) => List.generate(
                _numDisplays,
                (i) => PopupMenuItem(
                  value: i,
                  child: Text('Display $i'),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Video display area
          Expanded(
            child: _buildVideoDisplay(_currentDisplay),
          ),
          
          // Info panel
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[900],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      'Display: $_currentDisplay',
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Ready: ${_textureModel.isReady(_currentDisplay)}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (renderTime > 0)
                      Text(
                        'FPS: ${1000000 ~/ renderTime}',
                        style: const TextStyle(color: Colors.green),
                      ),
                  ],
                ),
                if (controller != null && controller.capture != null)
                  Text(
                    'Frame: ${controller.currentFrame} / ${controller.frameCount}',
                    style: const TextStyle(color: Colors.white),
                  ),
              ],
            ),
          ),
          
          // Control panel
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Open Video',
                      onPressed: _pickVideo,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        controller?.isPlaying == true ? Icons.pause : Icons.play_arrow,
                      ),
                      tooltip: controller?.isPlaying == true ? 'Pause' : 'Play',
                      onPressed: controller?.capture != null
                        ? () {
                            if (controller?.isPlaying == true) {
                              _stopPlayback();
                            } else {
                              _startPlayback();
                            }
                          }
                        : null,
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.stop),
                      tooltip: 'Stop',
                      onPressed: controller?.isPlaying == true ? _stopPlayback : null,
                    ),
                  ],
                ),
                
                // Video info
                if (controller?.videoPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'File: ${controller!.videoPath}',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
