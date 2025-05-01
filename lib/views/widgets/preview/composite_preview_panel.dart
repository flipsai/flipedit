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

  // Video playback control
  VideoPlayerController? _videoController;
  bool _isInitializingController = false;

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
    _previewViewModel.isGeneratingFrameNotifier.addListener(_rebuild);
    _previewViewModel.aspectRatioNotifier.addListener(_rebuild);
    
    _navigationViewModel.currentFrameNotifier.addListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.addListener(_handlePlaybackStateChange);
    _timelineViewModel.clipsNotifier.addListener(_handleClipsChanged);
    
    // Initialize content
    _initializeController();
  }

  @override
  void dispose() {
    logger.logInfo('CompositePreviewPanel disposing', _logTag);
    _previewViewModel.compositeFramePathNotifier.removeListener(_handlePreviewContentChanged);
    _previewViewModel.isGeneratingFrameNotifier.removeListener(_rebuild);
    _previewViewModel.aspectRatioNotifier.removeListener(_rebuild);
    
    _navigationViewModel.currentFrameNotifier.removeListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.removeListener(_handlePlaybackStateChange);
    _timelineViewModel.clipsNotifier.removeListener(_handleClipsChanged);
    
    _disposeVideoController();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  
  // Called when a new preview content (video) is available
  Future<void> _handlePreviewContentChanged() async {
    final newVideoPath = _previewViewModel.compositeFramePathNotifier.value;
    
    if (newVideoPath != null && newVideoPath.isNotEmpty && 
        (_videoController?.dataSource != newVideoPath)) {
      // We have a new video path that's different from the current one
      await _initializeController();
    } else if (newVideoPath == null && _videoController != null) {
      // No video available, dispose controller
      _disposeVideoController();
    }
  }
  
  void _handleTimelinePositionChange() {
    final isPlaying = _navigationViewModel.isPlaying;
    if (!isPlaying) {
      // When scrubbing (not playing), ensure we update our position in the video
      final frame = _navigationViewModel.currentFrame;
      logger.logVerbose('Timeline position changed to frame $frame while not playing', _logTag);
      
      // The PreviewViewModel handles generating a new video at the current position
      // We just need to ensure the controller is initialized with the new video when it's ready
    }
  }
  
  void _handlePlaybackStateChange() {
    final isPlaying = _navigationViewModel.isPlaying;
    logger.logInfo('Playback state changed: $isPlaying', _logTag);
    
    if (_videoController != null && _videoController!.value.isInitialized) {
      if (isPlaying) {
        _videoController!.play();
      } else {
        _videoController!.pause();
      }
    }
  }
  
  void _handleClipsChanged() {
    // When clips change, we may need to update our preview
    // PreviewViewModel will handle regenerating the preview content
    logger.logVerbose('Clips changed, preview will update as needed', _logTag);
  }
  
  Future<void> _initializeController() async {
    final videoPath = _previewViewModel.compositeFramePathNotifier.value;
    
    if (videoPath == null || videoPath.isEmpty) {
      _disposeVideoController();
      return;
    }
    
    if (_isInitializingController) {
      logger.logWarning('Controller initialization already in progress, skipping', _logTag);
      return;
    }
    
    _isInitializingController = true;
    setState(() {}); // Update UI to show loading
    
    try {
      // Dispose existing controller
      _disposeVideoController();
      
      // Initialize new controller
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      
      if (mounted) {
        setState(() {
          _videoController = controller;
          _isInitializingController = false;
          
          // Start playing if we're supposed to be playing
          if (_navigationViewModel.isPlaying) {
            controller.play();
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
  
  void _disposeVideoController() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  @override
  Widget build(BuildContext context) {
    final previewVm = _previewViewModel;
    final isGenerating = previewVm.isGeneratingFrameNotifier.value || _isInitializingController;
    final aspectRatio = previewVm.aspectRatioNotifier.value;
    
    logger.logVerbose(
      'CompositePreviewPanel building... Generating: $isGenerating',
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
                    else if (isGenerating)
                      _buildProcessingIndicator(context)
                    else
                      _buildPlaceholderWidget(context, 'No preview available'),
                    
                    // Show loading overlay during content generation
                    if (isGenerating) 
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