import 'dart:async';
import 'dart:io'; // Added for File access
import 'dart:ui'; // Required for lerpDouble
import 'package:drift/drift.dart' show Value; // Added Value import

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/dao/clip_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/database/app_database.dart' show Track;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart'; // Add logger import

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

class TimelineViewModel {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final ClipDao _clipDao;
  final TrackDao _trackDao;

  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);

  List<int> currentTrackIds = [];

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    if (zoomNotifier.value == value || value < 0.1 || value > 5.0) return;
    zoomNotifier.value = value;
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFrames = _calculateTotalFrames();
    final clampedValue = value.clamp(0, totalFrames);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;

    if (_playbackTimer?.isActive ?? false) {
      _stopPlaybackTimer();
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

  final ScrollController trackContentHorizontalScrollController =
      ScrollController();

  // Added back Notifier for the width of the track label area
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier(120.0);

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;
  StreamSubscription? _clipStreamSubscription;

  late final VoidCallback _debouncedFrameUpdate;

  TimelineViewModel(this._clipDao, this._trackDao) {
    _recalculateAndUpdateTotalFrames();

    _debouncedFrameUpdate = _debounce(() {
      if (!isPlayingNotifier.value) return;

      final currentMs = ClipModel.framesToMs(currentFrame);
      final nextFrameMs = currentMs + (1000 / _defaultFrameRate);
      final nextFrame = ClipModel.msToFrames(nextFrameMs.round());

      final totalFrames = _calculateTotalFrames();
      if (nextFrame <= totalFrames) {
        currentFrameNotifier.value = nextFrame;
        if (nextFrame < totalFrames) {
          _startPlaybackTimer();
        } else {
          _stopPlaybackTimer();
          isPlayingNotifier.value = false;
        }
      } else {
        _stopPlaybackTimer();
        isPlayingNotifier.value = false;
      }
    }, Duration(milliseconds: (1000 / _defaultFrameRate).round()));
  }

  Future<void> loadClipsForProject(int projectId) async {
    logInfo(
      _logTag,
      'Loading clips for project $projectId',
    ); // Use top-level function with tag
    final tracks = await _trackDao.getTracksForProject(projectId);

    currentTrackIds = tracks.map((t) => t.id).toList();
    logInfo(
      _logTag,
      'Loaded track IDs: $currentTrackIds',
    ); // Use top-level function with tag

    if (tracks.isEmpty) {
      logInfo(
        _logTag,
        'No tracks found for project $projectId',
      ); // Use top-level function with tag
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    final List<ClipModel> allClips = [];
    for (final track in tracks) {
      logDebug(
        _logTag,
        'Processing track ID: ${track.id}',
      ); // Use top-level function with tag
      final trackClipsData = await _clipDao.getClipsForTrack(track.id);
      logDebug(
        _logTag,
        'Found ${trackClipsData.length} clips for track ID: ${track.id}',
      ); // Use top-level function with tag
      allClips.addAll(
        trackClipsData.map((dbData) => ClipModel.fromDbData(dbData)),
      );
    }

    logInfo(
      _logTag,
      'Loaded ${allClips.length} clips',
    ); // Use top-level function with tag
    clipsNotifier.value = allClips;
    _recalculateAndUpdateTotalFrames();

    ClipModel? firstVideo; // Use nullable type
    try {
      firstVideo = allClips.firstWhere((c) => c.type == ClipType.video);
    } catch (e) {
      // Handle stateError if no element is found (no video clips)
      firstVideo = null;
    }

    if (firstVideo != null) {
      // await loadVideo(firstVideo.sourcePath); // Decide if auto-loading is desired
    } else {
      // Ensure player is cleared if no video clips
      // await _videoPlayerController?.dispose();
      // _videoPlayerController = null;
      // videoPlayerControllerNotifier.value = null;
    }
  }

  void _updateFrameFromController() {
    if (_videoPlayerController == null ||
        !_videoPlayerController!.value.isInitialized) {
      return;
    }

    final position = _videoPlayerController!.value.position;
    final frame = ClipModel.msToFrames(position.inMilliseconds);

    final totalFrames = _calculateTotalFrames();
    if (currentFrameNotifier.value != frame && frame <= totalFrames) {
      currentFrameNotifier.value = frame;
    }

    if (isPlayingNotifier.value != _videoPlayerController!.value.isPlaying) {
      isPlayingNotifier.value = _videoPlayerController!.value.isPlaying;
      if (!isPlayingNotifier.value) {
        _stopPlaybackTimer();
      }
    }
  }

  void _seekControllerToFrame(int frame) {
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      final targetPosition = Duration(
        milliseconds: ClipModel.framesToMs(frame),
      );

      final currentPosition = _videoPlayerController!.value.position;
      if ((targetPosition - currentPosition).abs() >
          const Duration(milliseconds: 50)) {
        _videoPlayerController!.seekTo(targetPosition);
      }
    }
  }

  void addClip(ClipModel clip) {
    final newClips = List<ClipModel>.from(clipsNotifier.value)..add(clip);
    clipsNotifier.value = newClips;
    _recalculateAndUpdateTotalFrames();

    if (_videoPlayerController == null && clip.type == ClipType.video) {
      _stopPlaybackTimer();
      isPlayingNotifier.value = false;
      loadVideo(clip.sourcePath);
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

  Future<void> addClipAtPosition({
    required ClipModel clipData,
    required int trackId,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
    double? localPositionX,
    double? scrollOffsetX,
  }) async {
    int targetStartTimeMs;

    if (localPositionX != null && scrollOffsetX != null) {
      targetStartTimeMs = calculateMsPositionFromDrop(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
    } else {
      targetStartTimeMs = ClipModel.framesToMs(currentFrame);
    }

    final newClipModel = ClipModel(
      trackId: trackId,
      name:
          clipData.name.isNotEmpty
              ? clipData.name
              : 'Clip ${DateTime.now().millisecondsSinceEpoch}',
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
      startTimeOnTrackMs: targetStartTimeMs,
    );

    try {
      final companion = newClipModel.toDbCompanion();
      final newDbId = await _clipDao.insertClip(companion);

      final clipWithId = newClipModel.copyWith(databaseId: Value(newDbId));

      final currentClips = List<ClipModel>.from(clipsNotifier.value);
      currentClips.add(clipWithId);
      clipsNotifier.value = currentClips;

      _recalculateAndUpdateTotalFrames();

      if (_videoPlayerController == null && clipWithId.type == ClipType.video) {
        _stopPlaybackTimer();
        isPlayingNotifier.value = false;
      }
      logInfo(
        _logTag,
        'Clip added with ID: $newDbId at ${clipWithId.startTimeOnTrackMs}ms',
      ); // Use top-level function with tag
    } catch (e) {
      logError(
        _logTag,
        "Error adding clip to database: $e",
      ); // Use top-level function with tag
    }
  }

  Future<void> removeClip(int clipId) async {
    logInfo(
      _logTag,
      'Attempting to remove clip with ID: $clipId',
    ); // Log attempt
    try {
      // Delete from database
      final rowsAffected = await _clipDao.deleteClip(clipId);

      if (rowsAffected > 0) {
        // Remove from the notifier
        final currentClips = List<ClipModel>.from(clipsNotifier.value);
        final initialLength = currentClips.length;
        currentClips.removeWhere((clip) => clip.databaseId == clipId);

        if (currentClips.length < initialLength) {
          clipsNotifier.value = currentClips;
          _recalculateAndUpdateTotalFrames(); // Update total duration
          logInfo(_logTag, 'Successfully removed clip ID: $clipId');

          // Optional: Handle video player if the removed clip was the primary video
          // This might require checking if the removed clip was the one loaded,
          // and potentially loading another video or clearing the player.
          // Example (needs refinement based on exact logic):
          // if (_videoPlayerController != null && _videoPlayerController!.dataSource.contains(clipSourcePath)) {
          //   await _videoPlayerController?.dispose();
          //   _videoPlayerController = null;
          //   videoPlayerControllerNotifier.value = null;
          //   // Maybe load the next video clip?
          // }
        } else {
          logWarning(
            _logTag,
            'Clip ID $clipId found in DB but not in notifier. Notifier might be out of sync.',
          );
        }
      } else {
        logWarning(
          _logTag,
          'Clip ID $clipId not found in database or deletion failed.',
        );
      }
    } catch (e, stackTrace) {
      logError('Error removing clip ID: $clipId', e, stackTrace, _logTag);
    }
  }

  Future<void> updateClipPosition(int clipId, int newStartTimeMs) async {
    if (clipId <= 0) return;

    try {
      final successCount = await _clipDao.updateClipStartTimeOnTrack(
        clipId,
        newStartTimeMs,
      );

      if (successCount > 0) {
        final currentClips = List<ClipModel>.from(clipsNotifier.value);
        final index = currentClips.indexWhere(
          (clip) => clip.databaseId == clipId,
        );
        if (index != -1) {
          final updatedClip = currentClips[index].copyWith(
            startTimeOnTrackMs: newStartTimeMs,
          );
          currentClips[index] = updatedClip;
          clipsNotifier.value = currentClips;
          _recalculateAndUpdateTotalFrames();
          logInfo(
            _logTag,
            'Clip $clipId position updated to ${newStartTimeMs}ms',
          ); // Use top-level function with tag
        } else {
          logWarning(
            _logTag,
            'Warning: Clip $clipId not found locally after successful DB update.',
          ); // Use top-level function with tag
        }
      } else {
        logError(
          _logTag,
          'Error: Clip $clipId not found in DB or failed to update position.',
        ); // Use top-level function with tag
      }
    } catch (e) {
      logError(
        _logTag,
        "Error updating clip position in database: $e",
      ); // Use top-level function with tag
    }
  }

  Future<void> updateClipTrim(
    int databaseId,
    int newStartTimeInSourceMs,
    int newEndTimeInSourceMs,
  ) async {
    if (databaseId <= 0 || newEndTimeInSourceMs < newStartTimeInSourceMs)
      return;

    try {
      final successCount = await _clipDao.updateClipTrimTimes(
        databaseId,
        newStartTimeInSourceMs,
        newEndTimeInSourceMs,
      );

      if (successCount > 0) {
        final currentClips = List<ClipModel>.from(clipsNotifier.value);
        final index = currentClips.indexWhere(
          (clip) => clip.databaseId == databaseId,
        );
        if (index != -1) {
          final updatedClip = currentClips[index].copyWith(
            startTimeInSourceMs: newStartTimeInSourceMs,
            endTimeInSourceMs: newEndTimeInSourceMs,
          );
          currentClips[index] = updatedClip;
          clipsNotifier.value = currentClips;
          _recalculateAndUpdateTotalFrames();
          logInfo(
            _logTag,
            'Clip $databaseId trim updated',
          ); // Use top-level function with tag
        } else {
          logWarning(
            _logTag,
            'Warning: Clip $databaseId not found locally after successful DB update.',
          ); // Use top-level function with tag
        }
      } else {
        logError(
          _logTag,
          'Error: Clip $databaseId not found in DB or failed to update trim.',
        ); // Use top-level function with tag
      }
    } catch (e) {
      logError(
        _logTag,
        "Error updating clip trim in database: $e",
      ); // Use top-level function with tag
    }
  }

  int calculateMsPositionFromDrop(
    double localPositionX,
    double scrollOffsetX,
    double zoom,
  ) {
    final frame = calculateFramePositionFromDrop(
      localPositionX,
      scrollOffsetX,
      zoom,
    );
    return ClipModel.framesToMs(frame);
  }

  void play() {
    if (isPlayingNotifier.value) return;

    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
      final totalDuration = _videoPlayerController!.value.duration;
      final currentPosition = _videoPlayerController!.value.position;
      if (currentPosition >= totalDuration) {
        _videoPlayerController!.seekTo(Duration.zero);
      }
      _videoPlayerController!.play();
      isPlayingNotifier.value = true;
    } else {
      final totalFrames = _calculateTotalFrames();
      if (currentFrame >= totalFrames) {
        currentFrame = 0;
      }
      isPlayingNotifier.value = true;
      _startPlaybackTimer();
    }
  }

  void pause() {
    if (!isPlayingNotifier.value) return;

    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isPlaying) {
      _videoPlayerController!.pause();
    }
    _stopPlaybackTimer();
    isPlayingNotifier.value = false;
  }

  void togglePlayPause() {
    if (isPlayingNotifier.value) {
      pause();
    } else {
      play();
    }
  }

  void _startPlaybackTimer() {
    _stopPlaybackTimer();
    if (isPlayingNotifier.value) {
      _playbackTimer = Timer(
        Duration(milliseconds: (1000 / _defaultFrameRate).round()),
        _debouncedFrameUpdate,
      );
    }
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  Future<void> loadVideo(String videoPath) async {
    await _videoPlayerController?.dispose();
    _controllerPositionSubscription?.cancel();
    videoPlayerControllerNotifier.value = null;

    Uri videoUri;
    if (videoPath.startsWith('http') || videoPath.startsWith('https')) {
      videoUri = Uri.parse(videoPath);
      _videoPlayerController = VideoPlayerController.networkUrl(videoUri);
    } else {
      final file = File(videoPath);
      if (!await file.exists()) {
        logError(
          _logTag,
          "Error: Video file not found at $videoPath",
        ); // Use top-level function with tag
        _recalculateAndUpdateTotalFrames();
        return;
      }
      videoUri = Uri.file(videoPath);
      _videoPlayerController = VideoPlayerController.file(file);
    }

    try {
      await _videoPlayerController!.initialize();
      _videoPlayerController!.setLooping(false);

      _recalculateAndUpdateTotalFrames();
      currentFrame = 0;

      _videoPlayerController!.addListener(_updateFrameFromController);
      videoPlayerControllerNotifier.value = _videoPlayerController;

      _stopPlaybackTimer();
      isPlayingNotifier.value = false;

      logInfo(
        _logTag,
        'Video loaded for preview: $videoPath',
      ); // Use top-level function with tag
    } catch (e) {
      logError(
        _logTag,
        "Error initializing video player: $e",
      ); // Use top-level function with tag
      _videoPlayerController = null;
      videoPlayerControllerNotifier.value = null;
      _recalculateAndUpdateTotalFrames();
    }
    isPlayingNotifier.value = false;
  }

  int _calculateTotalFrames() {
    if (clipsNotifier.value.isEmpty) {
      return 0;
    }
    int maxEndTimeMs = 0;
    for (final clip in clipsNotifier.value) {
      final clipEndTimeMs = clip.startTimeOnTrackMs + clip.durationMs;
      if (clipEndTimeMs > maxEndTimeMs) {
        maxEndTimeMs = clipEndTimeMs;
      }
    }
    return ClipModel.msToFrames(maxEndTimeMs);
  }

  void _recalculateAndUpdateTotalFrames() {
    final newTotalFrames = _calculateTotalFrames();
    if (totalFramesNotifier.value != newTotalFrames) {
      totalFramesNotifier.value = newTotalFrames;
      if (currentFrame > newTotalFrames) {
        currentFrame = newTotalFrames;
      }
    }
  }

  /// Update the width of the track label area (Added back)
  void updateTrackLabelWidth(double newWidth) {
    // Add constraints if needed, e.g., minimum/maximum width
    trackLabelWidthNotifier.value = newWidth.clamp(
      50.0,
      300.0,
    ); // Example constraints
  }

  @override
  void onDispose() {
    logInfo(_logTag, 'Disposing TimelineViewModel');
    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    isPlayingNotifier.dispose();
    videoPlayerControllerNotifier.dispose();
    trackLabelWidthNotifier.dispose(); // Added back disposal

    trackContentHorizontalScrollController.dispose();

    _stopPlaybackTimer();
    _controllerPositionSubscription?.cancel();
    _clipStreamSubscription?.cancel();

    _videoPlayerController?.dispose();
  }
}
