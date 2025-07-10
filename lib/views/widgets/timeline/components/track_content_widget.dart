import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as fw;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:flipedit/views/widgets/timeline/components/track_background.dart';
import 'package:flipedit/views/widgets/timeline/components/drag_preview.dart';
import 'package:flipedit/views/widgets/timeline/components/roll_edit_handle.dart';

// Callback types for resize preview handled by the track
typedef ResizeUpdateCallback =
    void Function(int previewStartFrame, int previewEndFrame);
typedef ResizeEndCallback = void Function();

class TrackContentWidget extends StatefulWidget {
  final int trackId;
  final bool isSelected;
  final double zoom;
  final double scrollOffset;
  final List<ClipModel> clips;
  final TimelineViewModel timelineViewModel;
  final TimelineNavigationViewModel timelineNavigationViewModel;

  const TrackContentWidget({
    super.key,
    required this.trackId,
    required this.isSelected,
    required this.zoom,
    required this.scrollOffset,
    required this.clips,
    required this.timelineViewModel,
    required this.timelineNavigationViewModel,
  });

  @override
  State<TrackContentWidget> createState() => _TrackContentWidgetState();
}

class _TrackContentWidgetState extends State<TrackContentWidget> {
  late final ValueNotifier<Offset?> _hoverPositionNotifier = ValueNotifier(
    null,
  );
  final GlobalKey _trackContentKey = GlobalKey();

  // State for resize preview overlay
  Rect? _resizePreviewRect;

  @override
  void dispose() {
    _hoverPositionNotifier.dispose();
    super.dispose();
  }

  /// Calculates the preview frame position using the ViewModel.
  int _calculateFramePositionForPreview(double previewRawX) {
    // Use ViewModel method for calculation
    final framePosition = widget.timelineViewModel
        .calculateFramePositionForOffset(
          previewRawX,
          widget.scrollOffset,
          widget.zoom,
        );
    return framePosition;
  }

  // Helper method to update hover position
  void _updateHoverPosition(Offset? position) {
    if (_hoverPositionNotifier.value != position) {
      setState(() {
        _hoverPositionNotifier.value = position;
      });
    }
  }

  // --- Resize Preview Callback Handlers ---

  void _handleClipResizeUpdate(int previewStartFrame, int previewEndFrame) {
    const double pixelsPerFrameBase = 5.0;
    final double pixelsPerFrame = pixelsPerFrameBase * widget.zoom;
    const double trackHeight =
        65.0; // Assuming fixed height, match TimelineClip

    if (pixelsPerFrame <= 0) return;

    final double previewLeft = previewStartFrame * pixelsPerFrame;
    final double previewWidth =
        (previewEndFrame - previewStartFrame) * pixelsPerFrame;
    final double clampedWidth = previewWidth.clamp(1.0, double.infinity);
    final double previewRight = previewLeft + clampedWidth;

    final newRect = Rect.fromLTRB(previewLeft, 0, previewRight, trackHeight);

    if (_resizePreviewRect != newRect) {
      setState(() {
        _resizePreviewRect = newRect;
      });
    }
  }

  void _handleClipResizeEnd() {
    if (_resizePreviewRect != null) {
      setState(() {
        _resizePreviewRect = null;
      });
    }
  }

  // --- End Resize Preview Callback Handlers ---

  /// Gets preview clip widgets using the ViewModel's preview calculation logic.
  List<Widget> _getPreviewClipsFromViewModel(
    ClipModel draggedClip,
    int frameForPreview,
    double zoom,
    double trackHeight,
  ) {
    if (draggedClip.databaseId == null) {
      return [];
    }

    final targetStartTimeOnTrackMs = widget.timelineViewModel.frameToMs(
      frameForPreview,
    );

    // Simple fallback for drag preview since this is synchronous UI code
    // The actual GES calculations happen during the real drag operation
    final movedClip = draggedClip.copyWith(
      trackId: widget.trackId,
      startTimeOnTrackMs: targetStartTimeOnTrackMs,
      endTimeOnTrackMs: targetStartTimeOnTrackMs + draggedClip.durationOnTrackMs,
    );
    
    final previewClips = [movedClip];

    return previewClips.map((clip) {
      final leftPosition = clip.startFrame * zoom * 5.0;
      final clipWidth = clip.durationFrames * zoom * 5.0;
      return Positioned(
        left: leftPosition,
        top: 0,
        height: trackHeight,
        width: clipWidth.clamp(4.0, double.infinity),
        child: TimelineClip(
          key: ValueKey('preview_${clip.databaseId ?? clip.sourcePath}'),
          clip: clip,
          trackId: widget.trackId,
        ),
      );
    }).toList();
  }

  /// Builds the RollEditHandle widgets for adjacent clips on the track.
  List<Widget> _buildRollEditHandles(
    List<ClipModel> trackClips,
    double zoom,
    TimelineViewModel viewModel,
    double trackHeight,
  ) {
    final List<Widget> handles = [];
    final sortedClips = List<ClipModel>.from(trackClips)
      ..sort((a, b) => a.startFrame.compareTo(b.startFrame));

    for (int i = 0; i < sortedClips.length - 1; i++) {
      final leftClip = sortedClips[i];
      final rightClip = sortedClips[i + 1];

      if (leftClip.endFrame == rightClip.startFrame &&
          leftClip.databaseId != null &&
          rightClip.databaseId != null) {
        final boundaryFrame = leftClip.endFrame;
        final handleWidth = 20.0;
        final leftPosition = (boundaryFrame * zoom * 5.0) - (handleWidth / 2);

        handles.add(
          Positioned(
            key: ValueKey(
              'roll_handle_${leftClip.databaseId}_${rightClip.databaseId}',
            ),
            left: leftPosition,
            top: 0,
            bottom: 0,
            width: handleWidth,
            child: RollEditHandle(
              leftClipId: leftClip.databaseId!,
              rightClipId: rightClip.databaseId!,
              initialFrame: boundaryFrame,
              zoom: zoom,
              viewModel: viewModel,
            ),
          ),
        );
      }
    }
    return handles;
  }

  @override
  Widget build(BuildContext context) {
    const trackHeight = 65.0;

    return Expanded(
      child: DragTarget<ClipModel>(
        key: _trackContentKey,
        onAcceptWithDetails: (details) async {
          final draggedClip = details.data;
          final RenderBox? renderBox =
              _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox == null) {
            return;
          }
          final localPosition = renderBox.globalToLocal(details.offset);
          final targetFrame = widget.timelineViewModel
              .calculateFramePositionForOffset(
                localPosition.dx,
                widget.scrollOffset,
                widget.zoom,
              );
          final targetStartTimeOnTrackMs = widget.timelineViewModel.frameToMs(
            targetFrame,
          );

          await widget.timelineViewModel.handleClipDrop(
            clip: draggedClip,
            trackId: widget.trackId,
            startTimeOnTrackMs: targetStartTimeOnTrackMs,
          );

          _updateHoverPosition(null);
        },
        onWillAcceptWithDetails: (details) {
          final RenderBox? renderBox =
              _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPosition = renderBox.globalToLocal(details.offset);
            _updateHoverPosition(localPosition);
          }
          return true;
        },
        onMove: (details) {
          final RenderBox? renderBox =
              _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final localPosition = renderBox.globalToLocal(details.offset);
            _updateHoverPosition(localPosition);
          }
        },
        onLeave: (_) {
          _updateHoverPosition(null);
        },
        builder: (context, candidateData, rejectedData) {
          int frameForPreview = -1;
          final currentHoverPos = _hoverPositionNotifier.value;
          int timeForPreviewMs = -1;

          if (currentHoverPos != null && candidateData.isNotEmpty) {
            frameForPreview = _calculateFramePositionForPreview(
              currentHoverPos.dx,
            );
            timeForPreviewMs = widget.timelineViewModel.frameToMs(
              frameForPreview,
            );
          }

          final theme = ShadTheme.of(context);

          return RepaintBoundary(
            child: Container(
              height: trackHeight,
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color:
                    widget
                            .isSelected // Use isSelected from parent
                        ? theme.colorScheme.primary.withOpacity(0.1)
                        : candidateData.isNotEmpty
                        ? theme.colorScheme.primary.withOpacity(0.3)
                        : theme.colorScheme.muted,
              ),
              child: Stack(
                clipBehavior: fw.Clip.hardEdge,
                children: [
                  Positioned.fill(child: TrackBackground(zoom: widget.zoom)),

                  if (candidateData.isNotEmpty && frameForPreview >= 0)
                    ..._getPreviewClipsFromViewModel(
                      candidateData.first!,
                      frameForPreview,
                      widget.zoom,
                      trackHeight,
                    )
                  else
                    ...widget.clips.whereType<ClipModel>().map((clip) {
                      final leftPosition = clip.startFrame * widget.zoom * 5.0;
                      final clipWidth = clip.durationFrames * widget.zoom * 5.0;
                      return Positioned(
                        left: leftPosition,
                        top: 0,
                        height: trackHeight,
                        width: clipWidth.clamp(4.0, double.infinity),
                        child: RepaintBoundary(
                          child: TimelineClip(
                            key: ValueKey(clip.databaseId ?? clip.sourcePath),
                            clip: clip,
                            trackId: widget.trackId,
                            onResizeUpdate: _handleClipResizeUpdate,
                            onResizeEnd: _handleClipResizeEnd,
                          ),
                        ),
                      );
                    }),

                  if (_resizePreviewRect != null)
                    Positioned.fromRect(
                      rect: _resizePreviewRect!,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.yellow.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                      ),
                    ),

                  if (frameForPreview >= 0 && timeForPreviewMs >= 0)
                    DragPreview(
                      candidateData: candidateData,
                      zoom: widget.zoom,
                      frameAtDropPosition: frameForPreview,
                      timeAtDropPositionMs: timeForPreviewMs,
                    ),

                  if (candidateData.isEmpty)
                    ..._buildRollEditHandles(
                      widget.clips,
                      widget.zoom,
                      widget.timelineViewModel,
                      trackHeight,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
