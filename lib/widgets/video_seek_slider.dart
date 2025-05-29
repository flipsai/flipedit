import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/utils/logger.dart';

class VideoSeekSlider extends StatefulWidget {
  final VideoPlayer videoPlayer;
  final Function(double)? onSeek;
  final bool useFrameBasedSeeking; // Option for frame-accurate seeking
  
  const VideoSeekSlider({
    super.key,
    required this.videoPlayer,
    this.onSeek,
    this.useFrameBasedSeeking = true, // Default to frame-based for accuracy
  });

  @override
  State<VideoSeekSlider> createState() => _VideoSeekSliderState();
}

class _VideoSeekSliderState extends State<VideoSeekSlider> {
  double _currentPosition = 0.0;
  double _duration = 0.0;
  bool _isDragging = false;
  double _dragPosition = 0.0; // Track the position while dragging
  Timer? _positionTimer;
  double _frameRate = 25.0; // Cache frame rate
  int _totalFrames = 0;
  bool _wasPlayingBeforeDrag = false; // Track if video was playing before drag started
  Timer? _previewTimer; // Timer for debounced preview
  double? _pendingPreviewPosition; // Store pending preview position
  bool _isPreviewSeeking = false; // Prevent concurrent preview seeks

  String get _logTag => 'VideoSeekSlider';

  @override
  void initState() {
    super.initState();
    _startPositionUpdater();
    _initializeFrameInfo();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _previewTimer?.cancel(); // Cancel preview timer
    super.dispose();
  }

  void _startPositionUpdater() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isDragging) return;
      
      try {
        final position = widget.videoPlayer.getPositionSeconds();
        final duration = widget.videoPlayer.getDurationSeconds();
        
        // Update frame info periodically in case it changes after video loads
        final currentFrameRate = widget.videoPlayer.getFrameRate();
        final currentTotalFrames = widget.videoPlayer.getTotalFrames().toInt();
        
        // Check if frame rate or total frames changed
        if (currentFrameRate != _frameRate || currentTotalFrames != _totalFrames) {
          _frameRate = currentFrameRate;
          _totalFrames = currentTotalFrames;
          logDebug("Updated video info: ${_frameRate.toStringAsFixed(2)} fps, $_totalFrames total frames (duration: ${duration.toStringAsFixed(2)}s)", _logTag);
        }
        
        setState(() {
          _currentPosition = position;
          _duration = duration;
        });
      } catch (e) {
        logError(_logTag, "Error updating position: $e");
      }
    });
  }

  void _initializeFrameInfo() {
    // Get frame rate and total frames
    _frameRate = widget.videoPlayer.getFrameRate();
    _totalFrames = widget.videoPlayer.getTotalFrames().toInt();
    logDebug("Video info: ${_frameRate.toStringAsFixed(2)} fps, $_totalFrames total frames", _logTag);
  }

  String _formatTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds < 0) {
      return "0:00";
    }
    
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).floor();
    return "$minutes:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  String _formatFrameInfo(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds < 0) {
      return "Frame 0";
    }
    
    final frameNumber = (seconds * _frameRate).round();
    return "Frame $frameNumber";
  }

  void _onSliderChanged(double value) {
    // If this is the start of dragging, record initial state and pause video
    if (!_isDragging) {
      _wasPlayingBeforeDrag = widget.videoPlayer.isPlaying();
      logDebug("Starting drag - video was ${_wasPlayingBeforeDrag ? 'playing' : 'paused'}", _logTag);
      
      _isDragging = true;
      
      // ONLY pause if the video was actually playing
      // Avoid unnecessary pause operations on already paused video
      if (_wasPlayingBeforeDrag) {
        logDebug("Pausing playing video for drag...", _logTag);
        widget.videoPlayer.pause().then((_) {
          logDebug("Video paused successfully for dragging", _logTag);
        }).catchError((e) {
          logError(_logTag, "Error pausing during drag start: $e");
        });
      } else {
        logDebug("Video already paused - no pause needed for drag", _logTag);
        // Video is already paused, don't touch the pipeline state
      }
    }
    
    // Update drag position immediately for responsive UI
    setState(() {
      _dragPosition = value;
    });

    logDebug("Dragging to ${_formatTime(value)} (${_formatFrameInfo(value)}) - video was ${_wasPlayingBeforeDrag ? 'playing' : 'paused'}", _logTag);
    
    // Schedule frame preview while dragging
    _schedulePreview(value);
  }

  void _schedulePreview(double value) {
    // Store the latest position for preview
    _pendingPreviewPosition = value;
    
    // Cancel any existing preview timer
    _previewTimer?.cancel();
    
    // Schedule frame extraction every 300ms during drag (reduced frequency to prevent overload)
    _previewTimer = Timer(const Duration(milliseconds: 300), () {
      if (_pendingPreviewPosition != null && _isDragging && !_isPreviewSeeking) {
        final previewPosition = _pendingPreviewPosition!;
        final targetFrame = (previewPosition * _frameRate).round();
        logDebug("Extracting frame at ${_formatTime(previewPosition)} (Frame $targetFrame)", _logTag);
        
        _isPreviewSeeking = true; // Mark as extracting
        
        // Use the new extract_frame_at_position method which doesn't seek the main pipeline
        // This creates a temporary pipeline to extract the frame and updates the texture display
        // The main pipeline stays at its current position, and Flutter picks up the extracted frame
        // through the normal getLatestFrame() calls in the video player widget
        widget.videoPlayer.extractFrameAtPosition(
          seconds: previewPosition
        ).timeout(
          const Duration(milliseconds: 500), // Longer timeout since this is more complex
          onTimeout: () {
            logWarning(_logTag, "Frame extraction timeout at ${_formatTime(previewPosition)} - continuing");
            return; // Return void on timeout
          },
        ).then((_) {
          if (_isDragging) {
            logDebug("Frame extraction completed at ${_formatTime(previewPosition)}", _logTag);
          }
        }).catchError((e) {
          if (_isDragging) {
            logError(_logTag, "Frame extraction error: $e - continuing");
          }
        }).whenComplete(() {
          _isPreviewSeeking = false; // Always reset the flag
          // Continue scheduling next preview if still dragging and position changed
          if (_isDragging && _pendingPreviewPosition != null) {
            _schedulePreview(_pendingPreviewPosition!);
          }
        });
        
        _pendingPreviewPosition = null;
      } else if (_isDragging && _pendingPreviewPosition != null) {
        // If we can't extract now but still dragging, reschedule
        _schedulePreview(_pendingPreviewPosition!);
      }
    });
  }

  void _onSliderChangeEnd(double value) {
    logDebug("Drag ended at ${_formatTime(value)} (${_formatFrameInfo(value)})", _logTag);
    // Cancel any pending preview operations
    _previewTimer?.cancel();
    _pendingPreviewPosition = null;
    _isPreviewSeeking = false; // Reset preview seeking flag
    
    // Perform final seek with proper pause/resume control
    // Note: Preview seeks always pause, so we need to restore the original state
    final seekFuture = widget.videoPlayer.seekAndPauseControl(
      seconds: value, 
      wasPlayingBefore: _wasPlayingBeforeDrag // Restore original playing state
    );
    
    // Add timeout to prevent infinite hang
    seekFuture.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        logError(_logTag, "TIMEOUT: Seek operation timed out after 5 seconds!");
        return value; // Return the target position as fallback
      },
    ).then((actualPosition) {
      logDebug("Final seek completed at ${_formatTime(actualPosition)}", _logTag);
      
      // Wait a moment for state to stabilize, then check actual playing state
      Future.delayed(const Duration(milliseconds: 100), () async {
        final actualPlayingState = await widget.videoPlayer.syncPlayingState();
        logDebug("Post-seek state verification - Expected playing: $_wasPlayingBeforeDrag, Actual playing: $actualPlayingState", _logTag);
        
        if (_wasPlayingBeforeDrag != actualPlayingState) {
          logWarning(_logTag, "Playing state mismatch after seek!");
          // Try to correct the state
          if (_wasPlayingBeforeDrag && !actualPlayingState) {
            logDebug("Attempting to resume playback...", _logTag);
            widget.videoPlayer.play().catchError((e) {
              logError(_logTag, "Failed to resume playback: $e");
            });
          }
        }
      });
      
      setState(() {
        _isDragging = false;
        _currentPosition = actualPosition; // Use the actual position returned
      });
      
      // Notify callback
      widget.onSeek?.call(actualPosition);
    }).catchError((e) {
      logError(_logTag, "Error during final seek: $e");
      setState(() {
        _isDragging = false;
        _currentPosition = value; // Use target position as fallback
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSeekable = widget.videoPlayer.isSeekable();
    final maxValue = _duration > 0 ? _duration : 1.0;
    
    // Use drag position when dragging, otherwise use current position
    final displayPosition = _isDragging ? _dragPosition : _currentPosition;
    final currentValue = displayPosition.clamp(0.0, maxValue);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black.withOpacity(0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time display - shows real-time position while dragging
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(displayPosition),
                    style: TextStyle(
                      color: _isDragging ? Colors.yellow : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.useFrameBasedSeeking)
                    Text(
                      _formatFrameInfo(displayPosition),
                      style: TextStyle(
                        color: _isDragging ? Colors.yellow.withOpacity(0.8) : Colors.white.withOpacity(0.7),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(_duration),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.useFrameBasedSeeking)
                    Text(
                      "Total: $_totalFrames frames",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          
          // Seek slider
          Slider(
            value: currentValue,
            min: 0.0,
            max: maxValue,
            onChanged: isSeekable ? _onSliderChanged : null,
            onChangeEnd: isSeekable ? _onSliderChangeEnd : null,
            style: SliderThemeData(
              useThumbBall: false,
              trackHeight: WidgetStateProperty.all(3.0),
              thumbRadius: WidgetStateProperty.all(8.0),
              activeColor: WidgetStateProperty.all(_isDragging ? Colors.yellow : Colors.red),
              inactiveColor: WidgetStateProperty.all(Colors.white.withOpacity(0.24)),
            ),
          ),
          
          // Seekability indicator
          if (!isSeekable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Seeking not available',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                ),
              ),
            ),
          
          // Status indicators
          if (isSeekable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDragging) ...[
                    Icon(
                      FluentIcons.camera,
                      color: Colors.yellow,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _wasPlayingBeforeDrag ? 'Extracting frames (will resume)' : 'Extracting frames (staying paused)',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 10,
                      ),
                    ),
                  ] else if (widget.useFrameBasedSeeking) ...[
                    Icon(
                      FluentIcons.video,
                      color: Colors.green,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Frame-accurate @ ${_frameRate.toStringAsFixed(1)} fps',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
