import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/app_database.dart' show Track;
import 'package:flipedit/services/project_service.dart';
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
  final hoverPositionNotifier = ValueNotifier<Offset?>(null);
  final GlobalKey trackContentKey = GlobalKey();
  late TimelineViewModel timelineViewModel;
  late ProjectService projectService;

  @override
  void initState() {
    super.initState();
    timelineViewModel = di<TimelineViewModel>();
    projectService = di<ProjectService>();
  }

  @override
  void dispose() {
    hoverPositionNotifier.dispose();
    super.dispose();
  }

  double getHorizontalScrollOffset() {
    if (timelineViewModel.trackContentHorizontalScrollController.hasClients) {
      return timelineViewModel.trackContentHorizontalScrollController.offset;
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final double zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    const trackHeight = 60.0;

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
                  child: Text(
                    widget.track.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body,
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
              key: trackContentKey,
              onAcceptWithDetails: (details) {
                final draggedClip = details.data;

                final RenderBox? renderBox =
                    trackContentKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (renderBox == null) return;

                final localPosition = renderBox.globalToLocal(details.offset);
                double posX = localPosition.dx.clamp(0.0, renderBox.size.width);
                final scrollOffsetX = getHorizontalScrollOffset();

                developer.log(
                  'Accepting drop at: local=$posX, scroll=$scrollOffsetX, zoom=$zoom',
                );

                timelineViewModel.addClipAtPosition(
                  clipData: draggedClip,
                  trackId: widget.track.id,
                  startTimeInSourceMs: draggedClip.startTimeInSourceMs,
                  endTimeInSourceMs: draggedClip.endTimeInSourceMs,
                  localPositionX: posX,
                  scrollOffsetX: scrollOffsetX,
                );

                hoverPositionNotifier.value = null;
              },
              onWillAcceptWithDetails: (details) {
                final RenderBox? renderBox =
                    trackContentKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (renderBox != null) {
                  final localPosition = renderBox.globalToLocal(details.offset);
                  hoverPositionNotifier.value = localPosition;
                }
                return true;
              },
              onMove: (details) {
                final RenderBox? renderBox =
                    trackContentKey.currentContext?.findRenderObject()
                        as RenderBox?;
                if (renderBox != null) {
                  final localPosition = renderBox.globalToLocal(details.offset);
                  if (localPosition.dx >= 0 &&
                      localPosition.dx <= renderBox.size.width) {
                    hoverPositionNotifier.value = localPosition;
                  } else {
                    hoverPositionNotifier.value = null;
                  }
                }
              },
              onLeave: (_) {
                hoverPositionNotifier.value = null;
              },
              builder: (context, candidateData, rejectedData) {
                return Container(
                  height: 60,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color:
                        candidateData.isNotEmpty
                            ? theme.accentColor.lightest.withOpacity(0.3)
                            : theme.resources.subtleFillColorSecondary,
                  ),
                  child: Stack(
                    clipBehavior: fw.Clip.hardEdge,
                    children: [
                      Positioned.fill(child: _TrackBackground(zoom: zoom)),
                      ...widget.clips.map((clip) {
                        final leftPosition = clip.startFrame * zoom * 5.0;
                        final clipWidth = clip.durationFrames * zoom * 5.0;
                        return Positioned(
                          left: leftPosition,
                          top: 0,
                          height: 60,
                          width: clipWidth.clamp(4.0, double.infinity),
                          child: TimelineClip(
                            clip: clip,
                            trackId: widget.track.id,
                          ),
                        );
                      }),
                      _DragPreview(
                        hoverPositionNotifier: hoverPositionNotifier,
                        candidateData: candidateData,
                        zoom: zoom,
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

  const _DragPreview({
    required this.hoverPositionNotifier,
    required this.candidateData,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final timelineViewModel = di<TimelineViewModel>();
    watch(hoverPositionNotifier);
    final Offset? hoverPositionValue = hoverPositionNotifier.value;

    if (hoverPositionValue == null || candidateData.isEmpty) {
      return const SizedBox.shrink();
    }

    final draggedClip = candidateData.first;
    if (draggedClip == null) return const SizedBox.shrink();

    final previewRawX = hoverPositionValue.dx;
    final frameAtCursor = (previewRawX / (5.0 * zoom)).floor();
    final nonNegativeFrame = frameAtCursor < 0 ? 0 : frameAtCursor;
    final previewLeftPosition = nonNegativeFrame * zoom * 5.0;
    final previewWidth = draggedClip.durationFrames * zoom * 5.0;

    return Stack(
      clipBehavior: fw.Clip.none,
      children: [
        Positioned(
          left: previewLeftPosition,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: theme.accentColor.lighter),
        ),
        Positioned(
          left: previewLeftPosition,
          top: 0,
          height: 60,
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
        Positioned(
          left: previewLeftPosition + previewWidth + 5,
          top: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              'Frame: ${timelineViewModel.calculateFramePositionFromDrop(previewRawX, getHorizontalScrollOffset(), zoom)}',
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  double getHorizontalScrollOffset() {
    final timelineViewModel = di<TimelineViewModel>();
    if (timelineViewModel.trackContentHorizontalScrollController.hasClients) {
      return timelineViewModel.trackContentHorizontalScrollController.offset;
    }
    return 0.0;
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
