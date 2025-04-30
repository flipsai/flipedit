import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// PreviewPanel displays the current timeline frame's video(s).
/// Uses PreviewViewModel via DI.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key});

  @override
  _PreviewPanelState createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  late final PreviewViewModel _previewViewModel;

  @override
  void initState() {
    super.initState();
    _previewViewModel = di<PreviewViewModel>();
  }

  @override
  Widget build(BuildContext context) {
    return PreviewPanelContent(previewViewModel: _previewViewModel);
  }
}

// --- Preview Panel Content (Stateful + Manual Listeners) ---

class PreviewPanelContent extends StatefulWidget {
  final PreviewViewModel previewViewModel;

  const PreviewPanelContent({super.key, required this.previewViewModel});

  @override
  _PreviewPanelContentState createState() => _PreviewPanelContentState();
}

class _PreviewPanelContentState extends State<PreviewPanelContent> {
  // Local state variables mirroring ViewModel notifiers
  late List<ClipModel> _visibleClips;
  late Map<int, Rect> _clipRects;
  late Map<int, Flip> _clipFlips;
  late int? _selectedClipId;
  late double _aspectRatio;
  late Size? _containerSize;
  late double? _hSnap;
  late double? _vSnap;
  late bool _aspectRatioLocked;
  // Add local state variable to hold the set of initialized IDs (ensures state update triggers listener)
  late Set<int> _initializedControllerIds;

  // Keep reference to EditorViewModel for listener
  late EditorViewModel _editorViewModel;

  @override
  void initState() {
    super.initState();

    // Get EditorViewModel instance from DI
    _editorViewModel = di<EditorViewModel>();

    // Initialize local state from ViewModel
    _updateStateFromViewModel();

    // Add listeners
    widget.previewViewModel.visibleClipsNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.clipRectsNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.clipFlipsNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.selectedClipIdNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.aspectRatioNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.containerSizeNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.activeHorizontalSnapYNotifier.addListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.activeVerticalSnapXNotifier.addListener(
      _handleViewModelChange,
    );
    _editorViewModel.aspectRatioLockedNotifier.addListener(
      _handleViewModelChange,
    );
    // Listen to the new notifier for controller initialization changes
    widget.previewViewModel.initializedControllerIdsNotifier.addListener(
      _handleViewModelChange,
    );
  }

  // Common listener callback
  void _handleViewModelChange() {
    // Update local state and trigger rebuild
    if (mounted) {
      setState(() {
        _updateStateFromViewModel();
      });
    }
  }

  // Helper to update all local state variables
  void _updateStateFromViewModel() {
    _visibleClips = widget.previewViewModel.visibleClipsNotifier.value;
    _clipRects = widget.previewViewModel.clipRectsNotifier.value;
    _clipFlips = widget.previewViewModel.clipFlipsNotifier.value;
    _selectedClipId = widget.previewViewModel.selectedClipIdNotifier.value;
    _aspectRatio = widget.previewViewModel.aspectRatioNotifier.value;
    _containerSize = widget.previewViewModel.containerSizeNotifier.value;
    _hSnap = widget.previewViewModel.activeHorizontalSnapYNotifier.value;
    _vSnap = widget.previewViewModel.activeVerticalSnapXNotifier.value;
    _aspectRatioLocked = _editorViewModel.aspectRatioLockedNotifier.value;
    // Read the value from the new notifier into local state
    _initializedControllerIds =
        widget.previewViewModel.initializedControllerIdsNotifier.value;
  }

  @override
  void dispose() {
    // Remove listeners
    widget.previewViewModel.visibleClipsNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.clipRectsNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.clipFlipsNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.selectedClipIdNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.aspectRatioNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.containerSizeNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.activeHorizontalSnapYNotifier.removeListener(
      _handleViewModelChange,
    );
    widget.previewViewModel.activeVerticalSnapXNotifier.removeListener(
      _handleViewModelChange,
    );
    _editorViewModel.aspectRatioLockedNotifier.removeListener(
      _handleViewModelChange,
    );
    // Remove the listener for the new notifier
    widget.previewViewModel.initializedControllerIdsNotifier.removeListener(
      _handleViewModelChange,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Access the ViewModel via widget.previewViewModel
    final previewViewModel = widget.previewViewModel;
    final videoControllers =
        previewViewModel.videoControllers; // Get controllers map

    // --- Build using local state variables (_visibleClips, _clipRects, etc.) ---
    final List<Widget> transformablePlayers = [];

    for (final clip in _visibleClips) {
      // Use local state
      final hasController = videoControllers.containsKey(clip.databaseId);
      final controller =
          hasController ? videoControllers[clip.databaseId]! : null;
      // Use the locally synced _initializedControllerIds set to check initialization status
      final isInitialized = _initializedControllerIds.contains(
        clip.databaseId,
      ); // Use the synced set
      final currentRect =
          _clipRects[clip.databaseId] ?? Rect.zero; // Use local state
      final currentFlip =
          _clipFlips[clip.databaseId] ?? Flip.none; // Use local state

      // Check uses the isInitialized derived from the synced notifier state
      if (clip.type == ClipType.video &&
          hasController &&
          controller != null &&
          isInitialized) {
        final bool isSelected =
            _selectedClipId == clip.databaseId; // Use local state
        transformablePlayers.add(
          TransformableBox(
            key: ValueKey('preview_clip_${clip.databaseId!}'),
            rect: currentRect,
            flip: currentFlip,
            resizeModeResolver:
                () =>
                    _aspectRatioLocked
                        ? ResizeMode.symmetricScale
                        : ResizeMode.freeform, // Use local state
            // Callbacks still use previewViewModel directly
            onChanged: (result, details) {
              previewViewModel.handleRectChanged(clip.databaseId!, result.rect);
            },
            onDragStart: (result) {
              previewViewModel.handleTransformStart(clip.databaseId!);
            },
            onResizeStart: (HandlePosition handle, DragStartDetails event) {
              previewViewModel.handleTransformStart(clip.databaseId!);
            },
            onDragEnd: (result) {
              previewViewModel.handleTransformEnd(clip.databaseId!);
            },
            onResizeEnd: (HandlePosition handle, DragEndDetails event) {
              previewViewModel.handleTransformEnd(clip.databaseId!);
            },
            onTap: () {
              previewViewModel.selectClip(clip.databaseId!);
            },
            enabledHandles:
                isSelected ? const {...HandlePosition.values} : const {},
            visibleHandles:
                isSelected ? const {...HandlePosition.values} : const {},
            constraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 36,
              maxWidth: 1920,
              maxHeight: 1080,
            ),
            contentBuilder: (context, rect, flip) {
              // Now that the outer check ensures initialization, we can directly return the VideoPlayer.
              return VideoPlayer(controller);
            },
          ),
        );
      }
    }

    Widget content;
    if (transformablePlayers.isEmpty) {
      content = Center(
        child: Text(
          'No video at current playback position',
          style: FluentTheme.of(
            context,
          ).typography.bodyLarge?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      content = Stack(children: transformablePlayers);
    }

    return Container(
      color: Colors.grey[160],
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio, // Use local state
                child: Container(
                  color: Colors.black.withOpacity(0.1),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            previewViewModel.containerSize !=
                                constraints.biggest) {
                          previewViewModel.updateContainerSize(
                            constraints.biggest,
                          );
                        }
                      });
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          previewViewModel.selectClip(null);
                        },
                        child: Stack(
                          children: [
                            content,
                            if (_containerSize != null &&
                                (_hSnap != null ||
                                    _vSnap != null)) // Use local state
                              SnapGuidePainter(
                                containerSize:
                                    _containerSize!, // Use local state
                                horizontalSnapY: _hSnap, // Use local state
                                verticalSnapX: _vSnap, // Use local state
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

// --- Snap Guide Painter (Keep as is) ---
// (Painter code remains the same as previously written)
class SnapGuidePainter extends StatelessWidget {
  final Size containerSize;
  final double? horizontalSnapY;
  final double? verticalSnapX;

  const SnapGuidePainter({
    super.key,
    required this.containerSize,
    this.horizontalSnapY,
    this.verticalSnapX,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = FluentTheme.of(context).accentColor;

    return CustomPaint(
      size: containerSize,
      painter: _GuidePainter(
        horizontalSnapY: horizontalSnapY,
        verticalSnapX: verticalSnapX,
        lineColor: accentColor,
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final double? horizontalSnapY;
  final double? verticalSnapX;
  final Color lineColor;

  final Paint _paint;

  _GuidePainter({
    this.horizontalSnapY,
    this.verticalSnapX,
    required this.lineColor,
  }) : _paint =
           Paint()
             ..color = lineColor
             ..strokeWidth = 1.0
             ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (horizontalSnapY != null) {
      canvas.drawLine(
        Offset(0, horizontalSnapY!),
        Offset(size.width, horizontalSnapY!),
        _paint,
      );
    }
    if (verticalSnapX != null) {
      canvas.drawLine(
        Offset(verticalSnapX!, 0),
        Offset(verticalSnapX!, size.height),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) {
    return oldDelegate.horizontalSnapY != horizontalSnapY ||
        oldDelegate.verticalSnapX != verticalSnapX ||
        oldDelegate.lineColor != lineColor;
  }
}
