import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/composite_video_service.dart';

/// CompositePreviewPanel displays the current timeline frame using a VideoPlayer widget driven by PreviewViewModel.
class CompositePreviewPanel extends StatefulWidget {
  const CompositePreviewPanel({super.key});

  @override
  _CompositePreviewPanelState createState() => _CompositePreviewPanelState();
}

class _CompositePreviewPanelState extends State<CompositePreviewPanel> {
  late final PreviewViewModel _previewViewModel;
  late final EditorViewModel _editorViewModel;
  late final CompositeVideoService _compositeVideoService;
  late final TimelineNavigationViewModel _navigationViewModel;

  // Used for direct composite video playback
  VideoPlayerController? _directCompositeController;
  String? _currentCompositePath;
  bool _isGeneratingComposite = false;

  final String _logTag = 'CompositePreviewPanel';

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
    _editorViewModel = di<EditorViewModel>();
    _compositeVideoService = di<CompositeVideoService>();
    _navigationViewModel = di<TimelineNavigationViewModel>();
    
    logger.logInfo('CompositePreviewPanel initialized', _logTag);
    _previewViewModel.addListener(_rebuild);
    _compositeVideoService.isProcessingNotifier.addListener(_rebuild);
    _navigationViewModel.currentFrameNotifier.addListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.addListener(_handlePlaybackStateChange);
    _previewViewModel.visibleClipsNotifier.addListener(_handleVisibleClipsChange);
  }

  @override
  void dispose() {
    logger.logInfo('CompositePreviewPanel disposing', _logTag);
    _previewViewModel.removeListener(_rebuild);
    _compositeVideoService.isProcessingNotifier.removeListener(_rebuild);
    _navigationViewModel.currentFrameNotifier.removeListener(_handleTimelinePositionChange);
    _navigationViewModel.isPlayingNotifier.removeListener(_handlePlaybackStateChange);
    _previewViewModel.visibleClipsNotifier.removeListener(_handleVisibleClipsChange);
    _disposeDirectController();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }
  
  void _handleTimelinePositionChange() {
    final currentClips = _previewViewModel.visibleClipsNotifier.value
        .where((clip) => clip.type == ClipType.video)
        .toList();
        
    // Check if we have multiple video clips and need to update the composite
    if (currentClips.length >= 2) {
      _updateCompositeVideo();
    } else if (_directCompositeController != null) {
      // If we no longer have multiple clips, dispose the direct controller
      // The PreviewViewModel will handle single clip playback
      _disposeDirectController();
      setState(() {
        _currentCompositePath = null;
      });
    }
  }
  
  void _handleVisibleClipsChange() {
    _updateCompositeVideo();
  }
  
  void _handlePlaybackStateChange() {
    if (_directCompositeController != null) {
      final isPlaying = _navigationViewModel.isPlayingNotifier.value;
      logger.logInfo('Timeline playback changed to: ${isPlaying ? "playing" : "paused"}', _logTag);
      _compositeVideoService.syncPlaybackState(isPlaying, _directCompositeController);
    }
  }
  
  Future<void> _updateCompositeVideo() async {
    // Skip if we're already generating a composite
    if (_isGeneratingComposite) return;
    
    final activeClips = _previewViewModel.visibleClipsNotifier.value
        .where((clip) => clip.type == ClipType.video)
        .toList();
    
    // If there are fewer than 2 active video clips, let PreviewViewModel handle it
    if (activeClips.length < 2) {
      _disposeDirectController();
      setState(() {
        _currentCompositePath = null;
      });
      return;
    }
    
    // Otherwise, generate a composite video
    _isGeneratingComposite = true;
    setState(() {});
    
    try {
      final currentMs = ClipModel.framesToMs(_navigationViewModel.currentFrameNotifier.value);
      final containerSize = _previewViewModel.containerSize;
      
      logger.logInfo('Generating composite video for ${activeClips.length} clips at ${currentMs}ms', _logTag);
      
      // Call the unified method in CompositeVideoService
      final success = await _compositeVideoService.createCompositeVideo(
        clips: activeClips,
        currentTimeMs: currentMs,
        containerSize: containerSize,
      );

      if (!success) {
        logger.logError('CompositeVideoService failed to create composite video', _logTag);
        _isGeneratingComposite = false;
        setState(() {});
        return;
      }

      // Retrieve the path generated by the service
      final compositePath = _compositeVideoService.getCompositeFilePath();

      if (compositePath == null) {
        logger.logError('CompositeVideoService succeeded but returned a null path', _logTag);
        _isGeneratingComposite = false;
        setState(() {});
        return;
      }

      // If the same composite file is already loaded, don't reload
      if (_currentCompositePath == compositePath && _directCompositeController != null) {
        _isGeneratingComposite = false;
        setState(() {});
        return;
      }

      // Otherwise, create a new controller with the composite path
      await _disposeDirectController();
      _directCompositeController = VideoPlayerController.file(File(compositePath));
      _currentCompositePath = compositePath;

      await _directCompositeController!.initialize();
      
      // Sync with timeline play state
      if (_navigationViewModel.isPlayingNotifier.value) {
        await _directCompositeController!.play();
      } else {
        await _directCompositeController!.pause();
      }
      
      logger.logInfo('Successfully initialized composite video player with: $compositePath', _logTag);
    } catch (e, stack) {
      logger.logError('Error creating direct composite video player: $e', _logTag, stack);
    } finally {
      _isGeneratingComposite = false;
      if (mounted) setState(() {});
    }
  }
  
  Future<void> _disposeDirectController() async {
    if (_directCompositeController != null) {
      final controller = _directCompositeController;
      _directCompositeController = null;
      await controller!.dispose();
      logger.logInfo('Disposed direct composite controller', _logTag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewVm = _previewViewModel;
    final editorVm = _editorViewModel;
    final compositeService = _compositeVideoService;
    final isProcessing = compositeService.isProcessingNotifier.value || _isGeneratingComposite;
    
    // Determine which controller to use
    final VideoPlayerController? activeController = 
        (_directCompositeController != null) ? _directCompositeController : previewVm.controller;
    
    final isControllerInitialized = activeController?.value.isInitialized ?? false;
    final aspectRatio = previewVm.aspectRatioNotifier.value;

    logger.logVerbose(
      'CompositePreviewPanel building... Using direct controller: ${_directCompositeController != null}, '
      'Initialized: $isControllerInitialized, Processing: $isProcessing',
      _logTag,
    );

    return Container(
      color: Colors.grey[160],
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                color: Colors.black,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && previewVm.containerSize != constraints.biggest) {
                        previewVm.updateContainerSize(constraints.biggest);
                        logger.logVerbose('Updated container size: ${constraints.biggest}', _logTag);
                      }
                    });
                    
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Builder(builder: (context) {
                          final isInit = activeController?.value.isInitialized ?? false;
                          final hasError = activeController?.value.hasError ?? false;
                          
                          if (activeController != null && isInit) {
                            // Log size information to help debug layout issues
                            logger.logInfo(
                              'Video size: ${activeController.value.size}, AspectRatio: ${activeController.value.aspectRatio}',
                              _logTag,
                            );
                            
                            // Use a simpler approach without FittedBox to avoid stretching
                            return AspectRatio(
                              aspectRatio: activeController.value.aspectRatio,
                              child: VideoPlayer(activeController),
                            );
                          } else if (hasError) {
                            return Center(
                              child: Text(
                                'Error loading video: ${activeController?.value.errorDescription}',
                                style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                            );
                          } else if (isProcessing) {
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                const ProgressRing(),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'Compositing videos...',
                                    style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            );
                          } else if (activeController != null && !isInit) {
                            return const Center(child: ProgressRing());
                          } else {
                            return Center(
                              child: Text(
                                'No video at current playback position',
                                style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                        }),

                        // Add overlay to show number of active clips
                        Positioned(
                          top: 10,
                          right: 10,
                          child: ValueListenableBuilder<List<ClipModel>>(
                            valueListenable: previewVm.visibleClipsNotifier,
                            builder: (context, visibleClips, _) {
                              if (visibleClips.isEmpty) return const SizedBox.shrink();
                              
                              final videoClips = visibleClips.where((c) => c.type == ClipType.video).toList();
                              final isComposite = videoClips.length >= 2;
                              
                              return Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${videoClips.length} video clip${videoClips.length != 1 ? 's' : ''} active'
                                  '${isComposite ? ' (composite view)' : ''}',
                                  style: FluentTheme.of(context).typography.caption?.copyWith(color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}