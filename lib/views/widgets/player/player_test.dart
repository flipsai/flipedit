import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:watch_it/watch_it.dart';
import '../../../models/video_texture_model.dart';
import '../../../services/video_texture_service.dart';
import '../../../viewmodels/timeline_navigation_viewmodel.dart';
import '../../../viewmodels/timeline_state_viewmodel.dart';
import '../../../models/clip.dart';

class PlayerTest extends StatefulWidget with WatchItStatefulWidgetMixin {
  const PlayerTest({super.key});

  @override
  State<PlayerTest> createState() => _PlayerTestState();
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

class _PlayerTestState extends State<PlayerTest> {
  late final VideoTextureService _textureService;
  late final VideoTextureModel _textureModel;
  late final TimelineNavigationViewModel _navigationViewModel;
  late final TimelineStateViewModel _stateViewModel;
  
  final Map<int, VideoPlayerController> _controllers = {};
  
  Timer? _playbackTimer;
  int renderTime = 0;
  int _currentDisplay = 0;
  
  // Configuration
  final int _numDisplays = 1;
  final String _textureModelId = 'player_test';
  
  // Timeline synchronization
  ClipModel? _currentClip;
  VoidCallback? _currentFrameListener;
  VoidCallback? _clipsListener;

  @override
  void initState() {
    super.initState();
    
    // Get services and view models from DI
    _textureService = di.get<VideoTextureService>();
    _navigationViewModel = di.get<TimelineNavigationViewModel>();
    _stateViewModel = di.get<TimelineStateViewModel>();
    
    // Create or get existing texture model
    _textureModel = _textureService.createTextureModel(_textureModelId);
    
    _initializeTextures();
    _setupTimelineListeners();
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
  
  void _setupTimelineListeners() {
    // Listen for selected clip changes
    _clipsListener = () {
      final selectedClipId = _stateViewModel.selectedClipId;
      
      if (selectedClipId != null) {
        try {
          final selectedClip = _stateViewModel.clips
              .firstWhere((clip) => clip.databaseId == selectedClipId);
          
          // If the clip changed, update the video
          if (_currentClip?.databaseId != selectedClip.databaseId) {
            _currentClip = selectedClip;
            _loadCurrentClip();
          }
        } catch (e) {
          debugPrint("Selected clip not found: $e");
        }
      } else {
        // If no clip is selected and we have active clips, try to use the first one
        final allClips = _stateViewModel.clips;
        if (allClips.isNotEmpty && (_currentClip == null || 
            !allClips.any((clip) => clip.databaseId == _currentClip!.databaseId))) {
          _currentClip = allClips.first;
          _loadCurrentClip();
        }
      }
    };
    
    // Listen for playback position changes
    _currentFrameListener = () {
      final currentFrame = _navigationViewModel.currentFrameNotifier.value;
      final controller = _currentController;
      
      if (controller != null && controller.capture != null && !controller.isPlaying) {
        // Only update if we're not already playing and the frame changed significantly
        if ((controller.currentFrame - currentFrame).abs() > 1) {
          controller.currentFrame = currentFrame;
          _seekToCurrentFrame();
        }
      }
    };
    
    _stateViewModel.selectedClipIdNotifier.addListener(_clipsListener!);
    _navigationViewModel.currentFrameNotifier.addListener(_currentFrameListener!);
    
    // Initial call to load any existing clip
    _clipsListener!();
  }
  
  void _loadCurrentClip() {
    if (_currentClip == null) return;
    
    _stopPlayback();
    
    final controller = _currentController;
    if (controller != null) {
      // Get the clip's source path
      final filePath = _currentClip!.sourcePath;
      
      if (filePath.isNotEmpty) {
        controller.videoPath = filePath;
        controller.capture?.release();
        controller.capture = null;
        controller.currentFrame = 0;
        controller.frameCount = 0;
        
        _initVideoCapture(controller);
        
        // Set initial position to timeline's current frame
        if (controller.capture != null) {
          controller.currentFrame = _navigationViewModel.currentFrameNotifier.value;
          _seekToCurrentFrame();
        }
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }
  
  void _seekToCurrentFrame() {
    final controller = _currentController;
    if (controller == null || controller.capture == null) return;
    
    try {
      controller.capture!.set(cv.CAP_PROP_POS_FRAMES, controller.currentFrame.toDouble());
      _renderFrame(_currentDisplay, controller);
    } catch (e) {
      debugPrint("Error seeking to frame: $e");
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
      _showError('No video loaded');
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
          
          // Update timeline position if this is the main display
          if (display == _currentDisplay) {
            _navigationViewModel.currentFrame = controller.currentFrame;
          }
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
    
    // Remove timeline listeners
    if (_clipsListener != null) {
      _stateViewModel.selectedClipIdNotifier.removeListener(_clipsListener!);
    }
    
    if (_currentFrameListener != null) {
      _navigationViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    }
    
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
    final clip = _currentClip;
    
    // Watch necessary timeline state (using WatchItMixin)
    final selectedClipId = watchValue((TimelineStateViewModel vm) => vm.selectedClipIdNotifier);
    final currentFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    
    return Column(
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
              if (clip != null)
                Text(
                  'Current Clip: ${clip.name ?? "Unnamed"}',
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
    );
  }
}
 