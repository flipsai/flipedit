import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:async';

class Playhead extends StatefulWidget {
  final double zoom;
  final double trackLabelWidth;
  final double timelineHeight;
  final ScrollController scrollController;

  const Playhead({
    super.key,
    required this.zoom,
    required this.trackLabelWidth,
    required this.timelineHeight,
    required this.scrollController,
  });

  @override
  State<Playhead> createState() => _PlayheadState();
}

class _PlayheadState extends State<Playhead> {
  late VideoPlayerService _videoPlayerService;
  bool _isDragging = false;
  double _dragPosition = 0.0;
  bool _wasPlayingBeforeDrag = false;
  Timer? _updateThrottleTimer;
  Timer? _resumeUpdatesTimer;
  int _lastRenderedFrame = -1;
  bool _ignorePositionUpdates = false;
  StreamSubscription<int>? _seekCompletionSubscription;
  
  // Add scroll listener for position updates
  VoidCallback? _scrollListener;
  
  // Cache expensive calculations during drag
  RenderBox? _cachedRenderBox;
  double _cachedScrollOffset = 0.0;
  double _cachedPxPerFrame = 0.0;
  
  // Throttle scroll updates
  Timer? _scrollUpdateTimer;
  static const Duration _scrollUpdateThrottle = Duration(milliseconds: 16); // ~60fps

  @override
  void initState() {
    super.initState();
    _videoPlayerService = di<VideoPlayerService>();
    
    // Listen to scroll changes to update playhead position (throttled)
    _scrollListener = () {
      if (mounted && !_isDragging) {
        _scrollUpdateTimer?.cancel();
        _scrollUpdateTimer = Timer(_scrollUpdateThrottle, () {
          if (mounted && !_isDragging) {
            setState(() {
              // Force rebuild when scroll position changes
            });
          }
        });
      }
    };
    
    widget.scrollController.addListener(_scrollListener!);
    
    // Set up seek completion listener
    _setupSeekCompletionListener();
  }

  @override
  void dispose() {
    _updateThrottleTimer?.cancel();
    _resumeUpdatesTimer?.cancel();
    _scrollUpdateTimer?.cancel();
    _seekCompletionSubscription?.cancel();
    
    // Remove scroll listener
    if (_scrollListener != null) {
      widget.scrollController.removeListener(_scrollListener!);
    }
    
    // Remove seek completion listener
    _videoPlayerService.seekCompletionNotifier.removeListener(_onSeekCompleted);
    
    super.dispose();
  }

  @override
  void didUpdateWidget(Playhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle scroll controller changes
    if (oldWidget.scrollController != widget.scrollController) {
      if (_scrollListener != null) {
        oldWidget.scrollController.removeListener(_scrollListener!);
        widget.scrollController.addListener(_scrollListener!);
      }
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _wasPlayingBeforeDrag = _videoPlayerService.isPlaying;
    if (_wasPlayingBeforeDrag) {
      // Pause playback during drag
      _videoPlayerService.activePlayer?.pause();
    }
    
    // Cache expensive calculations for drag performance
    _cachedRenderBox = context.findRenderObject() as RenderBox?;
    _cachedScrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    const double framePixelWidth = 5.0;
    _cachedPxPerFrame = framePixelWidth * widget.zoom;
    
    setState(() {
      _isDragging = true;
      _ignorePositionUpdates = true; // Ignore position updates during drag
      _dragPosition = _calculateFrameFromPositionCached(details.globalPosition.dx);
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isDragging) {
      // Direct update without throttling for smooth dragging
      setState(() {
        _dragPosition = _calculateFrameFromPositionCached(details.globalPosition.dx);
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
        // Keep ignoring position updates until seek completes
        _ignorePositionUpdates = true;
      });
      
      // Clear cached values
      _cachedRenderBox = null;
      _cachedScrollOffset = 0.0;
      _cachedPxPerFrame = 0.0;
      
      // Position updates will resume when seek completion is received
      // No need for fixed timer anymore
    }
  }


  double _calculatePositionFromFrame(int frame) {
    const double framePixelWidth = 5.0;
    final double pxPerFrame = framePixelWidth * widget.zoom;
    
    // Account for scroll offset since we're outside the scrollable area
    final scrollOffset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
    return widget.trackLabelWidth + (frame * pxPerFrame) - scrollOffset;
  }

  double _calculateFrameFromPositionCached(double globalX) {
    // Get our own render box to convert global to local coordinates
    final RenderBox? renderBox = _cachedRenderBox;
    if (renderBox == null) return 0.0;
    
    // Convert global coordinates to our local coordinates
    final localPosition = renderBox.globalToLocal(Offset(globalX, 0));
    
    // The local position is relative to our overlay widget
    // We need to subtract trackLabelWidth to get position relative to timeline content
    // Then add scrollOffset to account for the current scroll position
    final timelineContentX = localPosition.dx - widget.trackLabelWidth + _cachedScrollOffset;
    final adjustedPosition = timelineContentX.clamp(0.0, double.infinity);
    
    return adjustedPosition / _cachedPxPerFrame;
  }

  void _setupSeekCompletionListener() {
    // Listen for seek completion events from the video player service
    _videoPlayerService.seekCompletionNotifier.addListener(_onSeekCompleted);
  }

  void _onSeekCompleted() {
    // Resume position updates when seek completes
    if (mounted) {
      setState(() {
        _ignorePositionUpdates = false;
      });
    }
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

class _PlayheadRenderer extends StatefulWidget {
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
  State<_PlayheadRenderer> createState() => _PlayheadRendererState();
}

class _PlayheadRendererState extends State<_PlayheadRenderer> {
  Timer? _frameUpdateTimer;
  int _lastWatchedFrame = -1;
  static const Duration _frameUpdateThrottle = Duration(milliseconds: 33); // ~30fps
  VoidCallback? _frameListener;

  @override
  void initState() {
    super.initState();
    _setupFrameListener();
  }

  void _setupFrameListener() {
    _frameListener = () {
      final frame = widget.videoPlayerService.currentFrameNotifier.value;
      if (frame != _lastWatchedFrame && !widget.isDragging && !widget.ignorePositionUpdates) {
        _frameUpdateTimer?.cancel();
        _frameUpdateTimer = Timer(_frameUpdateThrottle, () {
          if (mounted) {
            setState(() {
              _lastWatchedFrame = frame;
            });
          }
        });
      }
    };
    
    widget.videoPlayerService.currentFrameNotifier.addListener(_frameListener!);
  }

  @override
  void dispose() {
    _frameUpdateTimer?.cancel();
    if (_frameListener != null) {
      widget.videoPlayerService.currentFrameNotifier.removeListener(_frameListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    
    // Determine current frame based on state
    int currentFrame;
    if (widget.isDragging) {
      // Use drag position when dragging
      currentFrame = widget.dragPosition.round();
    } else if (widget.ignorePositionUpdates) {
      // Use last rendered frame when ignoring updates (prevents snapback)
      currentFrame = widget.lastRenderedFrame;
    } else {
      // Use cached frame value (throttled updates)
      currentFrame = _lastWatchedFrame >= 0 ? _lastWatchedFrame : widget.videoPlayerService.currentFrameNotifier.value;
    }

    // Always render if we have a valid frame (remove optimization that might cause disappearing)
    widget.onFrameRendered(currentFrame);

    final playheadPosition = widget.calculatePositionFromFrame(currentFrame);

    // Don't render if position is off-screen
    if (playheadPosition < widget.trackLabelWidth || playheadPosition < 0) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned(
          left: playheadPosition - 6, // Position for wider hit area
          top: 0,
          child: GestureDetector(
            onPanStart: widget.onDragStart,
            onPanUpdate: widget.onDragUpdate,
            onPanEnd: widget.onDragEnd,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: Container(
                width: 12,
                height: widget.timelineHeight,
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: widget.timelineHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.3),
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