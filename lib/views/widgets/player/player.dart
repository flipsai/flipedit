import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:watch_it/watch_it.dart';
import '../../../models/video_texture_model.dart';
import '../../../services/video_texture_service.dart';
import '../../../services/video/optimized_video_player_service.dart';
import '../../../viewmodels/timeline_navigation_viewmodel.dart';
import '../../../viewmodels/timeline_state_viewmodel.dart';
import '../../../models/clip.dart';
import '../../../models/enums/clip_type.dart';

class Player extends StatefulWidget with WatchItStatefulWidgetMixin {
  const Player({super.key});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  late final VideoTextureService _textureService;
  late final VideoTextureModel _textureModel;
  late final TimelineNavigationViewModel _navigationViewModel;
  late final TimelineStateViewModel _stateViewModel;
  
  OptimizedVideoPlayerService? _playerService;
  String? _playerErrorMessage;
  
  // Configuration
  final String _textureModelId = 'main_player';
  final int _displayIndex = 0;
  
  // Current clip being played
  ClipModel? _currentClip;
  VoidCallback? _currentFrameListener;
  VoidCallback? _playPauseListener;
  bool _updatingFromTimeline = false;
  bool _updatingFromPlayer = false;
  
  // Performance metrics
  Map<String, dynamic> _performanceMetrics = {};
  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();
    
    // Get services and view models from DI
    _textureService = di.get<VideoTextureService>();
    _navigationViewModel = di.get<TimelineNavigationViewModel>();
    _stateViewModel = di.get<TimelineStateViewModel>();
    
    // Create or get existing texture model
    _textureModel = _textureService.createTextureModel(_textureModelId);
    
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    debugPrint('Initializing player...');
    
    // Create texture session
    await _textureModel.createSession(_textureModelId, numDisplays: 1);
    debugPrint('Texture session created');
    
    // Create player service
    _playerService = OptimizedVideoPlayerService(
      onFrameChanged: _onFrameChanged,
      onError: _onError,
    );
    debugPrint('Player service created');
    
    // Setup timeline listeners
    _setupTimelineListeners();
    
    // Connect player to playback service
    final playbackService = di.get<TimelineNavigationViewModel>().playbackService;
    // playbackService.setVideoPlayerService(_playerService);
    debugPrint('Connected to playback service');
    
    // Start performance metrics timer
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updatePerformanceMetrics();
    });
    
    if (mounted) {
      setState(() {});
    }
  }
  
  void _setupTimelineListeners() {
    debugPrint('Setting up timeline listeners...');
    
    // Listen for playback position changes
    _currentFrameListener = () {
      if (_updatingFromPlayer) return;
      
      _updatingFromTimeline = true;
      final currentFrame = _navigationViewModel.currentFrameNotifier.value;
      
      debugPrint('Timeline position changed to frame: $currentFrame');
      
      // Load the clip at the current playhead position
      _loadClipAtPlayhead();
      
      // Update player position
      if (_playerService != null && !_playerService!.isPlaying) {
        final playerFrame = _playerService!.currentFrame;
        if ((playerFrame - currentFrame).abs() > 1) {
          _playerService!.seek(currentFrame);
        }
      }
      _updatingFromTimeline = false;
    };
    
    // Listen for playback state changes from timeline
    _playPauseListener = () {
      debugPrint('Timeline play state changed: ${_navigationViewModel.isPlaying}');
      if (_playerService != null) {
        final timelineIsPlaying = _navigationViewModel.isPlaying;
        final playerIsPlaying = _playerService!.isPlaying;
        
        debugPrint('Timeline playing: $timelineIsPlaying, Player playing: $playerIsPlaying');
        
        if (timelineIsPlaying != playerIsPlaying) {
          if (timelineIsPlaying) {
            debugPrint('Starting player from timeline');
            // Ensure we have the right clip loaded before playing
            _loadClipAtPlayhead();
            _playerService!.play();
          } else {
            debugPrint('Pausing player from timeline');
            _playerService!.pause();
          }
          setState(() {});
        }
      }
    };
    
    _navigationViewModel.isPlayingNotifier.addListener(_playPauseListener!);
    _navigationViewModel.currentFrameNotifier.addListener(_currentFrameListener!);
    
    // Initial load - show what's at the current playhead
    _loadClipAtPlayhead();
  }
  
  void _loadClipAtPlayhead() {
    final clips = _stateViewModel.clips;
    final currentFrame = _navigationViewModel.currentFrame;
    final currentTimeMs = ClipModel.framesToMs(currentFrame);
    
    debugPrint('Loading clip at playhead - frame: $currentFrame, time: $currentTimeMs ms');
    
    // Find the clip at the current playhead position
    ClipModel? clipAtPlayhead;
    for (final clip in clips) {
      if (clip.type == ClipType.video &&
          clip.startTimeOnTrackMs <= currentTimeMs &&
          clip.endTimeOnTrackMs > currentTimeMs) {
        clipAtPlayhead = clip;
        debugPrint('Found clip at playhead: ${clip.name}');
        break;
      }
    }
    
    // If we found a clip and it's different from the current one, load it
    if (clipAtPlayhead != null && _currentClip?.databaseId != clipAtPlayhead.databaseId) {
      _currentClip = clipAtPlayhead;
      _loadCurrentClip();
    } else if (clipAtPlayhead == null && _currentClip != null) {
      // No clip at playhead, clear the current clip
      debugPrint('No clip at playhead position');
      _currentClip = null;
      // You might want to clear the display or show a blank frame here
    }
  }
  
  Future<void> _loadCurrentClip() async {
    if (mounted) {
      setState(() {
        _playerErrorMessage = null;
      });
    }
    debugPrint('Loading clip: ${_currentClip?.name}');
    if (_currentClip == null || _playerService == null) {
      debugPrint('Cannot load clip: clip=$_currentClip, playerService=$_playerService');
      if (mounted) {
        setState(() {
          _playerErrorMessage = 'Cannot load: No current clip or player service unavailable.';
        });
      }
      return;
    }
    
    final filePath = _currentClip!.sourcePath;
    debugPrint('File path: $filePath');
    
    if (filePath.isNotEmpty && File(filePath).existsSync()) {
      debugPrint('File exists, loading video...');
      
      final wasPlaying = _playerService!.isPlaying;
      _playerService!.pause();
      
      final success = await _playerService!.loadVideo(
        filePath,
        _textureModel,
        _displayIndex,
      );
      
      debugPrint('Video load success: $success');
      
      if (success) {
        // Calculate the position within this clip
        final currentFrame = _navigationViewModel.currentFrame;
        final currentTimeMs = ClipModel.framesToMs(currentFrame);
        final clipStartTimeMs = _currentClip!.startTimeOnTrackMs;
        final positionInClipMs = currentTimeMs - clipStartTimeMs;
        final frameInClip = ClipModel.msToFrames(positionInClipMs);
        
        debugPrint('Seeking to frame $frameInClip in clip');
        _playerService!.seek(frameInClip);
        
        // Resume playing if it was playing before
        if (wasPlaying) {
          _playerService!.play();
        }
      } else {
        if (mounted) {
          setState(() {
            _playerErrorMessage = 'Failed to load video: ${_currentClip?.name ?? filePath}';
          });
        }
      }
    } else {
      debugPrint('File does not exist or path is empty: $filePath');
      if (mounted) {
        setState(() {
          _playerErrorMessage = 'Video file not found: $filePath';
        });
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }
  
  void _onFrameChanged(int frame) {
    if (_updatingFromTimeline) return;
    
    _updatingFromPlayer = true;
    // Convert the frame in the clip to the timeline position
    if (_currentClip != null) {
      final clipStartFrame = ClipModel.msToFrames(_currentClip!.startTimeOnTrackMs);
      final timelineFrame = clipStartFrame + frame;
      _navigationViewModel.currentFrame = timelineFrame;
    }
    _updatingFromPlayer = false;
  }
  
  void _onError(String error) {
    debugPrint('Player error: $error');
    if (mounted) {
      setState(() {
        _playerErrorMessage = 'Player error: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Player error: $error')),
      );
    }
  }
  
  void _updatePerformanceMetrics() {
    if (_playerService != null && mounted) {
      setState(() {
        _performanceMetrics = _playerService!.getPerformanceMetrics();
      });
    }
  }

  @override
  void dispose() {
    _metricsTimer?.cancel();
    
    // Remove timeline listeners
    if (_currentFrameListener != null) {
      _navigationViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    }
    
    if (_playPauseListener != null) {
      _navigationViewModel.isPlayingNotifier.removeListener(_playPauseListener!);
    }
    
    // Dispose player
    _playerService?.dispose();
    
    // Dispose texture model
    _textureService.disposeTextureModel(_textureModelId);
    
    super.dispose();
  }

  Widget _buildVideoDisplay(int totalTimelineFrames) {
    if (_playerErrorMessage != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _playerErrorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_currentClip == null) {
      // No clip is currently loaded or active at the playhead
      if (totalTimelineFrames == 0) {
        // The entire timeline is empty (no clips loaded at all)
        return Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'Timeline is empty. Add media to start.',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        );
      } else {
        // Timeline has clips, but none are at the current playhead position
        return Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'No clip at current playhead position.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
    }

    // A clip is supposed to be active (_currentClip is not null), proceed with texture display
    final textureIdNotifier = _textureModel.getTextureId(_displayIndex);
    
    return ValueListenableBuilder<int>(
      valueListenable: textureIdNotifier,
      builder: (context, textureId, child) {
        if (textureId == -1) {
          // Texture is not ready for the current clip (e.g., still loading)
          return Container(
            color: Colors.black,
            child: const Center(
            child: CircularProgressIndicator(),
            ),
          );
        }
        
        // Texture is ready, display the video
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

  Widget _buildPerformanceMetrics() {
    final fps = _performanceMetrics['fps'] ?? 0.0;
    final renderTime = _performanceMetrics['averageRenderTime'] ?? 0.0;
    final bufferHealth = _performanceMetrics['bufferHealth'] ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MetricDisplay(
            label: 'FPS',
            value: fps.toStringAsFixed(1),
            color: fps >= 29 ? Colors.green : Colors.orange,
          ),
          _MetricDisplay(
            label: 'Render Time',
            value: '${(renderTime / 1000).toStringAsFixed(2)}ms',
            color: renderTime < 10000 ? Colors.green : Colors.orange,
          ),
          _MetricDisplay(
            label: 'Buffer',
            value: '${(bufferHealth * 100).toInt()}%',
            color: bufferHealth > 0.5 ? Colors.green : Colors.orange,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _textureModel.isReady(_displayIndex);
    final videoInfo = _playerService?.videoInfo;
    final currentFrameFromPlayerService = _playerService?.currentFrame ?? 0;
    final isPlaying = _playerService?.isPlaying ?? false;
    
    // Watch timeline state
    final timelineFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    final totalTimelineFrames = watchValue((TimelineNavigationViewModel vm) => vm.totalFramesNotifier);
    
    return Column(
      children: [
        // Video display
        Expanded(
          child: Stack(
            children: [
              _buildVideoDisplay(totalTimelineFrames),
              
              // Performance overlay  
              if (_performanceMetrics.isNotEmpty && _currentClip != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildPerformanceMetrics(),
                ),
            ],
          ),
        ),
        
        // Info panel
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Colors.grey[900],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (videoInfo != null && _currentClip != null)
                Text(
                  'Video: ${videoInfo.width}x${videoInfo.height} @ ${videoInfo.fps.toStringAsFixed(1)} fps',
                  style: const TextStyle(color: Colors.white),
                ),
              Text(
                'Timeline: Frame $timelineFrame / $totalTimelineFrames',
                style: const TextStyle(color: Colors.white),
              ),
              if (_currentClip != null)
                Text(
                  'Player Clip: ${_currentClip!.name ?? "Unnamed"} (Frames: $currentFrameFromPlayerService / ${videoInfo?.frameCount ?? 0})',
                  style: const TextStyle(color: Colors.white),
                )
              else if (totalTimelineFrames > 0)
                 const Text(
                  'Player Clip: None at playhead',
                  style: TextStyle(color: Colors.white70),
                )
              else
                const Text(
                  'Player Clip: Timeline empty',
                  style: TextStyle(color: Colors.white70),
                ),
            ],
          ),
        ),
        
        // Control panel
        Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32,
                ),
                tooltip: isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  // Toggle play/pause on timeline which will control the player
                  _navigationViewModel.togglePlayPause();
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Previous Frame',
                onPressed: () {
                  _navigationViewModel.currentFrame = _navigationViewModel.currentFrame - 1;
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: 'Next Frame',
                onPressed: () {
                  _navigationViewModel.currentFrame = _navigationViewModel.currentFrame + 1;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricDisplay extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  
  const _MetricDisplay({
    required this.label,
    required this.value,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
