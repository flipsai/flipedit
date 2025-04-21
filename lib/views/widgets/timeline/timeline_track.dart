import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_database.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw;
import 'dart:developer' as developer;

class TimelineTrack extends StatefulWidget with WatchItStatefulWidgetMixin {
  final Track track;
  final List<ClipModel> clips;
  final VoidCallback onDelete;
  final double trackLabelWidth;

  const TimelineTrack({
    super.key,
    required this.track,
    required this.clips,
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
      _timelineViewModel.forceRefreshClips();
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
    if (widget.track.name != oldWidget.track.name && !_isEditing) {
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
    developer.log('Attempting to submit rename...');
    final newName = _textController.text.trim();
    if (mounted && _isEditing) {
       developer.log('Mounted and isEditing: true. New name: "$newName"');
       if (newName.isNotEmpty && newName != widget.track.name) {
        developer.log('New name is valid. Calling databaseService.updateTrackName...');
        _databaseService.updateTrackName(widget.track.id, newName);
       } else {
         developer.log('New name is empty or same as old name. Not saving.');
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

  @override
  Widget build(BuildContext context) {
    final double zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final theme = FluentTheme.of(context);
    const trackHeight = 65.0;

    // Log clips for debugging
    if (widget.clips.isNotEmpty) {
      developer.log(
        '📼 Building TimelineTrack "${widget.track.name}" with ${widget.clips.length} clips',
        name: 'TimelineTrack'
      );
      developer.log(
        '📼 First clip: ${widget.clips.first.name}, startFrame: ${widget.clips.first.startFrame}',
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
              onAcceptWithDetails: (details) {
                final draggedClip = details.data;
                developer.log('✅ Clip drop detected: ${draggedClip.name}', name: 'TimelineTrack');
                
                final RenderBox? renderBox =
                    _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
                if (renderBox == null) {
                  developer.log('❌ Error: renderBox is null in onAcceptWithDetails', name: 'TimelineTrack');
                  return;
                }

                // Get local position within the track
                final localPosition = renderBox.globalToLocal(details.offset);
                
                // Calculate the proper position with scroll offset
                final scrollOffsetX = getHorizontalScrollOffset();
                final posX = localPosition.dx;
                
                // Calculate the exact frame position
                final framePosition = ((posX + scrollOffsetX) / (5.0 * zoom)).floor();
                final framePositionMs = framePosition * (1000 / 30); // Convert to ms (30fps)
                
                developer.log(
                  '📏 Position metrics: local=$posX, scroll=$scrollOffsetX, frame=$framePosition, ms=$framePositionMs',
                  name: 'TimelineTrack'
                );
                
                // Using the TimelineViewModel directly through watch_it
                di<TimelineViewModel>().createTimelineClip(
                  trackId: widget.track.id,
                  clipData: draggedClip,
                  framePosition: framePosition,
                );
                
                _updateHoverPosition(null);
              },
              onWillAcceptWithDetails: (details) {
                // Log fewer messages to reduce noise
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
                        ? theme.accentColor.lightest.withOpacity(0.3)
                        : theme.resources.subtleFillColorSecondary,
                  ),
                  child: Stack(
                    clipBehavior: fw.Clip.hardEdge,
                    children: [
                      // Background grid with frame markings
                      Positioned.fill(child: _TrackBackground(zoom: zoom)),
                      
                      // Display existing clips on this track
                      ...widget.clips.map((clip) {
                        final leftPosition = clip.startFrame * zoom * 5.0;
                        final clipWidth = clip.durationFrames * zoom * 5.0;
                        return Positioned(
                          left: leftPosition,
                          top: 0,
                          height: trackHeight,
                          width: clipWidth.clamp(4.0, double.infinity),
                          child: TimelineClip(
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
              color: theme.accentColor.normal.withOpacity(0.5),
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
              color: Colors.black.withOpacity(0.7),
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
        painter: _TrackBackgroundPainter(
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

class _TrackBackgroundPainter extends CustomPainter {
  final double zoom;
  final Color lineColor;
  final Color faintLineColor;
  final Color textColor;

  final Paint linePaint;
  final Paint faintLinePaint;

  _TrackBackgroundPainter({
    required this.zoom,
    required this.lineColor,
    required this.faintLineColor,
    required this.textColor,
  }) : linePaint = Paint()..strokeWidth = 1.0,
       faintLinePaint = Paint()..strokeWidth = 0.5 {
    linePaint.color = lineColor;
    faintLinePaint.color = faintLineColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double framePixelWidth = 5.0;
    const int framesPerMajorTick = 30;
    const int framesPerMinorTick = 5;

    final double effectiveFrameWidth = framePixelWidth * zoom;

    if (effectiveFrameWidth <= 0) return;

    final int totalMinorTicks =
        (size.width / (effectiveFrameWidth * framesPerMinorTick)).ceil() + 1;

    for (int i = 0; i < totalMinorTicks; i++) {
      final int frameNumber = i * framesPerMinorTick;
      final double x = frameNumber * effectiveFrameWidth;
      final bool isMajorTick = frameNumber % framesPerMajorTick == 0;

      final paintToUse = isMajorTick ? linePaint : faintLinePaint;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintToUse);
    }
  }

  @override
  bool shouldRepaint(covariant _TrackBackgroundPainter oldDelegate) {
    return oldDelegate.zoom != zoom ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.faintLineColor != faintLineColor ||
        oldDelegate.textColor != textColor;
  }
}
