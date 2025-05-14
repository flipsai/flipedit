import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:watch_it/watch_it.dart';
import '../../../models/video_texture_model.dart';
import '../../../services/video_texture_service.dart';

class DemoVideoPlayer extends StatefulWidget {
  const DemoVideoPlayer({super.key});

  @override
  State<DemoVideoPlayer> createState() => _DemoVideoPlayerState();
}

class _DemoVideoPlayerState extends State<DemoVideoPlayer> {
  late final VideoTextureService _textureService;
  late final VideoTextureModel _textureModel;
  
  cv.VideoCapture? _capture;
  Timer? _playbackTimer;
  
  // State variables
  String? _videoPath;
  bool _isPlaying = false;
  int _currentFrame = 0;
  int _frameCount = 0;
  double _fps = 30.0;
  int _renderTime = 0;
  
  // Texture state
  final String _textureModelId = 'demo_player';
  final ValueNotifier<int> _textureIdNotifier = ValueNotifier(-1);
  
  @override
  void initState() {
    super.initState();
    
    // Get the service from DI
    _textureService = di.get<VideoTextureService>();
    
    // Create texture model
    _textureModel = _textureService.createTextureModel(_textureModelId);
    
    _initializeTexture();
  }
  
  Future<void> _initializeTexture() async {
    await _textureModel.createSession(_textureModelId, numDisplays: 1);
    
    // Listen to texture ID changes
    final textureIdNotifier = _textureModel.getTextureId(0);
    textureIdNotifier.addListener(() {
      if (mounted) {
        _textureIdNotifier.value = textureIdNotifier.value;
      }
    });
    _textureIdNotifier.value = textureIdNotifier.value;
    
    if (mounted) {
      setState(() {});
    }
  }
  
  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );
    
    if (result != null) {
      final file = result.files.single;
      final path = file.path;
      
      if (path != null && mounted) {
        _stopPlayback();
        _loadVideo(path);
      }
    }
  }
  
  Future<void> _loadDemoVideo() async {
    // Try to load a sample video from the assets directory
    final demoVideoPath = '/Users/remymenard/code/flipedit/assets/sample_video_1.mp4';
    
    if (File(demoVideoPath).existsSync()) {
      _loadVideo(demoVideoPath);
    } else {
      _showError('Demo video not found. Please pick a video file.');
    }
  }
  
  void _loadVideo(String path) {
    _capture?.release();
    
    try {
      _capture = cv.VideoCapture.fromFile(path);
      
      if (_capture!.isOpened) {
        _frameCount = _capture!.get(cv.CAP_PROP_FRAME_COUNT).toInt();
        _fps = _capture!.get(cv.CAP_PROP_FPS);
        _currentFrame = 0;
        _videoPath = path;
        
        debugPrint("Video loaded: $path, frames: $_frameCount, fps: $_fps");
        
        // Render first frame
        _renderFrame();
        
        setState(() {});
      } else {
        _showError('Failed to open video');
        _capture = null;
      }
    } catch (e) {
      _showError('Error loading video: $e');
      _capture = null;
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
    if (_capture == null || !_capture!.isOpened || !_textureModel.isReady(0)) {
      return;
    }
    
    _isPlaying = true;
    
    // Use exact frame timing like the demo
    final frameDuration = Duration(milliseconds: (1000 / _fps).round());
    
    // Track timing for debugging
    DateTime lastFrameTime = DateTime.now();
    int frameDrops = 0;
    
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(frameDuration, (timer) {
      if (!mounted || !_isPlaying) {
        timer.cancel();
        return;
      }
      
      final now = DateTime.now();
      final elapsed = now.difference(lastFrameTime).inMilliseconds;
      
      // Debug: Check if we're falling behind
      if (elapsed > (1000 / _fps * 1.5)) {
        frameDrops++;
        debugPrint('Frame drop detected! Elapsed: ${elapsed}ms, Expected: ${(1000 / _fps).round()}ms');
      }
      
      _renderFrame();
      
      _currentFrame++;
      if (_currentFrame >= _frameCount) {
        _currentFrame = 0; // Loop
        debugPrint('Loop completed. Frame drops: $frameDrops');
        frameDrops = 0;
      }
      
      lastFrameTime = now;
      setState(() {});
    });
  }
  
  void _stopPlayback() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() {});
  }
  
  void _renderFrame() {
    if (_capture == null || !_capture!.isOpened || !_textureModel.isReady(0)) {
      return;
    }
    
    final seekStart = DateTime.now().microsecondsSinceEpoch;
    _capture!.set(cv.CAP_PROP_POS_FRAMES, _currentFrame.toDouble());
    final seekEnd = DateTime.now().microsecondsSinceEpoch;
    
    final readStart = DateTime.now().microsecondsSinceEpoch;
    final result = _capture!.read();
    final readEnd = DateTime.now().microsecondsSinceEpoch;
    
    if (result.$1 && !result.$2.isEmpty) {
      final mat = result.$2;
      
      final convertStart = DateTime.now().microsecondsSinceEpoch;
      final pic = cv.cvtColor(mat, cv.COLOR_BGR2RGBA);
      final convertEnd = DateTime.now().microsecondsSinceEpoch;
      
      final renderStart = DateTime.now().microsecondsSinceEpoch;
      _textureModel.renderFrame(
        0,
        pic.dataPtr,
        pic.total * pic.elemSize,
        pic.cols,
        pic.rows,
      );
      final renderEnd = DateTime.now().microsecondsSinceEpoch;
      
      // Log timing breakdown every 30 frames
      if (_currentFrame % 30 == 0) {
        debugPrint('Frame $_currentFrame timing (µs):');
        debugPrint('  Seek: ${seekEnd - seekStart}');
        debugPrint('  Read: ${readEnd - readStart}');
        debugPrint('  Convert: ${convertEnd - convertStart}');
        debugPrint('  Render: ${renderEnd - renderStart}');
        debugPrint('  Total: ${renderEnd - seekStart}');
      }
      
      _renderTime = renderEnd - seekStart;
      
      mat.dispose();
      pic.dispose();
    }
  }
  
  void _seekToFrame(int frame) {
    if (_capture == null || !_capture!.isOpened) return;
    
    _currentFrame = frame.clamp(0, _frameCount - 1);
    _renderFrame();
    setState(() {});
  }
  
  @override
  void dispose() {
    _playbackTimer?.cancel();
    _capture?.release();
    _textureService.disposeTextureModel(_textureModelId);
    _textureIdNotifier.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Video display
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: _textureIdNotifier,
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
          ),
        ),
        
        // Info panel
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Colors.grey[900],
          child: Column(
            children: [
              if (_videoPath != null)
                Text(
                  'Video: ${_videoPath!.split('/').last}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    'Frame: $_currentFrame / $_frameCount',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'FPS: ${_fps.toStringAsFixed(1)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (_renderTime > 0)
                    Text(
                      'Render: ${1000000 ~/ _renderTime} FPS',
                      style: const TextStyle(color: Colors.green),
                    ),
                ],
              ),
            ],
          ),
        ),
        
        // Control panel
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Progress bar
              if (_capture != null)
                Slider(
                  value: _currentFrame.toDouble(),
                  min: 0,
                  max: (_frameCount - 1).toDouble(),
                  onChanged: (value) {
                    _seekToFrame(value.toInt());
                  },
                ),
              
              // Playback controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: 'Open Video',
                    onPressed: _pickVideo,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.movie),
                    tooltip: 'Load Demo Video',
                    onPressed: _loadDemoVideo,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                    onPressed: _capture != null
                        ? () {
                            if (_isPlaying) {
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
                    onPressed: _isPlaying ? _stopPlayback : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
