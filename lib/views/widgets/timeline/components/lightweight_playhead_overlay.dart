import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:async';

class LightweightPlayheadOverlay extends StatefulWidget {
  final double zoom;
  final double trackLabelWidth;
  final double timelineHeight;
  final ScrollController scrollController;

  const LightweightPlayheadOverlay({
    super.key,
    required this.zoom,
    required this.trackLabelWidth,
    required this.timelineHeight,
    required this.scrollController,
  });

  @override
  State<LightweightPlayheadOverlay> createState() => _LightweightPlayheadOverlayState();
}

class _LightweightPlayheadOverlayState extends State<LightweightPlayheadOverlay> {
  late VideoPlayerService _videoPlayerService;
  bool _isDragging = false;
  double _dragPosition = 0.0;
  bool _wasPlayingBeforeDrag = false;
  Timer? _updateThrottleTimer;
  Timer? _resumeUpdatesTimer;
  int _lastRenderedFrame = -1;
  bool _ignorePositionUpdates = false;

  @override
  void initState() {
    super.initState();
    _videoPlayerService = di<VideoPlayerService>();
  }

  @override
  void dispose() {
    _updateThrottleTimer?.cancel();
    _resumeUpdatesTimer?.cancel();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    _wasPlayingBeforeDrag = _videoPlayerService.isPlaying;
    if (_wasPlayingBeforeDrag) {
      // Pause playback during drag
      _videoPlayerService.activeVideoPlayer?.pause();
    }
    
    setState(() {
      _isDragging = true;
      _ignorePositionUpdates = true; // Ignore position updates during drag
      _dragPosition = _calculateFrameFromPosition(details.globalPosition.dx);
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isDragging) {
      // Throttle drag updates to reduce rebuilds
      _updateThrottleTimer?.cancel();
      _updateThrottleTimer = Timer(const Duration(milliseconds: 16), () {
        if (mounted && _isDragging) {
          setState(() {
            _dragPosition = _calculateFrameFromPosition(details.globalPosition.dx);
          });
        }
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isDragging) {
      _updateThrottleTimer?.cancel();
      
      // Seek to final position
      final frameNumber = _dragPosition.round();
      _videoPlayerService.seekToFrame(frameNumber);
      
      setState(() {
        _isDragging = false;
        // Keep ignoring position updates briefly to prevent snapback
        _ignorePositionUpdates = true;
      });
      
      // Resume position updates after a short delay to allow Rust to update
      _resumeUpdatesTimer?.cancel();
      _resumeUpdatesTimer = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _ignorePositionUpdates = false;
          });
        }
      });
      
      // Resume playback if it was playing before
      if (_wasPlayingBeforeDrag) {
        _videoPlayerService.activeVideoPlayer?.play();
      }
    }
  }

  double _calculateFrameFromPosition(double globalX) {
    // Get the render box to convert global to local coordinates
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return 0.0;
    
    final localPosition = renderBox.globalToLocal(Offset(globalX, 0));
    const double framePixelWidth = 5.0;
    final double pxPerFrame = framePixelWidth * widget.zoom;
    
    // Account for scroll offset and track label width
    final scrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    final adjustedPosition = (localPosition.dx + scrollOffset - widget.trackLabelWidth).clamp(0.0, double.infinity);
    
    return adjustedPosition / pxPerFrame;
  }

  double _calculatePositionFromFrame(int frame) {
    const double framePixelWidth = 5.0;
    final double pxPerFrame = framePixelWidth * widget.zoom;
    
    // Account for scroll offset
    final scrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    return widget.trackLabelWidth + (frame * pxPerFrame) - scrollOffset;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _PlayheadRenderer(
        videoPlayerService: _videoPlayerService,
        zoom: widget.zoom,
        trackLabelWidth: widget.trackLabelWidth,
        timelineHeight: widget.timelineHeight,
        isDragging: _isDragging,
        dragPosition: _dragPosition,
        ignorePositionUpdates: _ignorePositionUpdates,
        onDragStart: _handleDragStart,
        onDragUpdate: _handleDragUpdate,
        onDragEnd: _handleDragEnd,
        calculatePositionFromFrame: _calculatePositionFromFrame,
        lastRenderedFrame: _lastRenderedFrame,
        onFrameRendered: (frame) => _lastRenderedFrame = frame,
      ),
    );
  }
}

class _PlayheadRenderer extends StatelessWidget with WatchItMixin {
  final VideoPlayerService videoPlayerService;
  final double zoom;
  final double trackLabelWidth;
  final double timelineHeight;
  final bool isDragging;
  final double dragPosition;
  final bool ignorePositionUpdates;
  final Function(DragStartDetails) onDragStart;
  final Function(DragUpdateDetails) onDragUpdate;
  final Function(DragEndDetails) onDragEnd;
  final Function(int) calculatePositionFromFrame;
  final int lastRenderedFrame;
  final Function(int) onFrameRendered;

  const _PlayheadRenderer({
    required this.videoPlayerService,
    required this.zoom,
    required this.trackLabelWidth,
    required this.timelineHeight,
    required this.isDragging,
    required this.dragPosition,
    required this.ignorePositionUpdates,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.calculatePositionFromFrame,
    required this.lastRenderedFrame,
    required this.onFrameRendered,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    // Determine current frame based on state
    int currentFrame;
    if (isDragging) {
      // Use drag position when dragging
      currentFrame = dragPosition.round();
    } else if (ignorePositionUpdates) {
      // Use last rendered frame when ignoring updates (prevents snapback)
      currentFrame = lastRenderedFrame;
    } else {
      // Use live position from Rust when not dragging and not ignoring
      currentFrame = watchValue((VideoPlayerService service) => service.currentFrameNotifier);
    }

    // Always render if we have a valid frame (remove optimization that might cause disappearing)
    onFrameRendered(currentFrame);

    final playheadPosition = isDragging 
        ? (trackLabelWidth + (dragPosition * 5.0 * zoom))
        : calculatePositionFromFrame(currentFrame);

    // Don't render if position is off-screen
    if (playheadPosition < trackLabelWidth || playheadPosition < 0) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned(
          left: playheadPosition - 6, // Position for wider hit area
          top: 0,
          child: GestureDetector(
            onPanStart: onDragStart,
            onPanUpdate: onDragUpdate,
            onPanEnd: onDragEnd,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 12,
                height: timelineHeight,
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: timelineHeight,
                  decoration: BoxDecoration(
                    color: theme.accentColor,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withOpacity(0.3),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
} 