import 'dart:async';
import 'dart:io'; // Added for File access
import 'package:drift/drift.dart' as drift; // Added Value import

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/database/project_database.dart' as project_db;
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/utils/logger.dart';

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

// Helper method to convert project database clip to ClipModel
ClipModel clipFromProjectDb(project_db.Clip dbData) {
  return ClipModel(
    databaseId: dbData.id,
    trackId: dbData.trackId,
    name: dbData.name,
    type: ClipType.values.firstWhere(
      (e) => e.toString().split('.').last == dbData.type,
      orElse: () => ClipType.video,
    ),
    sourcePath: dbData.sourcePath,
    startTimeInSourceMs: dbData.startTimeInSourceMs,
    endTimeInSourceMs: dbData.endTimeInSourceMs,
    startTimeOnTrackMs: dbData.startTimeOnTrackMs,
  );
}

class TimelineViewModel {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final ProjectDatabaseService _projectDatabaseService;

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

  final int _totalFrames = 0;
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

  TimelineViewModel(this._projectDatabaseService) {
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
      '🔄 Loading clips for project $projectId',
    );
    
    // Load the project using the service
    final success = await _projectDatabaseService.loadProject(projectId);
    if (!success) {
      logError(
        _logTag,
        '❌ Failed to load project $projectId',
      );
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }
    
    // Use the tracks from the service
    final tracks = _projectDatabaseService.tracksNotifier.value;

    currentTrackIds = tracks.map((t) => t.id).toList();
    logInfo(
      _logTag,
      '📊 Loaded ${tracks.length} tracks with IDs: $currentTrackIds',
    );

    if (tracks.isEmpty) {
      logInfo(
        _logTag,
        '⚠️ No tracks found for project $projectId',
      );
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    await refreshClips();
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

  /// Calculates exact frame position from pixel coordinates on the timeline
  int calculateFramePosition(double pixelPosition, double scrollOffset, double zoom) {
    final adjustedPosition = pixelPosition + scrollOffset;
    final frameWidth = 5.0 * zoom; // 5px per frame at 1.0 zoom
    
    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  /// Converts a frame position to milliseconds (based on standard 30fps)
  int frameToMs(int framePosition) {
    return ClipModel.framesToMs(framePosition);
  }
  
  /// Calculates millisecond position directly from pixel coordinates
  int calculateMsPositionFromPixels(double pixelPosition, double scrollOffset, double zoom) {
    final framePosition = calculateFramePosition(pixelPosition, scrollOffset, zoom);
    return frameToMs(framePosition);
  }

  Future<bool> addClip({
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) async {
    if (_projectDatabaseService.clipDao == null) {
      logError(_logTag, 'Clip DAO not initialized');
      return false;
    }
    try {
      final newClipId = await _projectDatabaseService.clipDao!.insertClip(
        project_db.ClipsCompanion(
          trackId: drift.Value(trackId),
          type: drift.Value(type.name),
          sourcePath: drift.Value(sourcePath),
          startTimeOnTrackMs: drift.Value(startTimeOnTrackMs),
          startTimeInSourceMs: drift.Value(startTimeInSourceMs),
          endTimeInSourceMs: drift.Value(endTimeInSourceMs),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      await refreshClips();
      logInfo(_logTag, 'Added new clip with ID $newClipId');
      return true;
    } catch (e) {
      logError(_logTag, 'Error adding clip: $e');
      return false;
    }
  }

  Future<bool> removeClip(int clipId) async {
    if (_projectDatabaseService.clipDao == null) {
      logError(_logTag, 'Clip DAO not initialized');
      return false;
    }
    try {
      await _projectDatabaseService.clipDao!.deleteClip(clipId);
      await refreshClips();
      logInfo(_logTag, 'Removed clip with ID $clipId');
      return true;
    } catch (e) {
      logError(_logTag, 'Error removing clip: $e');
      return false;
    }
  }

  Future<bool> moveClip({
    required int clipId,
    required int newTrackId,
    required int newStartTimeOnTrackMs,
  }) async {
    if (_projectDatabaseService.clipDao == null) {
      logError(_logTag, 'Clip DAO not initialized');
      return false;
    }
    try {
      final updated = await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        {
          'trackId': newTrackId,
          'startTimeOnTrackMs': newStartTimeOnTrackMs,
          'updatedAt': DateTime.now(),
        },
      );
      await refreshClips();
      logInfo(_logTag, 'Moved clip $clipId to track $newTrackId, start $newStartTimeOnTrackMs');
      return updated;
    } catch (e) {
      logError(_logTag, 'Error moving clip: $e');
      return false;
    }
  }

  Future<void> refreshClips() async {
    if (_projectDatabaseService.clipDao == null) return;
    // Aggregate all clips from all tracks
    final tracks = _projectDatabaseService.tracksNotifier.value;
    List<ClipModel> allClips = [];
    for (final track in tracks) {
      final dbClips = await _projectDatabaseService.clipDao!.getClipsForTrack(track.id);
      allClips.addAll(dbClips.map(clipFromProjectDb));
    }
    allClips.sort((a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs));
    clipsNotifier.value = allClips;
    _recalculateAndUpdateTotalFrames();
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

  Future<void> addClipAtPosition({
    required ClipModel clipData,
    required int trackId,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
    double? localPositionX,
    double? scrollOffsetX,
  }) async {
    int targetStartTimeMs;

    logInfo(
      _logTag,
      'addClipAtPosition called: trackId=$trackId, clip=${clipData.name}, type=${clipData.type}'
    );
    
    // Update currentTrackIds from the database service to ensure it's current
    final tracks = _projectDatabaseService.tracksNotifier.value;
    currentTrackIds = tracks.map((t) => t.id).toList();
    
    logInfo(
      _logTag,
      'Available track IDs: $currentTrackIds'
    );
    
    if (!currentTrackIds.contains(trackId)) {
      logError(
        _logTag,
        'Track ID $trackId is not in current tracks list: $currentTrackIds'
      );
      // Continue anyway - the track might exist but not be in our cached list
    }

    if (localPositionX != null && scrollOffsetX != null) {
      targetStartTimeMs = calculateMsPositionFromPixels(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
      logInfo(
        _logTag,
        'Calculated position: localX=$localPositionX, scrollX=$scrollOffsetX, targetMs=$targetStartTimeMs'
      );
    } else {
      targetStartTimeMs = ClipModel.framesToMs(currentFrame);
      logInfo(
        _logTag,
        'Using current frame position: frame=$currentFrame, targetMs=$targetStartTimeMs'
      );
    }
    
    final result = await addClip(
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      startTimeOnTrackMs: targetStartTimeMs,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
    );
    
    logInfo(
      _logTag,
      'addClip result: $result'
    );
  }

  Future<bool> createTimelineClip({
    required int trackId,
    required ClipModel clipData,
    required int framePosition,
  }) async {
    logInfo(
      _logTag,
      'Creating timeline clip at frame $framePosition on track $trackId for ${clipData.name}'
    );
    
    // Convert the frame position to milliseconds using the helper method
    final startTimeOnTrackMs = frameToMs(framePosition);
    
    // Additional debug info about timing
    final clipDurationFrames = ClipModel.msToFrames(clipData.durationMs);
    logInfo(
      _logTag,
      'Frame metrics: startFrame=$framePosition, durationFrames=$clipDurationFrames, startTimeMs=$startTimeOnTrackMs'
    );
    
    // Call the existing createClip method with the calculated position
    return await addClip(
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: clipData.startTimeInSourceMs,
      endTimeInSourceMs: clipData.endTimeInSourceMs,
    );
  }
}
