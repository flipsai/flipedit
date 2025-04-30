import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

/// CompositePreviewPanel displays the current timeline frame using a single composited video texture
/// and overlays interactive TransformableBox widgets for manipulation.
class CompositePreviewPanel extends StatefulWidget {
  const CompositePreviewPanel({super.key});

  @override
  _CompositePreviewPanelState createState() => _CompositePreviewPanelState();
}

class _CompositePreviewPanelState extends State<CompositePreviewPanel> {
  late final PreviewViewModel _previewViewModel;
  late final TimelineNavigationViewModel _navigationViewModel; // Keep for frame info if needed
  late final EditorViewModel _editorViewModel; // Keep for aspect ratio lock

  final String _logTag = 'CompositePreviewPanel';

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
    _navigationViewModel = di<TimelineNavigationViewModel>();
    _editorViewModel = di<EditorViewModel>();

    logger.logInfo('CompositePreviewPanel initialized', _logTag);
  }

  @override
  void dispose() {
    logger.logInfo('CompositePreviewPanel disposing', _logTag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _previewViewModel.aspectRatioNotifier.value;

    logger.logVerbose('CompositePreviewPanel building...', _logTag);

    return Container(
      color: Colors.grey[160], // Background for the panel area
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Container(
                  color: Colors.black, // Background for the aspect ratio container
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Update container size in ViewModel after layout
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _previewViewModel.containerSize != constraints.biggest) {
                          _previewViewModel.updateContainerSize(constraints.biggest);
                          logger.logVerbose('Updated container size: ${constraints.biggest}', _logTag);
                        }
                      });

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque, // Ensure taps outside clips are caught
                        onTap: () {
                          logger.logVerbose('Background tapped, deselecting clip.', _logTag);
                          _previewViewModel.selectClip(null); // Deselect clip on background tap
                        },
                        child: Stack(
                          fit: StackFit.expand, // Ensure Stack fills the container
                          children: [
                            // 1. MDK Player Texture (Listens to textureIdNotifier from ViewModel)
                            ValueListenableBuilder<int>(
                              valueListenable: _previewViewModel.textureIdNotifier, // Listen to ViewModel
                              builder: (context, textureId, _) {
                                logger.logVerbose('Texture ID builder: $textureId', _logTag);
                                if (textureId > 0) {
                                  // Use Positioned.fill to ensure texture covers the area
                                  return Positioned.fill(
                                    child: flutter.Texture(textureId: textureId),
                                  );
                                } else {
                                  // Show nothing if texture is invalid (black background suffices)
                                  return const SizedBox.shrink();
                                }
                              },
                            ),

                            // 2. Transformable Box Overlays (Listens to multiple VM notifiers)
                            ValueListenableBuilder<List<ClipModel>>(
                              valueListenable: _previewViewModel.visibleClipsNotifier,
                              builder: (context, visibleClipsForOverlay, _) {
                                // Also listen to rects, flips, and selection to rebuild overlays correctly
                                return ValueListenableBuilder<Map<int, Rect>>(
                                  valueListenable: _previewViewModel.clipRectsNotifier,
                                  builder: (context, clipRects, _) {
                                    return ValueListenableBuilder<Map<int, Flip>>(
                                      valueListenable: _previewViewModel.clipFlipsNotifier,
                                      builder: (context, clipFlips, _) {
                                        return ValueListenableBuilder<int?>(
                                          valueListenable: _previewViewModel.selectedClipIdNotifier,
                                          builder: (context, selectedClipId, _) {
                                            // Listen to aspect ratio lock state as well
                                            return ValueListenableBuilder<bool>(
                                              valueListenable: _editorViewModel.aspectRatioLockedNotifier,
                                              builder: (context, aspectRatioLocked, _) {
                                                logger.logVerbose('Building overlays for ${visibleClipsForOverlay.length} clips. Selected: $selectedClipId', _logTag);
                                                return Stack( // Stack for the overlays themselves
                                                  fit: StackFit.expand,
                                                  children: visibleClipsForOverlay.map((clip) {
                                                    if (clip.databaseId == null) return const SizedBox.shrink();

                                                    final clipId = clip.databaseId!;
                                                    final isSelected = selectedClipId == clipId;
                                                    // Get rect/flip, providing defaults if missing (shouldn't happen with VM logic)
                                                    final currentRect = clipRects[clipId] ?? Rect.zero;
                                                    final currentFlip = clipFlips[clipId] ?? Flip.none;

                                                    return _buildTransformableBoxOverlay(
                                                      context,
                                                      clipId,
                                                      currentRect,
                                                      currentFlip,
                                                      isSelected,
                                                      aspectRatioLocked,
                                                    );
                                                  }).toList(),
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),

                            // 3. Loading Indicator (Listens to isProcessingNotifier from ViewModel)
                            ValueListenableBuilder<bool>(
                              valueListenable: _previewViewModel.isProcessingNotifier, // Listen to ViewModel
                              builder: (context, isProcessing, _) {
                                logger.logVerbose('Processing state builder: $isProcessing', _logTag);
                                if (isProcessing) {
                                  return const Center(child: ProgressRing());
                                } else {
                                  return const SizedBox.shrink();
                                }
                              },
                            ),

                            // 4. Empty State (Listens to texture and visible clips from ViewModel)
                            ValueListenableBuilder<int>(
                                valueListenable: _previewViewModel.textureIdNotifier, // Listen to ViewModel
                                builder: (context, textureId, _) {
                                  return ValueListenableBuilder<List<ClipModel>>(
                                      valueListenable: _previewViewModel.visibleClipsNotifier,
                                      builder: (context, clipsForOverlay, _) {
                                        final hasTexture = textureId > 0;
                                        final hasOverlays = clipsForOverlay.isNotEmpty;
                                        logger.logVerbose('Empty state builder: HasTexture=$hasTexture, HasOverlays=$hasOverlays', _logTag);
                                        if (!hasTexture && !hasOverlays) {
                                          return Center(
                                            child: Text(
                                              'No video at current playback position',
                                              style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        } else {
                                          return const SizedBox.shrink(); // Show nothing if texture or overlays exist
                                        }
                                      });
                                }),

                            // 5. Debug Texture ID Indicator (Optional)
                            ValueListenableBuilder<int>(
                              valueListenable: _previewViewModel.textureIdNotifier, // Listen to ViewModel
                              builder: (context, textureId, _) {
                                if (textureId <= 0) return const SizedBox.shrink();
                                return Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    color: Colors.black.withOpacity(0.5),
                                    child: Text(
                                      'Tex ID: $textureId',
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

  // Helper method to build a single TransformableBox overlay
  Widget _buildTransformableBoxOverlay(
    BuildContext context,
    int clipId,
    Rect rect,
    Flip flip,
    bool isSelected,
    bool aspectRatioLocked,
  ) {
    return TransformableBox(
      key: ValueKey('preview_clip_$clipId'), // Use unique key
      rect: rect,
      flip: flip,
      // Configuration for flutter_box_transform
      resizeModeResolver: () =>
          aspectRatioLocked ? ResizeMode.symmetricScale : ResizeMode.freeform,
      constraints: const BoxConstraints( // Example constraints
        minWidth: 20,
        minHeight: 20,
        maxWidth: 4096, // Allow large sizes if needed
        maxHeight: 4096,
      ),
      clampingRect: Rect.largest, // Allow movement anywhere within the parent Stack

      // Callbacks connected directly to PreviewViewModel
      onChanged: (result, details) => _previewViewModel.handleRectChanged(clipId, result.rect),
      onDragStart: (_) => _previewViewModel.handleTransformStart(clipId),
      onResizeStart: (_, __) => _previewViewModel.handleTransformStart(clipId),
      onDragEnd: (_) => _previewViewModel.handleTransformEnd(clipId),
      onResizeEnd: (_, __) => _previewViewModel.handleTransformEnd(clipId),
      onTap: () => _previewViewModel.selectClip(clipId),

      // Control handle visibility based on selection
      enabledHandles: isSelected ? const {...HandlePosition.values} : const {},
      visibleHandles: isSelected ? const {...HandlePosition.values} : const {},

      // Simple border for visual feedback
      contentBuilder: (context, rect, flip) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.blue.withOpacity(0.7) : Colors.transparent,
              width: 1.5,
            ),
            // Optional: Add a semi-transparent fill when selected?
            // color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          ),
          // Important: Use SizedBox.expand to ensure the content fills the box,
          // otherwise, the border might not render correctly.
          child: const SizedBox.expand(),
        );
      },
    );
  }
}