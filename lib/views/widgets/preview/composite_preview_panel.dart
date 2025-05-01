import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

/// CompositePreviewPanel displays the current timeline using VideoPlayer for both
/// single-frame preview and during continuous playback.
class CompositePreviewPanel extends StatefulWidget {
  const CompositePreviewPanel({super.key});

  @override
  _CompositePreviewPanelState createState() => _CompositePreviewPanelState();
}

class _CompositePreviewPanelState extends State<CompositePreviewPanel> {
  late final PreviewViewModel _previewViewModel;
  late final EditorViewModel _editorViewModel;
  late final TimelineNavigationViewModel _navigationViewModel;
  late final TimelineViewModel _timelineViewModel;

  // Primary video controller for current segment
  VideoPlayerController? _videoController;
  
  // Preload controller for next segment
  VideoPlayerController? _nextVideoController;
  
  // Track if we're currently initializing controllers
  bool _isInitializingController = false;
  
  // Keep track of current segment index
  int _currentSegmentIndex = 0;
  
  // Keep track of available segments
  List<String> _videoSegments = [];
  
  // Seamless playback state
  bool _isTransitioning = false;

  final String _logTag = 'CompositePreviewPanel';

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
    _editorViewModel = di<EditorViewModel>();
    _navigationViewModel = di<TimelineNavigationViewModel>();
    _timelineViewModel = di<TimelineViewModel>();

    logger.logInfo('CompositePreviewPanel initialized', _logTag);
    
    // Add listeners
    _previewViewModel.compositeFramePathNotifier.addListener(_handlePreviewContentChanged);
    _previewViewModel.videoSegmentsNotifier.addListener(_handleVideoSegmentsChanged);
    _previewViewModel.isGeneratingFrameNotifier.addListener(_rebuildIfNotTransitioning);
    _previewViewModel.aspectRatioNotifier.addListener(_rebuild);
    
    _navigationViewModel.currentFrameNotifier.addListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.addListener(_handlePlaybackStateChange);
    _timelineViewModel.clipsNotifier.addListener(_handleClipsChanged);
    
    // Initialize content
    _initializeVideoSegments();
  }

  @override
  void dispose() {
    logger.logInfo('CompositePreviewPanel disposing', _logTag);
    _previewViewModel.compositeFramePathNotifier.removeListener(_handlePreviewContentChanged);
    _previewViewModel.videoSegmentsNotifier.removeListener(_handleVideoSegmentsChanged);
    _previewViewModel.isGeneratingFrameNotifier.removeListener(_rebuildIfNotTransitioning);
    _previewViewModel.aspectRatioNotifier.removeListener(_rebuild);
    
    _navigationViewModel.currentFrameNotifier.removeListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.removeListener(_handlePlaybackStateChange);
    _timelineViewModel.clipsNotifier.removeListener(_handleClipsChanged);
    
    // Remove video completion listener
    _videoController?.removeListener(_monitorVideoProgress);
    
    _disposeVideoControllers();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  
  void _rebuildIfNotTransitioning() {
    if (mounted && !_isTransitioning) {
      setState(() {});
    }
  }
  
  // Called when a new preview content (segments) is available
  Future<void> _handlePreviewContentChanged() async {
    final newVideoPath = _previewViewModel.compositeFramePathNotifier.value;
    
    if (newVideoPath != null && newVideoPath.isNotEmpty) {
      // For now, treat single file as a single segment
      _videoSegments = [newVideoPath];
      await _initializeVideoSegments();
    } else {
      // No video available, dispose controllers
      _disposeVideoControllers();
      _videoSegments = [];
    }
  }
  
  // Called when new video segments are available
  Future<void> _handleVideoSegmentsChanged() async {
    final segments = _previewViewModel.videoSegmentsNotifier.value;
    
    if (segments.isNotEmpty) {
      logger.logInfo('Received ${segments.length} video segments for playback', _logTag);
      _videoSegments = segments;
      await _initializeVideoSegments();
    } else {
      // No segments available, check if we have a single frame
      final singleFrame = _previewViewModel.compositeFramePathNotifier.value;
      if (singleFrame != null && singleFrame.isNotEmpty) {
        _videoSegments = [singleFrame];
        await _initializeVideoSegments();
      } else {
        // No video available, dispose controllers
        _disposeVideoControllers();
        _videoSegments = [];
      }
    }
  }
  
  void _handleTimelinePositionChange() {
    final isPlaying = _navigationViewModel.isPlaying;
    if (!isPlaying) {
      // When scrubbing (not playing), update our position in the video
      final frame = _navigationViewModel.currentFrame;
      logger.logVerbose('Timeline position changed to frame $frame while not playing', _logTag);
      
      // Find the appropriate segment for this frame and initialize it
      _seekToFramePosition(frame);
    }
  }
  
  void _seekToFramePosition(int frame) {
    // This will be implemented by seeking to the right position in the right segment
    // for now just reinitialize
    _initializeVideoSegments();
  }
  
  void _handlePlaybackStateChange() {
    final isPlaying = _navigationViewModel.isPlaying;
    logger.logInfo('Playback state changed: $isPlaying', _logTag);
    
    if (isPlaying) {
      // When starting playback, hide any loading indicators
      _isTransitioning = true; // Use the transitioning state to hide loading indicators
      
      // If the controller is ready, play it
      if (_videoController != null && _videoController!.value.isInitialized) {
        // Ensure we're at the right position when starting playback
        final frame = _navigationViewModel.currentFrame;
        final frameTimeMs = frame * (1000 / 30); // Assuming 30fps
        
        if (_videoController!.value.position.inMilliseconds != frameTimeMs) {
          // First seek to the right position, then play
          final seekMs = frameTimeMs.clamp(0, _videoController!.value.duration.inMilliseconds);
          _videoController!.seekTo(Duration(milliseconds: seekMs.toInt())).then((_) {
            if (_navigationViewModel.isPlaying) { // Check if still playing after seek completes
              _videoController!.play();
            }
          });
        } else {
          // Already at correct position, just play
          _videoController!.play();
        }
      } else {
        // If not ready, initialize it quickly without showing indicators
        _initializeVideoSegments();
      }
      
      // Reset transition state after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _isTransitioning = false;
          });
        }
      });
    } else {
      // When stopping playback, restore normal behavior
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController!.pause();
      }
      
      // Reset transition state immediately
      if (_isTransitioning) {
        setState(() {
          _isTransitioning = false;
        });
      }
    }
  }
  
  void _handleClipsChanged() {
    // When clips change, we may need to update our preview
    logger.logVerbose('Clips changed, preview will update as needed', _logTag);
  }
  
  Future<void> _initializeVideoSegments() async {
    if (_videoSegments.isEmpty) {
      _disposeVideoControllers();
      return;
    }
    
    if (_isInitializingController) {
      logger.logWarning('Controller initialization already in progress, skipping', _logTag);
      return;
    }
    
    _isInitializingController = true;
    final bool wasPlaying = _navigationViewModel.isPlaying;
    
    if (!_isTransitioning) {
      setState(() {}); // Update UI to show loading
    }
    
    try {
      // Dispose existing controllers if needed
      _disposeVideoControllers();
      
      // Set current segment
      _currentSegmentIndex = 0;
      
      // Initialize current controller
      await _initializeCurrentSegment();
      
      // Set the initial position based on current frame if needed
      if (_videoController != null && _videoController!.value.isInitialized) {
        final currentFrame = _navigationViewModel.currentFrame;
        final frameTimeMs = currentFrame * (1000 / 30); // Assuming 30fps
        
        // Seek to the appropriate position - use more precise calculation
        final seekMs = frameTimeMs.clamp(0, _videoController!.value.duration.inMilliseconds);
        // Round to the nearest frame boundary for more accurate seeking
        final frameRate = 30.0; // fps
        final frameDuration = 1000.0 / frameRate; // ms per frame
        final frameNumber = (seekMs / frameDuration).round();
        final adjustedSeekMs = (frameNumber * frameDuration).toInt();
        
        await _videoController!.seekTo(Duration(milliseconds: adjustedSeekMs));
        logger.logVerbose('Seeked to frame-aligned position: ${adjustedSeekMs}ms', _logTag);
      }
      
      // Preload next segment if available - do this in parallel without awaiting
      if (_videoSegments.length > 1) {
        _preloadNextSegment(); // Don't await, let it load in background
      }
      
      if (mounted) {
        setState(() {
          _isInitializingController = false;
          
          // Start playing if we're supposed to be playing
          if (wasPlaying && _navigationViewModel.isPlaying && _videoController != null) {
            _videoController!.play();
          }
        });
      }
    } catch (e, stackTrace) {
      logger.logError('Error initializing video controller: $e', _logTag, stackTrace);
      _isInitializingController = false;
      if (mounted) {
        setState(() {});
      }
    }
  }
  
  Future<void> _initializeCurrentSegment() async {
    if (_currentSegmentIndex >= _videoSegments.length) {
      logger.logError('Invalid segment index: $_currentSegmentIndex', _logTag);
      return;
    }
    
    final videoPath = _videoSegments[_currentSegmentIndex];
    
    if (!File(videoPath).existsSync()) {
      logger.logError('Segment file does not exist: $videoPath', _logTag);
      return;
    }
    
    // Initialize controller
    final controller = VideoPlayerController.file(File(videoPath));
    await controller.initialize();
    
    // Add listener to monitor playback position for segment switching
    controller.addListener(_monitorVideoProgress);
    
    _videoController = controller;
  }
  
  Future<void> _preloadNextSegment() async {
    final nextIndex = _currentSegmentIndex + 1;
    if (nextIndex >= _videoSegments.length) {
      return; // No next segment
    }
    
    final nextVideoPath = _videoSegments[nextIndex];
    
    try {
      if (!File(nextVideoPath).existsSync()) {
        logger.logError('Next segment file does not exist: $nextVideoPath', _logTag);
        return;
      }
      
      // Initialize next controller
      final controller = VideoPlayerController.file(File(nextVideoPath));
      await controller.initialize();
      
      // Pre-position at the start of the video, ensuring precise frame alignment
      await controller.seekTo(Duration.zero);
      await controller.pause();
      
      // Store but don't play yet
      _nextVideoController = controller;
      
      logger.logVerbose('Preloaded next video segment: $nextVideoPath', _logTag);
    } catch (e) {
      logger.logError('Error preloading next segment: $e', _logTag);
    }
  }
  
  void _monitorVideoProgress() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }
    
    // Get current position and duration
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    
    // Start transition earlier (85% through instead of 75%) for more time to prepare 
    // the transition, and use frame-aligned transition points
    const transitionThreshold = 0.85; // Transition at 85% through segment
    
    if (position.inMilliseconds > duration.inMilliseconds * transitionThreshold && 
        _nextVideoController != null && 
        _nextVideoController!.value.isInitialized &&
        !_isTransitioning) {
      
      // Calculate a frame-aligned transition point
      final frameRate = 30.0; // fps
      final frameDuration = 1000.0 / frameRate; // ms per frame
      final frameNumber = (position.inMilliseconds / frameDuration).round();
      final adjustedPositionMs = (frameNumber * frameDuration).toInt();
      
      logger.logVerbose(
        'Transitioning to next segment at frame-aligned position: ${adjustedPositionMs}ms',
        _logTag,
      );
      
      // Switch to next segment
      _transitionToNextSegment();
    }
    
    // If at the very end and no next segment is available, handle playback completion
    if (position.inMilliseconds >= duration.inMilliseconds * 0.98 &&
        (_nextVideoController == null || !_nextVideoController!.value.isInitialized) &&
        !_isTransitioning) {
      
      // Stop looping behavior by pausing at the end
      _videoController!.pause();
      
      // If navigation is still in playing state, update it
      if (_navigationViewModel.isPlaying) {
        // Trigger stop in the navigation ViewModel to synchronize state
        _navigationViewModel.stopPlayback();
        logger.logInfo('Playback completed and stopped at end of video', _logTag);
      }
    }
  }
  
  Future<void> _transitionToNextSegment() async {
    if (_isTransitioning || _nextVideoController == null) {
      return;
    }
    
    _isTransitioning = true;
    logger.logInfo('Transitioning to next video segment', _logTag);
    
    try {
      // Ensure the next video is positioned at the beginning
      // Start at the exact first frame, not a fractional position
      await _nextVideoController!.seekTo(Duration.zero);
      
      // Start playing the next video immediately
      await _nextVideoController!.play();
      
      // Update UI with crossfade
      if (mounted) {
        setState(() {
          // Swap controllers
          final oldController = _videoController;
          _videoController = _nextVideoController;
          _nextVideoController = null;
          
          // Update segment index
          _currentSegmentIndex++;
          
          // Clean up and prepare next segment
          Future.delayed(const Duration(milliseconds: 50), () {
            // Dispose old controller
            oldController?.dispose();
            
            // Preload next segment right away
            if (_currentSegmentIndex < _videoSegments.length - 1) {
              _preloadNextSegment();
            }
            
            // Reset transition state after everything is done
            _isTransitioning = false;
          });
        });
      }
    } catch (e, stack) {
      // Error handling in case of transition failure
      logger.logError('Error during segment transition: $e', _logTag, stack);
      _isTransitioning = false;
      
      // Try to recover by continuing with current controller
      if (_videoController?.value.isInitialized == true) {
        _videoController!.play();
      }
    }
  }
  
  void _disposeVideoControllers() {
    // Remove listener
    _videoController?.removeListener(_monitorVideoProgress);
    
    // Dispose current controller
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    
    // Dispose next controller
    _nextVideoController?.pause();
    _nextVideoController?.dispose();
    _nextVideoController = null;
  }

  @override
  Widget build(BuildContext context) {
    final previewVm = _previewViewModel;
    final isGenerating = previewVm.isGeneratingFrameNotifier.value || 
                         (_isInitializingController && !_isTransitioning);
    final aspectRatio = previewVm.aspectRatioNotifier.value;
    final isPlaying = _navigationViewModel.isPlaying;
    
    // When playing, never show generating indicators
    final showGeneratingIndicator = isGenerating && !isPlaying;
    
    logger.logVerbose(
      'CompositePreviewPanel building... Generating: $isGenerating, Transitioning: $_isTransitioning, Playing: $isPlaying',
      _logTag,
    );

    return Container(
      color: Colors.grey[160],
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            color: Colors.black,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Update container size in VM if it has changed
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (previewVm.containerSizeNotifier.value?.width != constraints.maxWidth ||
                      previewVm.containerSizeNotifier.value?.height != constraints.maxHeight) {
                    logger.logVerbose('Updating container size in VM: ${constraints.maxWidth}x${constraints.maxHeight}', _logTag);
                    previewVm.containerSizeNotifier.value = Size(constraints.maxWidth, constraints.maxHeight);
                    
                    // Update preview content when size changes
                    previewVm.updatePreviewContent();
                  }
                });

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Show video player when available
                    if (_videoController?.value.isInitialized == true)
                      VideoPlayer(_videoController!)
                    else if (isGenerating && !isPlaying)
                      _buildProcessingIndicator(context)
                    else
                      _buildPlaceholderWidget(context, 'No preview available'),
                    
                    // Show loading overlay during content generation, but not during transitions or playback
                    if (showGeneratingIndicator) 
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: ProgressRing(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Generating preview...',
                                style: FluentTheme.of(context).typography.caption?.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// --- Helper Widgets ---

Widget _buildProcessingIndicator(BuildContext context) {
  return const Center(child: ProgressRing());
}

Widget _buildPlaceholderWidget(BuildContext context, String message) {
  return Center(
    child: Text(
      message,
      style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
      textAlign: TextAlign.center,
    ),
  );
}