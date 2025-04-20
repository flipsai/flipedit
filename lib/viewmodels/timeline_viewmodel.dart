import 'dart:async';
import 'dart:io'; // Added for File access
import 'dart:ui'; // Required for lerpDouble
import 'package:drift/drift.dart' show Value; // Added Value import

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/database/project_database.dart' as project_db;
import 'package:flipedit/persistence/tables/clips.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
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
      'Loading clips for project $projectId',
    );
    
    // Load the project using the service
    final success = await _projectDatabaseService.loadProject(projectId);
    if (!success) {
      logError(
        _logTag,
        'Failed to load project $projectId',
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
      'Loaded track IDs: $currentTrackIds',
    );

    if (tracks.isEmpty) {
      logInfo(
        _logTag,
        'No tracks found for project $projectId',
      );
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    final List<ClipModel> allClips = [];
    for (final track in tracks) {
      logDebug(
        _logTag,
        'Processing track ID: ${track.id}',
      );
      
      // Since ProjectDatabaseTrackDao doesn't have getClipsForTrack, we need to use the ClipDao
      if (_projectDatabaseService.clipDao != null) {
        final trackClipsData = await _projectDatabaseService.clipDao!.getClipsForTrack(track.id);
        
        logDebug(
          _logTag,
          'Found ${trackClipsData.length} clips for track ID: ${track.id}',
        );
        allClips.addAll(
          trackClipsData.map((dbData) => clipFromProjectDb(dbData)),
        );
      }
    }

    logInfo(
      _logTag,
      'Loaded ${allClips.length} clips',
    );
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

  Future<bool> removeClip(int clipId) async {
    try {
      // Ensure the project database service has the clip DAO initialized
      if (_projectDatabaseService.clipDao == null) {
        logError(
          _logTag,
          'Clip DAO not initialized in ProjectDatabaseService',
        );
        return false;
      }

      // Delete the clip
      final deleteResult = await _projectDatabaseService.clipDao!.deleteClip(clipId);
      if (deleteResult <= 0) {
        logWarning(
          _logTag,
          'No clip found to delete with ID $clipId',
        );
        return false;
      }

      // Update local state
      final updatedClips = clipsNotifier.value
          .where((clip) => clip.databaseId != clipId)
          .toList();
      clipsNotifier.value = updatedClips;
      _recalculateAndUpdateTotalFrames();

      logInfo(
        _logTag,
        'Removed clip with ID $clipId',
      );
      return true;
    } catch (e) {
      logError(
        _logTag,
        'Error removing clip: $e',
      );
      return false;
    }
  }

  Future<bool> updateClipPosition(
    int clipId,
    int trackId,
    int startTimeOnTrackMs,
  ) async {
    try {
      // Ensure the project database service has the clip DAO initialized
      if (_projectDatabaseService.clipDao == null) {
        logError(
          _logTag,
          'Clip DAO not initialized in ProjectDatabaseService',
        );
        return false;
      }

      // Find the clip in our local state first
      final clipIndex =
          clipsNotifier.value.indexWhere((clip) => clip.databaseId == clipId);
      if (clipIndex < 0) {
        logError(
          _logTag,
          'Clip not found for position update: ID $clipId',
        );
        return false;
      }

      final clip = clipsNotifier.value[clipIndex];
      
      // Create companion for update for project database
      final clipCompanion = project_db.ClipsCompanion(
        id: Value(clipId),
        trackId: Value(trackId),
        startTimeOnTrackMs: Value(startTimeOnTrackMs),
        updatedAt: Value(DateTime.now()),
      );

      // Update using the service
      final updateResult = await _projectDatabaseService.clipDao!.updateClip(clipCompanion);
      if (!updateResult) {
        logError(
          _logTag,
          'Failed to update clip position in database: ID $clipId',
        );
        return false;
      }

      // Update local state
      final updatedClip = clip.copyWith(
        trackId: trackId,
        startTimeOnTrackMs: startTimeOnTrackMs,
      );
      final updatedClips = [...clipsNotifier.value];
      updatedClips[clipIndex] = updatedClip;
      clipsNotifier.value = updatedClips;
      _recalculateAndUpdateTotalFrames();

      logInfo(
        _logTag,
        'Updated position for clip ID $clipId: Track $trackId, Start $startTimeOnTrackMs ms',
      );
      return true;
    } catch (e) {
      logError(
        _logTag,
        'Error updating clip position: $e',
      );
      return false;
    }
  }

  Future<bool> updateClipTrim(
    int clipId,
    int startTimeInSourceMs,
    int endTimeInSourceMs,
  ) async {
    try {
      // Ensure the project database service has the clip DAO initialized
      if (_projectDatabaseService.clipDao == null) {
        logError(
          _logTag,
          'Clip DAO not initialized in ProjectDatabaseService',
        );
        return false;
      }

      final durationMs = endTimeInSourceMs - startTimeInSourceMs;
      if (durationMs <= 0) {
        logError(
          _logTag,
          'Invalid clip duration for trim: $durationMs ms',
        );
        return false;
      }

      // Find the clip in our local state first
      final clipIndex =
          clipsNotifier.value.indexWhere((clip) => clip.databaseId == clipId);
      if (clipIndex < 0) {
        logError(
          _logTag,
          'Clip not found for trim update: ID $clipId',
        );
        return false;
      }

      final clip = clipsNotifier.value[clipIndex];
      
      // Create companion for update for project database
      final clipCompanion = project_db.ClipsCompanion(
        id: Value(clipId),
        startTimeInSourceMs: Value(startTimeInSourceMs),
        endTimeInSourceMs: Value(endTimeInSourceMs),
        updatedAt: Value(DateTime.now()),
      );

      // Update using the service
      final updateResult = await _projectDatabaseService.clipDao!.updateClip(clipCompanion);
      if (!updateResult) {
        logError(
          _logTag,
          'Failed to update clip trim in database: ID $clipId',
        );
        return false;
      }

      // Update local state
      final updatedClip = clip.copyWith(
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );
      final updatedClips = [...clipsNotifier.value];
      updatedClips[clipIndex] = updatedClip;
      clipsNotifier.value = updatedClips;
      _recalculateAndUpdateTotalFrames();

      logInfo(
        _logTag,
        'Updated trim for clip ID $clipId: $startTimeInSourceMs to $endTimeInSourceMs ms',
      );
      return true;
    } catch (e) {
      logError(
        _logTag,
        'Error updating clip trim: $e',
      );
      return false;
    }
  }

  int calculateMsPositionFromDrop(
    double localPositionX,
    double scrollOffsetX,
    double currentZoom,
  ) {
    // Calculate the position in milliseconds based on drop position
    final pixelsPerMs = _defaultFrameRate / 1000 * currentZoom;
    final positionMs = ((localPositionX + scrollOffsetX) / pixelsPerMs).round();
    return positionMs;
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

    if (localPositionX != null && scrollOffsetX != null) {
      targetStartTimeMs = calculateMsPositionFromDrop(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
    } else {
      targetStartTimeMs = ClipModel.framesToMs(currentFrame);
    }
    
    await createClip(
      trackId: trackId,
      type: clipData.type,
      sourcePath: clipData.sourcePath,
      startTimeOnTrackMs: targetStartTimeMs,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
    );
  }

  // New method that uses the ProjectDatabaseService
  Future<bool> createClip({
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) async {
    if (!currentTrackIds.contains(trackId)) {
      logError(
        _logTag,
        'Invalid track ID: $trackId',
      );
      return false;
    }

    final durationMs = endTimeInSourceMs - startTimeInSourceMs;
    if (durationMs <= 0) {
      logError(
        _logTag,
        'Invalid clip duration: $durationMs',
      );
      return false;
    }

    try {
      // Ensure the project database service has the clip DAO initialized
      if (_projectDatabaseService.clipDao == null) {
        logError(
          _logTag,
          'Clip DAO not initialized in ProjectDatabaseService',
        );
        return false;
      }

      // Create the clip companion for project database
      final clipCompanion = project_db.ClipsCompanion(
        trackId: Value(trackId),
        type: Value(type.name),
        name: Value('Clip ${DateTime.now().millisecondsSinceEpoch}'),
        sourcePath: Value(sourcePath),
        startTimeOnTrackMs: Value(startTimeOnTrackMs),
        startTimeInSourceMs: Value(startTimeInSourceMs),
        endTimeInSourceMs: Value(endTimeInSourceMs),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      );

      // Insert the clip
      final newClipId = await _projectDatabaseService.clipDao!.insertClip(clipCompanion);
      
      if (newClipId <= 0) {
        logError(
          _logTag,
          'Failed to insert clip into database',
        );
        return false;
      }

      // Get the inserted clip
      final dbData = await _projectDatabaseService.clipDao!.getClipById(newClipId);
      if (dbData == null) {
        logError(
          _logTag,
          'Inserted clip not found in database: ID $newClipId',
        );
        return false;
      }

      final newClip = clipFromProjectDb(dbData);
      final updatedClips = [...clipsNotifier.value, newClip];
      clipsNotifier.value = updatedClips;
      _recalculateAndUpdateTotalFrames();

      logInfo(
        _logTag,
        'Added new clip with ID $newClipId',
      );
      return true;
    } catch (e) {
      logError(
        _logTag,
        'Error adding clip: $e',
      );
      return false;
    }
  }
}
