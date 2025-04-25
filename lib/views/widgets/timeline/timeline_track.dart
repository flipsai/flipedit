import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw;
import "dart:developer" as developer;
import 'painters/track_background_painter.dart';
import 'package:flipedit/viewmodels/commands/roll_edit_command.dart';
import 'package:flipedit/viewmodels/commands/add_clip_command.dart';

class TimelineTrack extends StatefulWidget with WatchItStatefulWidgetMixin {
  final Track track;
  final VoidCallback onDelete;
  final double trackLabelWidth;

  const TimelineTrack({
    super.key,
    required this.track,
    required this.onDelete,
    required this.trackLabelWidth,
  });

  @override
  State<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends State<TimelineTrack> {
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late final ValueNotifier<Offset?> _hoverPositionNotifier = ValueNotifier(null);
  final GlobalKey _trackContentKey = GlobalKey();

  late TimelineViewModel _timelineViewModel;
  late ProjectDatabaseService _databaseService;

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>();
    _databaseService = di<ProjectDatabaseService>();
    _textController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _submitRename();
      }
    });

    // Force a refresh of clips when mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineViewModel.refreshClips();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.removeListener(() { });
    _focusNode.dispose();
    _hoverPositionNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TimelineTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the track name changes from the parent widget AND we are not currently editing,
    // update the text controller to reflect the external change.
    if (widget.track.name != oldWidget.track.name && !_isEditing) {
      developer.log('Track name updated externally from "${oldWidget.track.name}" to "${widget.track.name}"');
      _textController.text = widget.track.name;
    }
  }
 
  void _enterEditingMode() {
    setState(() {
      _isEditing = true;
      _textController.text = widget.track.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _focusNode.requestFocus();
       _textController.selection = TextSelection(
           baseOffset: 0,
           extentOffset: _textController.text.length,
       );
    });
  }

  void _submitRename() {
    developer.log('Attempting to submit rename for track ${widget.track.id}...');
    final newName = _textController.text.trim();
    if (mounted && _isEditing) {
      developer.log('Mounted and isEditing: true. New name: "$newName"');
      final oldName = widget.track.name; // Store old name
      if (newName.isNotEmpty && newName != oldName) {
        developer.log('New name is valid. Calling timelineViewModel.updateTrackName...');
        _timelineViewModel.updateTrackName(widget.track.id, newName);
      }
      setState(() {
        _isEditing = false;
        developer.log('Exiting editing mode.');
      });
    } else {
      developer.log('Not submitting: mounted=$mounted, isEditing=$_isEditing');
    }
  }

  double getHorizontalScrollOffset() {
    if (_timelineViewModel.trackContentHorizontalScrollController.hasClients) {
      return _timelineViewModel.trackContentHorizontalScrollController.offset;
    }
    return 0.0;
  }

  int _calculateFramePositionForPreview(double previewRawX, double zoom) {
    final scrollOffsetX = getHorizontalScrollOffset();
    final position = (previewRawX + scrollOffsetX) / (5.0 * zoom);
    final framePosition = position < 0 ? 0 : position.floor();
    
    // Debug the calculation to ensure it matches with the actual drop
    developer.log(
      '🔍 Preview position: raw=$previewRawX, scroll=$scrollOffsetX, frame=$framePosition',
      name: 'TimelineTrack'
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

  Future<void> _handleClipDrop(ClipModel draggedClip, int startTimeOnTrackMs) async {
    final timelineVm = di<TimelineViewModel>();
    await timelineVm.handleClipDrop(
      clip: draggedClip,
      trackId: widget.track.id,
      startTimeOnTrackMs: startTimeOnTrackMs,
    );
    // ViewModel handles updates, no explicit refresh needed here
  }

  @override
  Widget build(BuildContext context) {
    final double zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final theme = FluentTheme.of(context);
    const trackHeight = 65.0;

    // Watch only the clips for this track
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier)
        .where((clip) => clip.trackId == widget.track.id)
        .toList();

    // Log clips for debugging
    if (clips.isNotEmpty) {
      developer.log(
        '📼 Building TimelineTrack "${widget.track.name}" with ${clips.length} clips',
        name: 'TimelineTrack'
      );
      developer.log(
        '📼 First clip: ${clips.first.name}, startFrame: ${clips.first.startFrame}',
        name: 'TimelineTrack'
      );
    } else {
      developer.log(
        '📼 Building TimelineTrack "${widget.track.name}" with NO CLIPS',
        name: 'TimelineTrack'
      );
    }

    return SizedBox(
      height: trackHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: widget.trackLabelWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: theme.resources.subtleFillColorTertiary,
              border: Border(
                right: BorderSide(
                  color: theme.resources.controlStrokeColorDefault,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: _enterEditingMode,
                    child: _isEditing
                        ? TextBox(
                            controller: _textController,
                            focusNode: _focusNode,
                            placeholder: 'Track Name',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 4.0,
                            ),
                            style: theme.typography.body,
                            decoration: WidgetStateProperty.all(BoxDecoration(
                              color: theme.resources.controlFillColorDefault,
                              borderRadius: BorderRadius.circular(4.0),
                            )),
                            onSubmitted: (_) => _submitRename(),
                          )
                        : Text(
                            widget.track.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.body,
                          ),
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.delete, size: 14),
                  onPressed: widget.onDelete,
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(EdgeInsets.zero),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DragTarget<ClipModel>(
              key: _trackContentKey,
              onAcceptWithDetails: (details) async {
                final draggedClip = details.data;
                developer.log('✅ Clip drop detected: ${draggedClip.name}', name: 'TimelineTrack');
                final RenderBox? renderBox =
                    _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
                if (renderBox == null) {
                  developer.log('❌ Error: renderBox is null in onAcceptWithDetails', name: 'TimelineTrack');
                  return;
                }
                final localPosition = renderBox.globalToLocal(details.offset);
                final scrollOffsetX = getHorizontalScrollOffset();
                final posX = localPosition.dx;
                final framePosition = ((posX + scrollOffsetX) / (5.0 * zoom)).floor();
                // Calculate position in milliseconds using the ViewModel's helper
                final startTimeOnTrackMs = _timelineViewModel.frameToMs(framePosition);
                developer.log(
                  '📏 Position metrics: local=$posX, scroll=$scrollOffsetX, frame=$framePosition, ms=$startTimeOnTrackMs',
                  name: 'TimelineTrack'
                );
                final addClipCmd = AddClipCommand(
                  vm: _timelineViewModel,
                  clipData: draggedClip,
                  trackId: widget.track.id,
                  // Pass the calculated start time on the track
                  startTimeOnTrackMs: startTimeOnTrackMs,
                  // Use the original source start time
                  startTimeInSourceMs: draggedClip.startTimeInSourceMs,
                  endTimeInSourceMs: draggedClip.endTimeInSourceMs,
                  localPositionX: null,
                  scrollOffsetX: null,
                );
                await _timelineViewModel.runCommand(addClipCmd);
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

                if (currentHoverPos != null && candidateData.isNotEmpty) {
                  frameForPreview = _calculateFramePositionForPreview(currentHoverPos.dx, zoom);
                }

                return Container(
                  height: trackHeight,
                  margin: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: candidateData.isNotEmpty
                        ? theme.accentColor.lightest.withValues(alpha: 0.3)
                        : theme.resources.subtleFillColorSecondary,
                  ),
                  child: Stack(
                    clipBehavior: fw.Clip.hardEdge,
                    children: [
                      // Background grid with frame markings
                      Positioned.fill(child: _TrackBackground(zoom: zoom)),

                      // Display existing clips on this track, or preview if dragging
                      if (candidateData.isNotEmpty && frameForPreview >= 0)
                        ..._getPreviewClips(candidateData.first!, frameForPreview, zoom, trackHeight)
                      else
                        ...clips.whereType<ClipModel>().map((clip) {
                          final leftPosition = clip.startFrame * zoom * 5.0;
                          final clipWidth = clip.durationFrames * zoom * 5.0;
                          return Positioned(
                            left: leftPosition,
                            top: 0,
                            height: trackHeight,
                            width: clipWidth.clamp(4.0, double.infinity),
                            child: TimelineClip(
                              key: ValueKey(clip.databaseId ?? clip.sourcePath),
                              clip: clip,
                              trackId: widget.track.id,
                            ),
                          );
                        }),

                      // Show preview for where the clip will be placed when dragging
                      if (frameForPreview >= 0)
                        _DragPreview(
                          hoverPositionNotifier: _hoverPositionNotifier,
                          candidateData: candidateData,
                          zoom: zoom,
                          frameAtDropPosition: frameForPreview,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _getPreviewClips(ClipModel draggedClip, int frameForPreview, double zoom, double trackHeight) {
    if (draggedClip.databaseId == null) {
      debugPrint('Warning: draggedClip.databaseId is null. Skipping preview.');
      return [];
    }
    final timelineVm = di<TimelineViewModel>();
    final previewClips = timelineVm.getPreviewClipsForDrag(
      clipId: draggedClip.databaseId!,
      targetTrackId: widget.track.id,
      targetStartTimeOnTrackMs: (frameForPreview * (1000 / 30)).toInt(),
    ).where((clip) => clip.trackId == widget.track.id).whereType<ClipModel>().toList();
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
          trackId: widget.track.id,
        ),
      );
    }).toList();
  }
}

class _DragPreview extends StatelessWidget with WatchItMixin {
  final ValueNotifier<Offset?> hoverPositionNotifier;
  final List<ClipModel?> candidateData;
  final double zoom;
  final int frameAtDropPosition;

  const _DragPreview({
    required this.hoverPositionNotifier,
    required this.candidateData,
    required this.zoom,
    required this.frameAtDropPosition,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Make sure to watch the notifier for position updates
    final hoverPosValue = watch(hoverPositionNotifier);
    // Use the same track height constant
    const trackHeight = 65.0;

    developer.log('DragPreview build - hover: $hoverPosValue, candidates: ${candidateData.length}', name: 'DragPreview');

    if (candidateData.isEmpty) {
      return const SizedBox.shrink();
    }

    final draggedClip = candidateData.first;
    if (draggedClip == null) {
      return const SizedBox.shrink();
    }
    
    final previewLeftPosition = frameAtDropPosition * zoom * 5.0;
    final previewWidth = draggedClip.durationFrames * zoom * 5.0;
    
    // Calculate time in milliseconds for display
    final timeInMs = ClipModel.framesToMs(frameAtDropPosition);
    final formattedTime = '${(timeInMs / 1000).toStringAsFixed(2)}s';

    return Stack(
      clipBehavior: fw.Clip.none,
      children: [
        // Position indicator line
        Positioned(
          left: previewLeftPosition,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: theme.accentColor.lighter),
        ),
        // Preview rectangle
        Positioned(
          left: previewLeftPosition,
          top: 4, // Add a bit of padding from the top
          height: trackHeight - 8, // Leave some padding at bottom too
          width: previewWidth.clamp(2.0, double.infinity),
          child: Container(
            decoration: BoxDecoration(
              color: theme.accentColor.normal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.accentColor.normal, width: 2),
            ),
            child: Center(
              child: Text(
                draggedClip.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        // Frame and time information
        Positioned(
          left: previewLeftPosition + previewWidth + 5,
          top: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frame: $frameAtDropPosition',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                Text(
                  'Time: $formattedTime',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TrackBackground extends StatelessWidget {
  final double zoom;

  const _TrackBackground({required this.zoom});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final lineColor = theme.resources.controlStrokeColorDefault;
    final faintLineColor = theme.resources.subtleFillColorTertiary;
    final textColor = theme.typography.caption?.color ?? Colors.grey;

    return RepaintBoundary(
      child: CustomPaint(
        painter: TrackBackgroundPainter(
          zoom: zoom,
          lineColor: lineColor,
          faintLineColor: faintLineColor,
          textColor: textColor,
        ),
        child: Container(),
      ),
    );
  }
}

class _RollEditHandle extends StatefulWidget {
  final int leftClipId;
  final int rightClipId;
  final int initialFrame;
  final double zoom;

  const _RollEditHandle({
    required this.leftClipId,
    required this.rightClipId,
    required this.initialFrame,
    required this.zoom,
  });

  @override
  State<_RollEditHandle> createState() => _RollEditHandleState();
}

class _RollEditHandleState extends State<_RollEditHandle> {
  double _startX = 0;
  int _startFrame = 0;
  int _initialFrame = 0;

  @override
  void initState() {
    super.initState();
    _startFrame = widget.initialFrame;
    _initialFrame = widget.initialFrame;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _startX = details.globalPosition.dx;
        _startFrame = _initialFrame;
      },
      onHorizontalDragUpdate: (details) async {
        final pixelsPerFrame = 5.0 * widget.zoom;
        final frameDelta = ((details.globalPosition.dx - _startX) / pixelsPerFrame).round();
        final newBoundary = _startFrame + frameDelta;
        final timelineVm = di<TimelineViewModel>();
        final cmd = RollEditCommand(
          vm: timelineVm,
          leftClipId: widget.leftClipId,
          rightClipId: widget.rightClipId,
          newBoundaryFrame: newBoundary,
        );
        // Don't await UI updates, run command asynchronously
        timelineVm.runCommand(cmd);
      },
      onHorizontalDragEnd: (_) {
        _startX = 0;
        _startFrame = widget.initialFrame;
      },
      onHorizontalDragCancel: () {
        _startX = 0;
        _startFrame = widget.initialFrame;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          decoration: BoxDecoration(
            color: theme.accentColor.normal.withAlpha(70),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.accentColor.normal, width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Icon(FluentIcons.a_a_d_logo, size: 14, color: theme.accentColor.darker),
          ),
        ),
      ),
    );
  }
}

