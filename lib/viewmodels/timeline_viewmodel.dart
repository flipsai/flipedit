import 'dart:async';
import 'dart:io'; // Added for File access

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

const double _defaultFrameRate = 30.0;

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

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;

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

      _totalFrames =
          (_videoPlayerController!.value.duration.inMilliseconds *
                  _defaultFrameRate /
                  1000)
              .round();
      totalFramesNotifier.value = _totalFrames;
      currentFrame = 0;

      _videoPlayerController!.addListener(_updateFrameFromController);

      videoPlayerControllerNotifier.value = _videoPlayerController;

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
        !_videoPlayerController!.value.isInitialized)
      return;

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
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized)
      return;

    if (_videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    } else {
      _seekControllerToFrame(currentFrame);
      _videoPlayerController!.play();
    }
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

    int videoFrames = 0;
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      videoFrames =
          (_videoPlayerController!.value.duration.inMilliseconds *
                  _defaultFrameRate /
                  1000)
              .round();
    }

    _totalFrames = maxClipFrame > videoFrames ? maxClipFrame : videoFrames;
    totalFramesNotifier.value = _totalFrames;

    if (currentFrame > _totalFrames) {
      currentFrame = _totalFrames;
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

  @override
  void onDispose() {
    _videoPlayerController?.dispose();
    _controllerPositionSubscription?.cancel();
    _playbackTimer?.cancel();

    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    isPlayingNotifier.dispose();
    videoPlayerControllerNotifier.dispose();

    trackScrollController.dispose();
  }
}
