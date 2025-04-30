import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/services/composite_video_service.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

/// CompositePreviewPanel displays the current timeline frame using a single composited video
class CompositePreviewPanel extends StatefulWidget {
  const CompositePreviewPanel({super.key});

  @override
  _CompositePreviewPanelState createState() => _CompositePreviewPanelState();
}

class _CompositePreviewPanelState extends State<CompositePreviewPanel> {
  late final PreviewViewModel _previewViewModel;
  late final CompositeVideoService _compositeVideoService;
  late final TimelineNavigationViewModel _navigationViewModel;
  late final EditorViewModel _editorViewModel;
  
  final String _logTag = 'CompositePreviewPanel';
  bool _isGenerating = false;
  
  // Debounce for transforms to avoid excessive updates
  Timer? _transformDebounceTimer;
  bool _isCurrentlyTransforming = false;
  final Map<int, Rect> _lastRects = {};
  final Map<int, Flip> _lastFlips = {};

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
    _compositeVideoService = di<CompositeVideoService>();
    _navigationViewModel = di<TimelineNavigationViewModel>();
    _editorViewModel = di<EditorViewModel>();
    
    logger.logInfo('CompositePreviewPanel initialized', _logTag);
    
    // Set up listeners
    _previewViewModel.visibleClipsNotifier.addListener(_onVisibleClipsChanged);
    _previewViewModel.clipRectsNotifier.addListener(_onRectChanged);
    _previewViewModel.clipFlipsNotifier.addListener(_onFlipChanged);
    _navigationViewModel.currentFrameNotifier.addListener(_updatePlaybackPosition);
    _compositeVideoService.isProcessingNotifier.addListener(_updateProcessingState);
    
    // Force a first update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      logger.logInfo('CompositePreviewPanel post-frame callback - forcing update', _logTag);
      _updateCompositeVideo();
    });
  }

  @override
  void dispose() {
    // Remove listeners
    _previewViewModel.visibleClipsNotifier.removeListener(_onVisibleClipsChanged);
    _previewViewModel.clipRectsNotifier.removeListener(_onRectChanged);
    _previewViewModel.clipFlipsNotifier.removeListener(_onFlipChanged);
    _navigationViewModel.currentFrameNotifier.removeListener(_updatePlaybackPosition);
    _compositeVideoService.isProcessingNotifier.removeListener(_updateProcessingState);
    
    // Cancel any pending debounce timer
    _transformDebounceTimer?.cancel();
    
    super.dispose();
  }
  
  void _updateProcessingState() {
    if (mounted) {
      setState(() {
        _isGenerating = _compositeVideoService.isProcessingNotifier.value;
      });
    }
  }
  
  void _updatePlaybackPosition() {
    // No need to seek - composite video is generated at the exact right frame
    if (!_isCurrentlyTransforming) {
      _updateCompositeVideo();
    }
  }
  
  // New methods to handle change detection
  void _onVisibleClipsChanged() {
    if (!_isCurrentlyTransforming) {
      _updateCompositeVideo();
    }
  }
  
  void _onRectChanged() {
    // Skip if we're in the middle of a transform operation
    if (_isCurrentlyTransforming) {
      return;
    }
    _updateCompositeVideo();
  }
  
  void _onFlipChanged() {
    // Skip if we're in the middle of a transform operation
    if (_isCurrentlyTransforming) {
      return;
    }
    _updateCompositeVideo();
  }
  
  void _startTransform(int clipId) {
    logger.logInfo('Starting transform for clip $clipId', _logTag);
    _isCurrentlyTransforming = true;
    
    // Store current transforms
    final positions = _previewViewModel.clipRectsNotifier.value;
    final flips = _previewViewModel.clipFlipsNotifier.value;
    
    if (positions.containsKey(clipId)) {
      _lastRects[clipId] = positions[clipId]!;
    }
    if (flips.containsKey(clipId)) {
      _lastFlips[clipId] = flips[clipId]!;
    }
  }
  
  void _endTransform(int clipId) {
    logger.logInfo('Ending transform for clip $clipId', _logTag);
    _isCurrentlyTransforming = false;
    
    // Check if there was an actual change
    final positions = _previewViewModel.clipRectsNotifier.value;
    final flips = _previewViewModel.clipFlipsNotifier.value;
    
    bool changed = false;
    
    if (positions.containsKey(clipId) && _lastRects.containsKey(clipId)) {
      changed = positions[clipId] != _lastRects[clipId];
    }
    
    if (!changed && flips.containsKey(clipId) && _lastFlips.containsKey(clipId)) {
      changed = flips[clipId] != _lastFlips[clipId];
    }
    
    if (changed) {
      // Debounce the update to avoid excessive FFmpeg calls
      _transformDebounceTimer?.cancel();
      _transformDebounceTimer = Timer(const Duration(milliseconds: 150), () {
        _updateCompositeVideo();
      });
    }
    
    // Clear stored values
    _lastRects.remove(clipId);
    _lastFlips.remove(clipId);
  }
  
  Future<void> _updateCompositeVideo() async {
    if (_isGenerating || _isCurrentlyTransforming) return;
    
    final clips = _previewViewModel.visibleClipsNotifier.value;
    final positions = _previewViewModel.clipRectsNotifier.value;
    final flips = _previewViewModel.clipFlipsNotifier.value;
    final containerSize = _previewViewModel.containerSize;
    
    // Only generate if we have video clips to display
    if (clips.isNotEmpty) {
      final videoClips = clips.where((clip) => clip.type == ClipType.video).toList();
      if (videoClips.isEmpty) return;
      
      logger.logInfo('Generating composite video with ${videoClips.length} clips', _logTag);
      
      // Get current time in milliseconds
      final currentFrame = _navigationViewModel.currentFrameNotifier.value;
      final currentTimeMs = ClipModel.framesToMs(currentFrame);
      
      // Initialize positions and flips maps if empty - ensure every clip has a value
      final Map<int, Rect> positionsWithDefaults = Map.from(positions);
      final Map<int, Flip> flipsWithDefaults = Map.from(flips);
      
      // Ensure every clip has a position and flip value
      for (final clip in videoClips) {
        if (clip.databaseId != null) {
          final clipId = clip.databaseId!;
          
          // Add default position if missing
          if (!positionsWithDefaults.containsKey(clipId)) {
            // Create default centered rect at 1/4 size of container
            final defaultWidth = containerSize != null ? containerSize.width / 2 : 320.0;
            final defaultHeight = containerSize != null ? containerSize.height / 2 : 240.0;
            final defaultX = containerSize != null ? (containerSize.width - defaultWidth) / 2 : 0.0;
            final defaultY = containerSize != null ? (containerSize.height - defaultHeight) / 2 : 0.0;
            
            positionsWithDefaults[clipId] = Rect.fromLTWH(defaultX, defaultY, defaultWidth, defaultHeight);
            logger.logInfo('Added default position for clip $clipId: ${positionsWithDefaults[clipId]}', _logTag);
          }
          
          // Add default flip if missing
          if (!flipsWithDefaults.containsKey(clipId)) {
            flipsWithDefaults[clipId] = Flip.none;
            logger.logInfo('Added default flip for clip $clipId: ${flipsWithDefaults[clipId]}', _logTag);
          }
        }
      }
      
      // Log the maps for debugging
      logger.logInfo('Positions map keys: ${positionsWithDefaults.keys.join(', ')}', _logTag);
      logger.logInfo('Flips map keys: ${flipsWithDefaults.keys.join(', ')}', _logTag);
      
      // Generate the composite video
      await _compositeVideoService.createCompositeVideo(
        clips: videoClips,
        positions: positionsWithDefaults,
        flips: flipsWithDefaults,
        currentTimeMs: currentTimeMs,
        containerSize: containerSize,
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final visibleClips = _previewViewModel.visibleClipsNotifier.value;
    final clipCount = visibleClips.length;
    final clipIds = visibleClips.map((c) => c.databaseId).toList();
    final clipRects = _previewViewModel.clipRectsNotifier.value;
    final clipFlips = _previewViewModel.clipFlipsNotifier.value;
    final selectedClipId = _previewViewModel.selectedClipIdNotifier.value;
    final aspectRatio = _previewViewModel.aspectRatioNotifier.value;
    final aspectRatioLocked = _editorViewModel.aspectRatioLockedNotifier.value;
    
    logger.logInfo('CompositePreviewPanel building with $clipCount clips: $clipIds', _logTag);
    
    return Container(
      color: Colors.grey[160],
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _previewViewModel.containerSize != constraints.biggest) {
                          _previewViewModel.updateContainerSize(constraints.biggest);
                        }
                      });
                      
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _previewViewModel.selectClip(null);
                        },
                        child: Stack(
                          children: [
                            // Background and base video player
                            Container(color: Colors.black),
                            
                            // MDK Player view - Render based on player readiness and transform state
                            ValueListenableBuilder<bool>(
                              valueListenable: _compositeVideoService.isPlayerReadyNotifier,
                              builder: (context, isPlayerReady, _) {
                                // Only show texture widget if player is ready AND not currently transforming
                                if (isPlayerReady && !_isCurrentlyTransforming) {
                                  return Positioned.fill(
                                    child: ValueListenableBuilder<int>(
                                      valueListenable: _compositeVideoService.textureIdNotifier,
                                      builder: (context, textureId, _) {
                                        logger.logDebug('Player ready: $isPlayerReady, Texture ID: $textureId', _logTag);

                                        if (textureId <= 0) {
                                          // Player is ready, but texture ID is invalid
                                          return Center(
                                            child: Text(
                                              'Texture not available (ID: $textureId)',
                                              style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                            ),
                                          );
                                        }

                                        // Player ready and texture ID is valid
                                        return flutter.Texture(textureId: textureId);
                                      },
                                    ),
                                  );
                                } else {
                                  // Player not ready or is transforming, show nothing (black background suffices)
                                  logger.logDebug('Player not ready ($isPlayerReady) or transforming ($_isCurrentlyTransforming), hiding texture.', _logTag);
                                  return const SizedBox.shrink();
                                }
                              },
                            ),

                            // Transformable boxes for clips
                            ...visibleClips.map((clip) {
                              if (clip.databaseId == null) return const SizedBox();
                              
                              final clipId = clip.databaseId!;
                              final isSelected = selectedClipId == clipId;
                              final currentRect = clipRects[clipId] ?? Rect.zero;
                              final currentFlip = clipFlips[clipId] ?? Flip.none;
                              
                              return TransformableBox(
                                key: ValueKey('preview_clip_$clipId'),
                                rect: currentRect,
                                flip: currentFlip,
                                resizeModeResolver: () => 
                                  aspectRatioLocked 
                                    ? ResizeMode.symmetricScale 
                                    : ResizeMode.freeform,
                                onChanged: (result, details) {
                                  _previewViewModel.handleRectChanged(clipId, result.rect);
                                },
                                onDragStart: (result) {
                                  _startTransform(clipId);
                                  _previewViewModel.handleTransformStart(clipId);
                                },
                                onResizeStart: (handle, event) {
                                  _startTransform(clipId);
                                  _previewViewModel.handleTransformStart(clipId);
                                },
                                onDragEnd: (result) {
                                  _previewViewModel.handleTransformEnd(clipId);
                                  _endTransform(clipId);
                                },
                                onResizeEnd: (handle, event) {
                                  _previewViewModel.handleTransformEnd(clipId);
                                  _endTransform(clipId);
                                },
                                onTap: () {
                                  _previewViewModel.selectClip(clipId);
                                },
                                enabledHandles: isSelected ? const {...HandlePosition.values} : const {},
                                visibleHandles: isSelected ? const {...HandlePosition.values} : const {},
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 36,
                                  maxWidth: 1920,
                                  maxHeight: 1080,
                                ),
                                // Just render an outline box for handles
                                contentBuilder: (context, rect, flip) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isSelected ? Colors.blue : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  );
                                },
                              );
                            }).toList(),
                            
                            // Show a progress indicator during transform
                            if (_isCurrentlyTransforming)
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Transforming...',
                                      style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                    ),
                                    const SizedBox(height: 10),
                                    const ProgressRing(),
                                  ],
                                ),
                              ),
                            
                            // Loading indicator when generating
                            if (_isGenerating && !_isCurrentlyTransforming)
                              const Center(
                                child: ProgressRing(),
                              ),
                            
                            // Empty state when no clips
                            if (visibleClips.isEmpty)
                              Center(
                                child: Text(
                                  'No video at current playback position',
                                  style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              
                            // Debug indicator for texture ID  
                            ValueListenableBuilder<int>(
                              valueListenable: _compositeVideoService.textureIdNotifier,
                              builder: (context, textureId, _) {
                                if (textureId <= 0) return const SizedBox();
                                
                                return Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    color: Colors.black.withOpacity(0.5),
                                    child: Text(
                                      'Texture ID: $textureId',
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 