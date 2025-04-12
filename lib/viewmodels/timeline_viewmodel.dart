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
  final ClipDao _clipDao;
  final TrackDao _trackDao;

  final ValueNotifier<List<ClipModel>> clipsNotifier = ValueNotifier<List<ClipModel>>([]);
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

  final ScrollController trackLabelScrollController = ScrollController();
  final ScrollController trackContentScrollController = ScrollController();

  bool _isSyncingLabels = false;
  bool _isSyncingContent = false;

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;
  StreamSubscription? _clipStreamSubscription;

  late final VoidCallback _debouncedFrameUpdate;

  TimelineViewModel(this._clipDao, this._trackDao) {
    _setupScrollSync();
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

  void _setupScrollSync() {
    final debouncedSyncToContent = _debounce(() {
      if (!_isSyncingLabels &&
          trackLabelScrollController.hasClients &&
          trackContentScrollController.hasClients &&
          trackLabelScrollController.position.hasPixels &&
          trackContentScrollController.position.hasPixels) {
        _isSyncingContent = true;
        trackContentScrollController.jumpTo(trackLabelScrollController.offset);
        Future.delayed(Duration.zero, () => _isSyncingContent = false);
      }
    }, const Duration(milliseconds: 10));

    final debouncedSyncToLabels = _debounce(() {
      if (!_isSyncingContent &&
          trackContentScrollController.hasClients &&
          trackLabelScrollController.hasClients &&
          trackLabelScrollController.position.hasPixels &&
          trackContentScrollController.position.hasPixels) {
        _isSyncingLabels = true;
        trackLabelScrollController.jumpTo(trackContentScrollController.offset);
        Future.delayed(Duration.zero, () => _isSyncingLabels = false);
      }
    }, const Duration(milliseconds: 10));

    trackLabelScrollController.addListener(debouncedSyncToContent);
    trackContentScrollController.addListener(debouncedSyncToLabels);
  }

  Future<void> loadClipsForProject(int projectId) async {
    print('Loading clips for project $projectId');
    final tracks = await _trackDao.getTracksForProject(projectId);
    
    currentTrackIds = tracks.map((t) => t.id).toList();
    print('Loaded track IDs: $currentTrackIds');

    if (tracks.isEmpty) {
      print('No tracks found for project $projectId');
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    final List<ClipModel> allClips = [];
    for (final track in tracks) {
      print('Processing track ID: ${track.id}');
      final trackClipsData = await _clipDao.getClipsForTrack(track.id);
      print('Found ${trackClipsData.length} clips for track ID: ${track.id}');
      allClips.addAll(trackClipsData.map((dbData) => ClipModel.fromDbData(dbData)));
    }

    print('Loaded ${allClips.length} clips');
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
      final targetPosition = Duration(milliseconds: ClipModel.framesToMs(frame));

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
       name: clipData.name.isNotEmpty ? clipData.name : 'Clip ${DateTime.now().millisecondsSinceEpoch}',
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
        print('Clip added with ID: $newDbId at ${clipWithId.startTimeOnTrackMs}ms');

    } catch (e) {
       print("Error adding clip to database: $e");
    }
  }

  Future<void> removeClip(int databaseId) async {
    if (databaseId <= 0) return;

    try {
      final successCount = await _clipDao.deleteClip(databaseId);

      if (successCount > 0) {
        final currentClips = List<ClipModel>.from(clipsNotifier.value);
        final initialLength = currentClips.length;
        currentClips.removeWhere((clip) => clip.databaseId == databaseId);

        if (currentClips.length < initialLength) {
           clipsNotifier.value = currentClips;
           _recalculateAndUpdateTotalFrames();
           print('Clip removed with ID: $databaseId');

        } else {
           print('Warning: Clip with ID $databaseId not found in local state after successful DB delete.');
        }
      } else {
         print('Error: Clip with ID $databaseId not found in database or could not be deleted.');
      }
    } catch (e) {
      print("Error removing clip from database: $e");
    }
  }

  Future<void> updateClipPosition(int databaseId, int newStartTimeOnTrackMs) async {
     if (databaseId <= 0) return;

     try {
        final successCount = await _clipDao.updateClipStartTimeOnTrack(databaseId, newStartTimeOnTrackMs);

        if (successCount > 0) {
            final currentClips = List<ClipModel>.from(clipsNotifier.value);
            final index = currentClips.indexWhere((clip) => clip.databaseId == databaseId);
            if (index != -1) {
               final updatedClip = currentClips[index].copyWith(startTimeOnTrackMs: newStartTimeOnTrackMs);
               currentClips[index] = updatedClip;
               clipsNotifier.value = currentClips;
               _recalculateAndUpdateTotalFrames();
               print('Clip $databaseId position updated to ${newStartTimeOnTrackMs}ms');
            } else {
               print('Warning: Clip $databaseId not found locally after successful DB update.');
            }
        } else {
           print('Error: Clip $databaseId not found in DB or failed to update position.');
        }
     } catch (e) {
        print("Error updating clip position in database: $e");
     }
  }

  Future<void> updateClipTrim(int databaseId, int newStartTimeInSourceMs, int newEndTimeInSourceMs) async {
      if (databaseId <= 0 || newEndTimeInSourceMs < newStartTimeInSourceMs) return;

       try {
        final successCount = await _clipDao.updateClipTrimTimes(databaseId, newStartTimeInSourceMs, newEndTimeInSourceMs);

        if (successCount > 0) {
            final currentClips = List<ClipModel>.from(clipsNotifier.value);
            final index = currentClips.indexWhere((clip) => clip.databaseId == databaseId);
            if (index != -1) {
               final updatedClip = currentClips[index].copyWith(
                   startTimeInSourceMs: newStartTimeInSourceMs,
                   endTimeInSourceMs: newEndTimeInSourceMs,
               );
               currentClips[index] = updatedClip;
               clipsNotifier.value = currentClips;
               _recalculateAndUpdateTotalFrames();
               print('Clip $databaseId trim updated');
            } else {
               print('Warning: Clip $databaseId not found locally after successful DB update.');
            }
        } else {
           print('Error: Clip $databaseId not found in DB or failed to update trim.');
        }
     } catch (e) {
        print("Error updating clip trim in database: $e");
     }
  }

  int calculateMsPositionFromDrop(
    double localPositionX,
    double scrollOffsetX,
    double zoom,
  ) {
    final frame = calculateFramePositionFromDrop(localPositionX, scrollOffsetX, zoom);
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
           print("Error: Video file not found at $videoPath");
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

      print('Video loaded for preview: $videoPath');
    } catch (e) {
      print("Error initializing video player: $e");
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

  @override
  void onDispose() {
    print('Disposing TimelineViewModel');
    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    isPlayingNotifier.dispose();
    videoPlayerControllerNotifier.dispose();

    trackLabelScrollController.dispose();
    trackContentScrollController.dispose();

    _stopPlaybackTimer();
    _controllerPositionSubscription?.cancel();
    _clipStreamSubscription?.cancel();

    _videoPlayerController?.dispose();
  }
}
