import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/src/rust/video/timeline_composer.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';

class TimelineVideoPlayerWidget extends StatefulWidget {
  final List<ClipModel> clips;
  final TimelineNavigationViewModel timelineNavViewModel;
  
  const TimelineVideoPlayerWidget({
    super.key, 
    required this.clips,
    required this.timelineNavViewModel,
  });

  @override
  State<TimelineVideoPlayerWidget> createState() => _TimelineVideoPlayerWidgetState();
}

class _TimelineVideoPlayerWidgetState extends State<TimelineVideoPlayerWidget> {
  int? _timelineComposerHandle;
  final _textureRenderer = TextureRgbaRenderer();
  int? _textureId;
  int _textureKey = -1;
  bool _isInitialized = false;
  bool _hasValidTimeline = false; // Track if we have a valid timeline with clips
  String? _errorMessage;
  double _aspectRatio = 16 / 9;
  Timer? _frameTimer;
  Timer? _stateSyncTimer;
  
  String get _logTag => 'TimelineVideoPlayerWidget';
  
  @override
  void initState() {
    super.initState();
    _initializeTimelineComposer();
  }

  @override
  void didUpdateWidget(TimelineVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if clips have changed
    if (widget.clips != oldWidget.clips) {
      _updateTimelineClips();
    }
  }
  
  Future<void> _initializeTimelineComposer() async {
    try {
      logDebug("Initializing timeline composer", _logTag);
      
      // Create timeline composer instance
      _timelineComposerHandle = timelineComposerCreate();
      
      logDebug("Created timeline composer handle: $_timelineComposerHandle", _logTag);
      
      // Create texture
      _textureKey = DateTime.now().millisecondsSinceEpoch;
      final textureId = await _textureRenderer.createTexture(_textureKey);
      
      if (textureId == -1) {
        throw Exception("Failed to create texture");
      }
      
      logDebug("Created texture with ID: $textureId", _logTag);
      
      setState(() {
        _textureId = textureId;
      });
      
      // Get texture pointer and pass to Rust
      final texturePtr = await _textureRenderer.getTexturePtr(_textureKey);
      timelineComposerSetTexturePtr(handle: _timelineComposerHandle!, ptr: texturePtr);
      
      logDebug("Set texture pointer: $texturePtr", _logTag);
      
      if (texturePtr == 0) {
        throw Exception("Invalid texture pointer received");
      }
      
      // Update timeline with current clips
      await _updateTimelineClips();
      
      setState(() {
        _isInitialized = true;
      });
      
      // Start frame update timer
      _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        _updateTexture();
      });
      
      // Start state sync timer (only when we have a valid timeline)
      _stateSyncTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_hasValidTimeline) {
          _syncPlayingState();
        }
      });
      
      logDebug("Timeline composer initialized successfully", _logTag);
      
    } catch (e) {
      logError(_logTag, "Failed to initialize timeline composer: $e");
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }
  
  Future<void> _updateTimelineClips() async {
    if (!_isInitialized || _timelineComposerHandle == null) return;
    
    try {
      logDebug("Updating timeline with ${widget.clips.length} clips", _logTag);
      
      // Convert ClipModel objects to TimelineClipData
      final timelineClips = widget.clips
          .where((clip) => clip.type.name == 'video') // Only video clips for now
          .map((clip) => TimelineClipData(
                id: clip.databaseId ?? 0,
                trackId: clip.trackId,
                sourcePath: clip.sourcePath,
                startTimeOnTrackMs: clip.startTimeOnTrackMs,
                endTimeOnTrackMs: clip.endTimeOnTrackMs,
                startTimeInSourceMs: clip.startTimeInSourceMs,
                endTimeInSourceMs: clip.endTimeInSourceMs,
                sourceDurationMs: clip.sourceDurationMs,
              ))
          .toList();
      
      if (timelineClips.isNotEmpty) {
        logDebug("Converted to ${timelineClips.length} timeline clips:", _logTag);
        for (final clip in timelineClips) {
          logDebug("  Clip ${clip.id}: ${clip.sourcePath} (${clip.startTimeOnTrackMs}-${clip.endTimeOnTrackMs}ms)", _logTag);
        }
        
        await timelineComposerUpdateTimeline(handle: _timelineComposerHandle!, clips: timelineClips);
        setState(() {
          _hasValidTimeline = true;
        });
        logDebug("Timeline updated with ${timelineClips.length} video clips", _logTag);
      } else {
        setState(() {
          _hasValidTimeline = false;
        });
        logDebug("No video clips to update in timeline", _logTag);
      }
    } catch (e) {
      logError(_logTag, "Failed to update timeline clips: $e");
      setState(() {
        _errorMessage = "Failed to update timeline: $e";
        _hasValidTimeline = false;
      });
    }
  }
  
  void _updateTexture() {
    if (!_isInitialized || _timelineComposerHandle == null || !_hasValidTimeline) return;
    
    try {
      final frameData = timelineComposerGetLatestFrame(handle: _timelineComposerHandle!);
      if (frameData != null && _textureId != null) {
        logDebug("Updating texture with frame: ${frameData.width}x${frameData.height}, ${frameData.data.length} bytes", _logTag);
        
        _textureRenderer.onRgba(
          _textureKey,
          Uint8List.fromList(frameData.data),
          frameData.height,
          frameData.width,
          1,
        );
        
        final newAspectRatio = frameData.width / frameData.height;
        if (_aspectRatio != newAspectRatio) {
          setState(() {
            _aspectRatio = newAspectRatio;
          });
          logDebug("Updated aspect ratio to: $newAspectRatio", _logTag);
        }
      } else if (frameData == null) {
        // logDebug("No frame data available", _logTag); // Comment out to avoid spam
      }
    } catch (e) {
      logError(_logTag, "Error updating texture: $e");
    }
  }
  
  void _syncPlayingState() {
    if (!_isInitialized || _timelineComposerHandle == null || !_hasValidTimeline) return;
    
    try {
      final rustIsPlaying = timelineComposerIsPlaying(handle: _timelineComposerHandle!);
      final dartIsPlaying = widget.timelineNavViewModel.isPlaying;
      
      if (rustIsPlaying != dartIsPlaying) {
        if (dartIsPlaying) {
          timelineComposerPlay(handle: _timelineComposerHandle!);
        } else {
          timelineComposerPause(handle: _timelineComposerHandle!);
        }
      }
      
      // Update current position
      final currentTimeMs = timelineComposerGetPosition(handle: _timelineComposerHandle!);
      final currentFrame = ClipModel.msToFrames(currentTimeMs);
      
      // Update timeline navigation if needed (avoid infinite loops)
      if (widget.timelineNavViewModel.currentFrame != currentFrame && dartIsPlaying) {
        widget.timelineNavViewModel.currentFrame = currentFrame;
      }
      
      // Only seek if position has changed significantly and we're not currently playing
      // This avoids frequent seeks during playback which can cause issues
      if (!dartIsPlaying) {
        final expectedTimeMs = ClipModel.framesToMs(widget.timelineNavViewModel.currentFrame);
        final timeDifference = (currentTimeMs - expectedTimeMs).abs();
        
        // Only seek if difference is significant (> 500ms) to avoid constant seeking
        if (timeDifference > 500) {
          logDebug("Position sync: current=${currentTimeMs}ms, expected=${expectedTimeMs}ms, diff=${timeDifference}ms", _logTag);
          
          // Validate the seek position is reasonable
          if (expectedTimeMs >= 0) {
            timelineComposerSeek(handle: _timelineComposerHandle!, positionMs: expectedTimeMs).catchError((error) {
              logError(_logTag, "Seek failed: $error");
              // Don't mark timeline as invalid for seek failures, just log and continue
            });
          }
        }
      }
    } catch (e) {
      logError(_logTag, "Error syncing playing state: $e");
      // Only mark timeline as invalid if it's a critical error, not just seek failures
      if (e.toString().contains("No timeline pipeline available") || 
          e.toString().contains("Failed to send") ||
          e.toString().contains("Failed to receive")) {
        setState(() {
          _hasValidTimeline = false;
        });
      }
    }
  }
  
  @override
  void dispose() {
    logDebug("Disposing timeline video player widget", _logTag);
    
    _frameTimer?.cancel();
    _stateSyncTimer?.cancel();
    
    try {
      if (_timelineComposerHandle != null) {
        timelineComposerDispose(handle: _timelineComposerHandle!);
      }
    } catch (e) {
      logError(_logTag, "Error disposing timeline composer: $e");
    }
    
    if (_textureId != null) {
      _textureRenderer.closeTexture(_textureKey);
    }
    
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red.withOpacity(0.7),
              ),
              const SizedBox(height: 16),
              Text(
                'Timeline Playback Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    if (!_isInitialized || _textureId == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Colors.white.withOpacity(0.7),
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Initializing Timeline Player...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: Texture(textureId: _textureId!),
        ),
      ),
    );
  }
} 