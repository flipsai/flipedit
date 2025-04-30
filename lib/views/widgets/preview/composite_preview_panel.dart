import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

/// CompositePreviewPanel displays the current timeline frame using a VideoPlayer widget driven by PreviewViewModel.
class CompositePreviewPanel extends StatefulWidget {
  const CompositePreviewPanel({super.key});

  @override
  _CompositePreviewPanelState createState() => _CompositePreviewPanelState();
}

class _CompositePreviewPanelState extends State<CompositePreviewPanel> {
  late final PreviewViewModel _previewViewModel;
  late final EditorViewModel _editorViewModel;

  final String _logTag = 'CompositePreviewPanel';

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
    _editorViewModel = di<EditorViewModel>();
    logger.logInfo('CompositePreviewPanel initialized', _logTag);
    _previewViewModel.addListener(_rebuild);
  }

  @override
  void dispose() {
    logger.logInfo('CompositePreviewPanel disposing', _logTag);
    _previewViewModel.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewVm = _previewViewModel;
    final editorVm = _editorViewModel;

    final controller = previewVm.controller;
    final isControllerInitialized = controller?.value.isInitialized ?? false;
    final aspectRatio = previewVm.aspectRatioNotifier.value;
    final containerSize = previewVm.containerSizeNotifier.value;
    final visibleClipsForOverlay = previewVm.visibleClipsNotifier.value;
    final clipRects = previewVm.clipRectsNotifier.value;
    final clipFlips = previewVm.clipFlipsNotifier.value;
    final selectedClipId = previewVm.selectedClipIdNotifier.value;
    final aspectRatioLocked = editorVm.aspectRatioLockedNotifier.value;

    logger.logVerbose(
      'CompositePreviewPanel building... Controller: ${controller?.textureId}, Initialized: $isControllerInitialized',
      _logTag,
    );

    return ValueListenableBuilder<int?>(
      valueListenable: previewVm.firstActiveVideoClipIdNotifier,
      builder: (_, firstActiveVideoClipId, __) {
        return ValueListenableBuilder<Map<int, Rect>>(
          valueListenable: previewVm.clipRectsNotifier,
          builder: (_, clipRects, __) {
            final videoRect = (firstActiveVideoClipId != null)
                ? clipRects[firstActiveVideoClipId]
                : null;

            logger.logVerbose(
              'CompositePreviewPanel building... Controller: ${controller?.textureId}, VideoRect: $videoRect',
              _logTag,
            );

            return Container(
              color: Colors.grey[160],
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: aspectRatio,
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
                              
                              final Size actualSize = constraints.biggest;
                              final scaleX = (previewVm.containerSize?.width ?? 0) > 0 
                                  ? actualSize.width / previewVm.containerSize!.width 
                                  : 1.0;
                              final scaleY = (previewVm.containerSize?.height ?? 0) > 0
                                  ? actualSize.height / previewVm.containerSize!.height
                                  : 1.0;

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  logger.logVerbose('Background tapped, deselecting clip.', _logTag);
                                  previewVm.selectClip(null);
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Builder(builder: (context) {
                                      final currentController = previewVm.controller;
                                      final isInit = currentController?.value.isInitialized ?? false;
                                      final hasError = currentController?.value.hasError ?? false;

                                      if (currentController != null && isInit && videoRect != null) {
                                        final pixelLeft = videoRect.left * scaleX;
                                        final pixelTop = videoRect.top * scaleY;
                                        final pixelWidth = videoRect.width * scaleX;
                                        final pixelHeight = videoRect.height * scaleY;

                                        final safeWidth = pixelWidth < 0 ? 0.0 : pixelWidth;
                                        final safeHeight = pixelHeight < 0 ? 0.0 : pixelHeight;

                                        return Positioned(
                                          left: pixelLeft,
                                          top: pixelTop,
                                          width: safeWidth,
                                          height: safeHeight,
                                          child: AspectRatio(
                                            aspectRatio: currentController.value.aspectRatio,
                                            child: VideoPlayer(currentController),
                                          ),
                                        );
                                      } else if (hasError) {
                                        return Center(
                                          child: Text(
                                            'Error loading video: ${currentController?.value.errorDescription}',
                                            style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.red),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      } else if (currentController != null && !isInit) {
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

                                    ValueListenableBuilder<List<ClipModel>>(
                                      valueListenable: previewVm.visibleClipsNotifier,
                                      builder: (_, visibleClipsForOverlay, __) {
                                        return ValueListenableBuilder<Map<int, Rect>>(
                                          valueListenable: previewVm.clipRectsNotifier,
                                          builder: (_, clipRects, __) {
                                            return ValueListenableBuilder<Map<int, Flip>>(
                                              valueListenable: previewVm.clipFlipsNotifier,
                                              builder: (_, clipFlips, __) {
                                                return ValueListenableBuilder<int?>(
                                                  valueListenable: previewVm.selectedClipIdNotifier,
                                                  builder: (_, selectedClipId, __) {
                                                    return ValueListenableBuilder<bool>(
                                                      valueListenable: editorVm.aspectRatioLockedNotifier,
                                                      builder: (_, aspectRatioLocked, __) {
                                                        return Stack(
                                                          fit: StackFit.expand,
                                                          children: visibleClipsForOverlay.map((clip) {
                                                            if (clip.databaseId == null) return const SizedBox.shrink();
                                                            final clipId = clip.databaseId!;
                                                            final isSelected = selectedClipId == clipId;
                                                            final currentRect = clipRects[clipId] ?? Rect.zero;
                                                            final currentFlip = clipFlips[clipId] ?? Flip.none;
                                                            return _buildTransformableBoxOverlay(
                                                              context,
                                                              previewVm,
                                                              editorVm,
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
          },
        );
      },
    );
  }

  Widget _buildTransformableBoxOverlay(
    BuildContext context,
    PreviewViewModel previewVm,
    EditorViewModel editorVm,
    int clipId,
    Rect rect,
    Flip flip,
    bool isSelected,
    bool aspectRatioLocked,
  ) {
    return TransformableBox(
      key: ValueKey('preview_clip_$clipId'),
      rect: rect,
      flip: flip,
      resizeModeResolver: () =>
          aspectRatioLocked ? ResizeMode.symmetricScale : ResizeMode.freeform,
      constraints: const BoxConstraints(
        minWidth: 20,
        minHeight: 20,
        maxWidth: 4096,
        maxHeight: 4096,
      ),
      clampingRect: Rect.largest,

      onChanged: (result, details) => previewVm.handleRectChanged(clipId, result.rect),
      onDragStart: (_) => previewVm.handleTransformStart(clipId),
      onResizeStart: (_, __) => previewVm.handleTransformStart(clipId),
      onDragEnd: (_) => previewVm.handleTransformEnd(clipId),
      onResizeEnd: (_, __) => previewVm.handleTransformEnd(clipId),
      onTap: () => previewVm.selectClip(clipId),

      enabledHandles: isSelected ? const {...HandlePosition.values} : const {},
      visibleHandles: isSelected ? const {...HandlePosition.values} : const {},

      contentBuilder: (context, rect, flip) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.blue.withOpacity(0.7) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}