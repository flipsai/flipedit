import 'dart:async';
import 'dart:io'; // Added for File access
import 'dart:ui'; // Required for lerpDouble

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

const double _defaultFrameRate = 30.0;
const int _defaultTimelineDurationFrames = 90; // Default 3 seconds at 30fps

// Simple debounce utility
void Function() _debounce(VoidCallback func, Duration delay) {
  Timer? debounceTimer;
  return () {
    debounceTimer?.cancel();
    debounceTimer = Timer(delay, func);
  };
}

class TimelineViewModel implements Disposable {
  final ValueNotifier<List<Clip>> clipsNotifier = ValueNotifier<List<Clip>>([]);
  List<Clip> get clips => List.unmodifiable(clipsNotifier.value);

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    if (zoomNotifier.value == value || value < 0.1 || value > 5.0) return;
    zoomNotifier.value = value;
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final clampedValue = value.clamp(0, _totalFrames);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;

    // If playing via timer, pause it when manually seeking
    if (_playbackTimer?.isActive ?? false) {
       _stopPlaybackTimer();
       // Optional: Decide if seeking should resume playback. Currently, it stops.
       isPlayingNotifier.value = false; 
    }

    _seekControllerToFrame(clampedValue);
  }

  int _totalFrames = 0;
  int get totalFrames => _totalFrames;
  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  VideoPlayerController? _videoPlayerController;
  VideoPlayerController? get videoPlayerController => _videoPlayerController;
  final ValueNotifier<VideoPlayerController?> videoPlayerControllerNotifier =
      ValueNotifier<VideoPlayerController?>(null);

  // Scroll Controllers for synchronized scrolling
  final ScrollController trackLabelScrollController = ScrollController();
  final ScrollController trackContentScrollController = ScrollController();

  // Flags to prevent recursive listener calls
  bool _isSyncingLabels = false;
  bool _isSyncingContent = false;

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;

  // Debounce the frame update from timer to avoid excessive state changes
  late final VoidCallback _debouncedFrameUpdate;

  TimelineViewModel() {
    // Setup scroll synchronization listeners
    _setupScrollSync();
    _recalculateTotalFrames(); // Initialize total frames

    // Initialize debounced frame update
    _debouncedFrameUpdate = _debounce(() {
      if (!isPlayingNotifier.value) return; // Check if still playing

      final nextFrame = currentFrame + 1;
      if (nextFrame <= _totalFrames) {
        currentFrameNotifier.value = nextFrame; // Update frame directly
        // Restart timer for next frame if not at the end
        if (nextFrame < _totalFrames) {
          _startPlaybackTimer(); 
        } else {
          // Reached end, stop playback
          _stopPlaybackTimer();
          isPlayingNotifier.value = false;
        }
      } else {
        // Should not happen if check above is correct, but safety stop
        _stopPlaybackTimer();
        isPlayingNotifier.value = false;
      }
    }, Duration(milliseconds: (1000 / _defaultFrameRate).round()));
  }

  void _setupScrollSync() {
    // Debounced functions to avoid excessive updates during fast scrolls
    final debouncedSyncToContent = _debounce(() {
      if (!_isSyncingLabels &&
          trackLabelScrollController.hasClients &&
          trackContentScrollController.hasClients) {
        _isSyncingContent = true;
        trackContentScrollController
            .jumpTo(trackLabelScrollController.offset);
        // Use Future.delayed to reset the flag after the jump completes
        Future.delayed(Duration.zero, () => _isSyncingContent = false);
      }
    }, const Duration(milliseconds: 10)); // Short debounce delay

    final debouncedSyncToLabels = _debounce(() {
      if (!_isSyncingContent &&
          trackContentScrollController.hasClients &&
          trackLabelScrollController.hasClients) {
        _isSyncingLabels = true;
        trackLabelScrollController
            .jumpTo(trackContentScrollController.offset);
        // Use Future.delayed to reset the flag after the jump completes
        Future.delayed(Duration.zero, () => _isSyncingLabels = false);
      }
    }, const Duration(milliseconds: 10)); // Short debounce delay

    trackLabelScrollController.addListener(debouncedSyncToContent);
    trackContentScrollController.addListener(debouncedSyncToLabels);
  }

  Future<void> loadVideo(String videoPath) async {
    await _videoPlayerController?.dispose();
    _controllerPositionSubscription?.cancel();

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      ),
    );

    try {
      await _videoPlayerController!.initialize();
      _videoPlayerController!.setLooping(false);

      _recalculateTotalFrames(); // Recalculate based on video potentially
      currentFrame = 0;

      _videoPlayerController!.addListener(_updateFrameFromController);
      videoPlayerControllerNotifier.value = _videoPlayerController;

      // Stop timer playback if video takes over
      _stopPlaybackTimer();
      isPlayingNotifier.value = false; 

      print('Video loaded. Total frames: $_totalFrames');
    } catch (e) {
      print("Error initializing video player: $e");
      _videoPlayerController = null;
      videoPlayerControllerNotifier.value = null;
      _totalFrames = 0;
      totalFramesNotifier.value = _totalFrames;
    }
    isPlayingNotifier.value = false;
  }

  void _updateFrameFromController() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return;
    }

    final position = _videoPlayerController!.value.position;
    final frame = (position.inMilliseconds * _defaultFrameRate / 1000).round();

    if (currentFrameNotifier.value != frame && frame <= _totalFrames) {
      currentFrameNotifier.value = frame;
    }

    if (isPlayingNotifier.value != _videoPlayerController!.value.isPlaying) {
      isPlayingNotifier.value = _videoPlayerController!.value.isPlaying;
    }
  }

  void _seekControllerToFrame(int frame) {
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      final targetPosition = Duration(
        milliseconds: (frame * 1000 / _defaultFrameRate).round(),
      );
      final currentPosition = _videoPlayerController!.value.position;
      if ((targetPosition - currentPosition).abs() >
          const Duration(milliseconds: 50)) {
        _videoPlayerController!.seekTo(targetPosition);
      }
    }
  }

  void addClip(Clip clip) {
    final newClips = List<Clip>.from(clipsNotifier.value)..add(clip);
    clipsNotifier.value = newClips;
    _recalculateTotalFrames();

    if (_videoPlayerController == null && clip.type == ClipType.video) {
      // Stop timer playback before loading video
      _stopPlaybackTimer(); 
      isPlayingNotifier.value = false;
      loadVideo(clip.filePath);
    }
  }

  int calculateFramePositionFromDrop(
    double localPositionX,
    double scrollOffsetX,
    double zoom,
  ) {
    final adjustedPosition = localPositionX + scrollOffsetX;
    final frameWidth = 5.0 * zoom;

    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  void addClipAtPosition(
    Clip clip, {
    double? localPositionX,
    double? scrollOffsetX,
  }) {
    int targetFrame = currentFrame;

    if (localPositionX != null && scrollOffsetX != null) {
      targetFrame = calculateFramePositionFromDrop(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
    }

    final newClip = clip.copyWith(startFrame: targetFrame);
    addClip(newClip);
  }

  void removeClip(String clipId) {
    if (clipId.isEmpty) return;

    final initialLength = clipsNotifier.value.length;
    final newClips =
        clipsNotifier.value.where((clip) => clip.id != clipId).toList();

    if (newClips.length != initialLength) {
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();

      if (clipsNotifier.value.isEmpty ||
          clipsNotifier.value.every((c) => c.type != ClipType.video)) {
        _unloadVideo();
      }
    }
  }

  void updateClip(String clipId, Clip updatedClip) {
    if (clipId.isEmpty) return;

    final index = clipsNotifier.value.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      final newClips = List<Clip>.from(clipsNotifier.value);
      newClips[index] = updatedClip;
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();
    }
  }

  void moveClip(String clipId, int newStartFrame) {
    if (clipId.isEmpty || newStartFrame < 0) return;

    final index = clipsNotifier.value.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      final clip = clipsNotifier.value[index];
      if (clip.startFrame == newStartFrame) return;

      final updatedClip = clip.copyWith(startFrame: newStartFrame);
      final newClips = List<Clip>.from(clipsNotifier.value);
      newClips[index] = updatedClip;
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();
    }
  }

  void seekTo(int frame) {
    currentFrame = frame;
  }

  void togglePlayback() {
    // Case 1: Video controller exists and is initialized
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      if (_videoPlayerController!.value.isPlaying) {
        _videoPlayerController!.pause();
      } else {
        // If paused at the end, seek to start before playing
        if (currentFrame >= _totalFrames) {
           currentFrame = 0; // Seek to beginning
        }
        _seekControllerToFrame(currentFrame); // Ensure controller matches frame
        _videoPlayerController!.play();
      }
      isPlayingNotifier.value = _videoPlayerController!.value.isPlaying;
    } 
    // Case 2: No video controller, use timer
    else if (_totalFrames > 0) { // Only play if there's some duration
       if (isPlayingNotifier.value) {
         // Currently playing with timer, so pause
         _stopPlaybackTimer();
         isPlayingNotifier.value = false;
       } else {
         // Currently paused or stopped, start timer playback
         // If paused at the end, seek to start before playing
         if (currentFrame >= _totalFrames) {
           currentFrame = 0; // Seek to beginning
         }
         isPlayingNotifier.value = true;
         _startPlaybackTimer(); // Start the timer
       }
    }
    // Case 3: No controller and zero duration - do nothing
  }

  void setZoom(double newZoom) {
    zoom = newZoom;
  }

  void _recalculateTotalFrames() {
    int maxClipFrame = 0;
    if (clipsNotifier.value.isNotEmpty) {
      maxClipFrame = clipsNotifier.value
          .map((clip) => clip.startFrame + clip.durationFrames)
          .reduce((a, b) => a > b ? a : b);
    }

    // Use video duration if controller exists and is longer than clips
    int videoFrames = 0;
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      videoFrames = (_videoPlayerController!.value.duration.inMilliseconds *
              _defaultFrameRate /
              1000)
          .round();
    }
    
    // If no clips and no video, use default duration. Otherwise use the max of clips/video.
    int newTotalFrames;
    if (clipsNotifier.value.isEmpty && videoFrames == 0) {
       newTotalFrames = _defaultTimelineDurationFrames;
    } else {
       newTotalFrames = maxClipFrame > videoFrames ? maxClipFrame : videoFrames;
    }

    // Ensure total frames doesn't decrease if playback is active near the old end
    // (This might need adjustment based on desired behavior when clips are shortened)
    if (newTotalFrames < _totalFrames && currentFrame >= newTotalFrames) {
        currentFrame = newTotalFrames; // Clamp current frame if needed
    }

    if (_totalFrames != newTotalFrames) {
      _totalFrames = newTotalFrames;
      totalFramesNotifier.value = _totalFrames;
      print("Recalculated total frames: $_totalFrames");

      // Stop playback if the new duration is 0 or current frame is now out of bounds
      if (_totalFrames == 0 || currentFrame > _totalFrames) {
         _stopPlaybackTimer();
         isPlayingNotifier.value = false;
         currentFrame = _totalFrames; // Clamp frame
      }
    }
  }

  Future<void> _unloadVideo() async {
    await _videoPlayerController?.dispose();
    _controllerPositionSubscription?.cancel();
    _videoPlayerController = null;
    videoPlayerControllerNotifier.value = null;
    isPlayingNotifier.value = false;
    _recalculateTotalFrames();
  }

  final ScrollController trackScrollController = ScrollController();

  // Add a clip from a file path, calculating duration
  Future<void> addClipFromFile(
    String filePath,
    int targetFrame,
    int trackIndex,
    ClipType type,
    String name,
  ) async {
    int durationFrames = 150; // Default duration if fetching fails

    if (type == ClipType.video || type == ClipType.audio) {
      VideoPlayerController? tempController;
      try {
        // Use networkUrl for testing if filePath is a URL, otherwise use file
        // Adapt this based on how file paths are handled (local vs network)
        if (Uri.tryParse(filePath)?.isAbsolute ?? false) {
          tempController = VideoPlayerController.networkUrl(
            Uri.parse(filePath),
          );
        } else {
          // Assuming filePath is a local path
          tempController = VideoPlayerController.file(File(filePath));
        }

        await tempController.initialize();
        final duration = tempController.value.duration;
        durationFrames =
            (duration.inMilliseconds * _defaultFrameRate / 1000).round();
        print(
          'Fetched duration for $filePath: $duration -> $durationFrames frames',
        );
      } catch (e) {
        print(
          "Error getting duration for $filePath: $e. Using default duration.",
        );
        // Keep default durationFrames
      } finally {
        // Ensure the temporary controller is disposed
        // Use ?.await to handle potential null if initialization failed early
        await tempController?.dispose();
      }
    }
    // Handle other types like images differently if needed (e.g., fixed duration)
    else if (type == ClipType.image) {
      durationFrames = 150; // Example fixed duration for images
    }

    // Create the clip with calculated (or default) duration
    final newClip = Clip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isNotEmpty ? name : 'Clip', // Use provided name or default
      type: type,
      filePath: filePath,
      startFrame: targetFrame,
      trackIndex: trackIndex,
      durationFrames: durationFrames,
    );

    // Add the clip using the existing method
    addClip(newClip);
  }

  // --- Playback Timer Logic ---

  void _startPlaybackTimer() {
    _stopPlaybackTimer(); // Ensure any existing timer is cancelled
    if (currentFrame >= _totalFrames) {
       isPlayingNotifier.value = false;
       return; // Don't start if already at the end
    }
    _playbackTimer = Timer(
      Duration(milliseconds: (1000 / _defaultFrameRate).round()),
      _handleTimerTick,
    );
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  void _handleTimerTick() {
    // This function will now be called by the Timer
     final nextFrame = currentFrame + 1;
      if (nextFrame <= _totalFrames) {
        currentFrameNotifier.value = nextFrame; // Update frame directly
        // Restart timer for next frame if not at the end
        if (nextFrame < _totalFrames) {
          _startPlaybackTimer(); 
        } else {
          // Reached end, stop playback
          _stopPlaybackTimer();
          isPlayingNotifier.value = false;
        }
      } else {
        // Should not happen if check above is correct, but safety stop
        _stopPlaybackTimer();
        isPlayingNotifier.value = false;
      }
  }

  @override
  void onDispose() {
    // Dispose controllers - this automatically removes listeners
    trackLabelScrollController.dispose();
    trackContentScrollController.dispose();

    // Dispose ValueNotifiers and other resources
    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    isPlayingNotifier.dispose();
    totalFramesNotifier.dispose();
    videoPlayerControllerNotifier.dispose(); // Dispose this notifier too
    
    _playbackTimer?.cancel();
    _controllerPositionSubscription?.cancel();
    _videoPlayerController?.dispose(); // Ensure video controller is disposed
  }
}
