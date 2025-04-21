import 'dart:async';
import 'dart:io'; // Added for File access
import 'package:drift/drift.dart' as drift; // Added Value import

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/utils/logger.dart' as logger; // Import logger
import 'package:flipedit/viewmodels/timeline_utils.dart';

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

  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(
    EditMode.select,
  );

  // Helper to set edit mode and notify
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;
  StreamSubscription? _clipStreamSubscription;

  late final VoidCallback _debouncedFrameUpdate;

  TimelineViewModel(this._projectDatabaseService) {
    _recalculateAndUpdateTotalFrames();

    _debouncedFrameUpdate = debounce(() {
      if (!isPlayingNotifier.value) return;

      final currentMs = ClipModel.framesToMs(currentFrame);
      final nextFrameMs = currentMs + (1000 / kDefaultFrameRate);
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
    }, Duration(milliseconds: (1000 / kDefaultFrameRate).round()));
  }

  Future<void> loadClipsForProject(int projectId) async {
    logger.logInfo('🔄 Loading clips for project $projectId', _logTag);

    // Load the project using the service
    final success = await _projectDatabaseService.loadProject(projectId);
    if (!success) {
      logger.logError('❌ Failed to load project $projectId', _logTag);
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    // Use the tracks from the service
    final tracks = _projectDatabaseService.tracksNotifier.value;

    currentTrackIds = tracks.map((t) => t.id).toList();
    logger.logInfo(
      '📊 Loaded ${tracks.length} tracks with IDs: $currentTrackIds',
      _logTag,
    );

    if (tracks.isEmpty) {
      logger.logInfo('⚠️ No tracks found for project $projectId', _logTag);
      clipsNotifier.value = [];
      _recalculateAndUpdateTotalFrames();
      return;
    }

    await refreshClips();
  }

  void _updateFrameFromController() {
    if (_videoPlayerController != null &&
        _videoPlayerController!.value.isInitialized) {
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
  int calculateFramePosition(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
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
  int calculateMsPositionFromPixels(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    final framePosition = calculateFramePosition(
      pixelPosition,
      scrollOffset,
      zoom,
    );
    return frameToMs(framePosition);
  }

  /// Centralized utility to place a clip on a track, trimming/removing/splitting neighbors as needed
  Future<bool> placeClipOnTrack({
    int? clipId, // If updating an existing clip
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) async {
    if (_projectDatabaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return false;
    }
    final newClipDuration = endTimeInSourceMs - startTimeInSourceMs;
    int newStart = startTimeOnTrackMs;
    int newEnd = startTimeOnTrackMs + newClipDuration;
    // 1. Gather and sort neighbors
    final neighbors =
        clips
            .where(
              (c) =>
                  c.trackId == trackId &&
                  (clipId == null || c.databaseId != clipId),
            )
            .toList()
          ..sort(
            (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
          );
    // 2. Trim or remove neighbors (no splitting)
    bool changed = false;
    List<ClipModel> updatedClips = List<ClipModel>.from(clips);
    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;
      if (ne <= newStart || ns >= newEnd) continue; // No overlap
      if (ns >= newStart && ne <= newEnd) {
        updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
        changed = true;
        await removeClip(neighbor.databaseId!);
      } else if (ns < newStart && ne > newStart && ne <= newEnd) {
        // Overlap on right: trim neighbor's end to the intersection
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] =
            updated;
        changed = true;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighbor.databaseId!,
          {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        );
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
        // Overlap on left: trim neighbor's start to the intersection
        final updated = neighbor.copyWith(
          startTimeInSourceMs: neighbor.startTimeInSourceMs + (newEnd - ns),
          startTimeOnTrackMs: newEnd,
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] =
            updated;
        changed = true;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighbor.databaseId!,
          {
            'startTimeInSourceMs': neighbor.startTimeInSourceMs + (newEnd - ns),
            'startTimeOnTrackMs': newEnd,
          },
        );
      } else if (ns < newStart && ne > newEnd) {
        // Moved clip is fully inside neighbor: trim neighbor's end to newStart (left part remains)
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] =
            updated;
        changed = true;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighbor.databaseId!,
          {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        );
      }
      // NEW CASE: If the left neighbor's end overlaps the new start, trim its end to newStart
      else if (ne > newStart && ne <= newEnd && ns < newStart) {
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] =
            updated;
        changed = true;
        await _projectDatabaseService.clipDao!.updateClipFields(
          neighbor.databaseId!,
          {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        );
      }
    }
    // 3. Clamp new clip to available space
    int clampLeft = 0;
    int clampRight = 1 << 30;
    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;
      if (ne <= newStart) {
        if (ne > clampLeft) clampLeft = ne;
      }
      if (ns >= newEnd) {
        if (ns < clampRight) clampRight = ns;
      }
    }
    newStart = newStart.clamp(clampLeft, clampRight - 1);
    newEnd = (newStart + newClipDuration).clamp(clampLeft + 1, clampRight);
    if (newEnd <= newStart) return false;
    // 4. Add or update the clip
    if (clipId == null) {
      // Insert new
      final newClipId = await _projectDatabaseService.clipDao!.insertClip(
        project_db.ClipsCompanion(
          trackId: drift.Value(trackId),
          type: drift.Value(type.name),
          sourcePath: drift.Value(sourcePath),
          startTimeOnTrackMs: drift.Value(newStart),
          startTimeInSourceMs: drift.Value(startTimeInSourceMs),
          endTimeInSourceMs: drift.Value(
            startTimeInSourceMs + (newEnd - newStart),
          ),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      // Optimistically add to memory
      updatedClips.add(
        ClipModel(
          databaseId: newClipId,
          trackId: trackId,
          name: '',
          type: type,
          sourcePath: sourcePath,
          startTimeInSourceMs: startTimeInSourceMs,
          endTimeInSourceMs: startTimeInSourceMs + (newEnd - newStart),
          startTimeOnTrackMs: newStart,
          effects: [],
          metadata: {},
        ),
      );
      changed = true;
      clipsNotifier.value = List<ClipModel>.from(updatedClips);
      await refreshClips();
      logger.logInfo(
        'Added new clip with ID $newClipId (auto-trimmed)',
        _logTag,
      );
      return true;
    } else {
      // Update existing
      final idx = updatedClips.indexWhere((c) => c.databaseId == clipId);
      if (idx != -1) {
        updatedClips[idx] = updatedClips[idx].copyWith(
          trackId: trackId,
          startTimeOnTrackMs: newStart,
          startTimeInSourceMs: startTimeInSourceMs,
          endTimeInSourceMs: startTimeInSourceMs + (newEnd - newStart),
        );
        changed = true;
      }
      clipsNotifier.value = List<ClipModel>.from(updatedClips);
      await _projectDatabaseService.clipDao!.updateClipFields(clipId, {
        'trackId': trackId,
        'startTimeOnTrackMs': newStart,
        'startTimeInSourceMs': startTimeInSourceMs,
        'endTimeInSourceMs': startTimeInSourceMs + (newEnd - newStart),
        'updatedAt': DateTime.now(),
      });
      await refreshClips();
      logger.logInfo('Moved/resized clip $clipId (auto-trimmed)', _logTag);
      return true;
    }
  }

  Future<bool> addClip({
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) async {
    return await placeClipOnTrack(
      trackId: trackId,
      type: type,
      sourcePath: sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
    );
  }

  Future<bool> moveClip({
    required int clipId,
    required int newTrackId,
    required int newStartTimeOnTrackMs,
  }) async {
    final clip = clips.firstWhere(
      (c) => c.databaseId == clipId,
      orElse: () => throw Exception('Clip not found'),
    );
    return await placeClipOnTrack(
      clipId: clipId,
      trackId: newTrackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: newStartTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
    );
  }

  Future<bool> resizeClip({
    required int clipId,
    required String direction, // 'left' or 'right'
    required int newFrame,
  }) async {
    final clip = clips.firstWhere(
      (c) => c.databaseId == clipId,
      orElse: () => throw Exception('Clip not found'),
    );
    int newStart = clip.startTimeOnTrackMs;
    int newEnd = clip.startTimeOnTrackMs + clip.durationMs;
    if (direction == 'left') {
      newStart = ClipModel.framesToMs(newFrame);
    } else if (direction == 'right') {
      newEnd = ClipModel.framesToMs(newFrame);
    }
    return await placeClipOnTrack(
      clipId: clipId,
      trackId: clip.trackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: newStart,
      startTimeInSourceMs:
          clip.startTimeInSourceMs + (newStart - clip.startTimeOnTrackMs),
      endTimeInSourceMs:
          clip.startTimeInSourceMs + (newEnd - clip.startTimeOnTrackMs),
    );
  }

  Future<bool> removeClip(int clipId) async {
    if (_projectDatabaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return false;
    }
    try {
      await _projectDatabaseService.clipDao!.deleteClip(clipId);
      await refreshClips();
      logger.logInfo('Removed clip with ID $clipId', _logTag);
      return true;
    } catch (e) {
      logger.logError('Error removing clip: $e', _logTag);
      return false;
    }
  }

  Future<void> refreshClips() async {
    if (_projectDatabaseService.clipDao == null) return;
    // Aggregate all clips from all tracks
    final tracks = _projectDatabaseService.tracksNotifier.value;
    List<ClipModel> allClips = [];
    for (final track in tracks) {
      final dbClips = await _projectDatabaseService.clipDao!.getClipsForTrack(
        track.id,
      );
      allClips.addAll(dbClips.map(clipFromProjectDb));
    }
    allClips.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );
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
        Duration(milliseconds: (1000 / kDefaultFrameRate).round()),
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
        logger.logError("Error: Video file not found at $videoPath", _logTag);
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

      logger.logInfo('Video loaded for preview: $videoPath', _logTag);
    } catch (e) {
      logger.logError("Error initializing video player: $e", _logTag);
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

  void onDispose() {
    logger.logInfo('Disposing TimelineViewModel', _logTag);
    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    isPlayingNotifier.dispose();
    videoPlayerControllerNotifier.dispose();
    trackLabelWidthNotifier.dispose(); // Added back disposal
    currentEditMode.dispose();

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

    logger.logInfo(
      'addClipAtPosition called: trackId=$trackId, clip=${clipData.name}, type=${clipData.type}',
      _logTag,
    );

    // Update currentTrackIds from the database service to ensure it's current
    final tracks = _projectDatabaseService.tracksNotifier.value;
    currentTrackIds = tracks.map((t) => t.id).toList();

    logger.logInfo('Available track IDs: $currentTrackIds', _logTag);

    if (!currentTrackIds.contains(trackId)) {
      logger.logError(
        'Track ID $trackId is not in current tracks list: $currentTrackIds',
        _logTag,
      );
      // Continue anyway - the track might exist but not be in our cached list
    }

    if (localPositionX != null && scrollOffsetX != null) {
      targetStartTimeMs = calculateMsPositionFromPixels(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
      logger.logInfo(
        'Calculated position: localX=$localPositionX, scrollX=$scrollOffsetX, targetMs=$targetStartTimeMs',
        _logTag,
      );
    } else {
      targetStartTimeMs = ClipModel.framesToMs(currentFrame);
      logger.logInfo(
        'Using current frame position: frame=$currentFrame, targetMs=$targetStartTimeMs',
        _logTag,
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

    logger.logInfo('addClip result: $result', _logTag);
  }

  Future<bool> createTimelineClip({
    required int trackId,
    required ClipModel clipData,
    required int framePosition,
  }) async {
    logger.logInfo(
      'Creating timeline clip at frame $framePosition on track $trackId for ${clipData.name}',
      _logTag,
    );

    // Convert the frame position to milliseconds using the helper method
    final startTimeOnTrackMs = frameToMs(framePosition);

    // Additional debug info about timing
    final clipDurationFrames = ClipModel.msToFrames(clipData.durationMs);
    logger.logInfo(
      'Frame metrics: startFrame=$framePosition, durationFrames=$clipDurationFrames, startTimeMs=$startTimeOnTrackMs',
      _logTag,
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

  /// Roll edit between two adjacent clips: moves the boundary between them.
  /// [leftClipId] is the left clip, [rightClipId] is the right clip, [newBoundaryFrame] is the new frame for the boundary.
  /// Returns true if successful, false if constraints prevent the operation.
  Future<bool> rollEditClips({
    required int leftClipId,
    required int rightClipId,
    required int newBoundaryFrame,
  }) async {
    final left = clips.firstWhere(
      (c) => c.databaseId == leftClipId,
      orElse: () => throw Exception('Left clip not found'),
    );
    final right = clips.firstWhere(
      (c) => c.databaseId == rightClipId,
      orElse: () => throw Exception('Right clip not found'),
    );
    // Must be on same track and adjacent
    if (left.trackId != right.trackId) return false;
    if (left.endFrame != right.startFrame) return false;
    // Compute valid range for the boundary
    final leftMinBoundary = left.startFrame + 1;
    final leftMaxBoundary =
        left.startFrame + (left.endFrameInSource - left.startFrameInSource);
    final rightMinBoundary =
        right.endFrame - (right.endFrameInSource - right.startFrameInSource);
    final rightMaxBoundary = right.endFrame - 1;
    // The valid range is the intersection of both
    final minBoundary = [
      leftMinBoundary,
      rightMinBoundary,
    ].reduce((a, b) => a > b ? a : b);
    final maxBoundary = [
      leftMaxBoundary,
      rightMaxBoundary,
    ].reduce((a, b) => a < b ? a : b);
    final clampedBoundary = newBoundaryFrame.clamp(minBoundary, maxBoundary);
    if (clampedBoundary <= left.startFrame || clampedBoundary >= right.endFrame)
      return false;
    // Compute new times
    final newLeftEndMs = ClipModel.framesToMs(clampedBoundary);
    final newRightStartMs = ClipModel.framesToMs(clampedBoundary);
    final newLeftEndInSourceMs =
        left.startTimeInSourceMs + (newLeftEndMs - left.startTimeOnTrackMs);
    final newRightStartInSourceMs =
        right.startTimeInSourceMs +
        (newRightStartMs - right.startTimeOnTrackMs);
    // --- FIX: Always update right's startTimeOnTrackMs to match boundary ---
    await _projectDatabaseService.clipDao!.updateClipFields(left.databaseId!, {
      'endTimeInSourceMs': newLeftEndInSourceMs,
    });
    await _projectDatabaseService.clipDao!.updateClipFields(right.databaseId!, {
      'startTimeOnTrackMs': newRightStartMs,
      'startTimeInSourceMs': newRightStartInSourceMs,
    });
    await refreshClips();
    return true;
  }

  /// Trims, removes, or splits clips that overlap with [startMs, endMs) on [trackId]. Optionally excludes a clip by ID.
  Future<void> trimOrRemoveOverlappingClips(
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) async {
    final overlapping = getOverlappingClips(
      trackId,
      startMs,
      endMs,
      excludeClipId,
    );
    for (final clip in overlapping) {
      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.startTimeOnTrackMs + clip.durationMs;
      // Fully covered: remove
      if (clipStart >= startMs && clipEnd <= endMs) {
        await removeClip(clip.databaseId!);
      } else if (clipStart < endMs && clipEnd > endMs) {
        // Overlap on left: trim neighbor's start (neighbor is to the right of the new clip)
        if (clip.databaseId != null) {
          final neighborClip = clip; // Use a clearer variable name
          final amountToTrimMs =
              endMs -
              neighborClip
                  .startTimeOnTrackMs; // Calculate trim amount explicitly

          // Ensure we don't trim more than the clip's duration
          if (amountToTrimMs >= neighborClip.durationMs) {
            // If the overlap implies the entire neighbor clip should be removed
            await _projectDatabaseService.clipDao!.deleteClip(
              neighborClip.databaseId!,
            );
            // Log this removal for clarity
            logger.logInfo(
              'Neighbor clip ${neighborClip.databaseId} fully overlapped and removed.',
              _logTag,
            );
          } else if (amountToTrimMs > 0) {
            // Only update if there's actually something to trim
            final newStartTimeInSourceMs =
                neighborClip.startTimeInSourceMs + amountToTrimMs;
            final newStartTimeOnTrackMs =
                endMs; // Set the neighbor's start time to the new clip's end time

            await _projectDatabaseService.clipDao!.updateClipFields(
              neighborClip.databaseId!,
              {
                'startTimeInSourceMs': newStartTimeInSourceMs,
                'startTimeOnTrackMs':
                    newStartTimeOnTrackMs, // Update track start time
              },
            );
            // Log the update
            logger.logDebug(
              'Neighbor clip ${neighborClip.databaseId} trimmed (left): new track start $newStartTimeOnTrackMs ms, new source start $newStartTimeInSourceMs ms.',
              _logTag,
            );
          } else {
            // Log if no trim was needed (e.g., endMs exactly matched clipStart)
            logger.logDebug(
              'Neighbor clip ${neighborClip.databaseId} touches new clip end, no trim needed.',
              _logTag,
            );
          }
        }
      } else if (clipStart < startMs && clipEnd > startMs) {
        // Overlap on right: trim neighbor's end
        await _projectDatabaseService.clipDao!.updateClipFields(
          clip.databaseId!,
          {
            'endTimeInSourceMs':
                clip.startTimeInSourceMs + (startMs - clipStart),
          },
        );
      } else if (clipStart < endMs && clipEnd > endMs) {
        // Overlap on left: trim neighbor's start
        await _projectDatabaseService.clipDao!
            .updateClipFields(clip.databaseId!, {
              'startTimeInSourceMs':
                  clip.startTimeInSourceMs + (endMs - clipStart),
              'startTimeOnTrackMs': endMs,
            });
      }
    }
    await refreshClips();
  }

  /// Returns all clips on the same track that overlap with [startMs, endMs). Optionally excludes a clip by ID.
  List<ClipModel> getOverlappingClips(
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) {
    return clips.where((clip) {
      if (clip.trackId != trackId) return false;
      if (excludeClipId != null && clip.databaseId == excludeClipId)
        return false;
      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.startTimeOnTrackMs + clip.durationMs;
      // Overlap if ranges intersect
      return clipStart < endMs && clipEnd > startMs;
    }).toList();
  }

  /// Returns a preview of the timeline clips as if a clip were dragged to a new position, applying trimming logic in-memory only.
  List<ClipModel> getPreviewClipsForDrag({
    required int clipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    final original = clips;
    final dragged = original.firstWhere((c) => c.databaseId == clipId);
    final newClipDuration = dragged.durationMs;
    int newStart = targetStartTimeOnTrackMs;
    int newEnd = targetStartTimeOnTrackMs + newClipDuration;
    // Remove the dragged clip from the list
    final others = original.where((c) => c.databaseId != clipId).toList();
    List<ClipModel> preview = [];
    for (final neighbor in others) {
      if (neighbor.trackId != targetTrackId) {
        preview.add(neighbor);
        continue;
      }
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;
      if (ne <= newStart || ns >= newEnd) {
        preview.add(neighbor);
      } else if (ns >= newStart && ne <= newEnd) {
        // Fully covered: remove
        continue;
      } else if (ns < newStart && ne > newStart && ne <= newEnd) {
        // Overlap on right: trim neighbor's end
        preview.add(
          neighbor.copyWith(
            endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
          ),
        );
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
        // Overlap on left: trim neighbor's start
        preview.add(
          neighbor.copyWith(
            startTimeInSourceMs: neighbor.startTimeInSourceMs + (newEnd - ns),
            startTimeOnTrackMs: newEnd,
          ),
        );
      } else if (ns < newStart && ne > newEnd) {
        // Dragged clip is fully inside neighbor: only left part remains (trim at newStart)
        preview.add(
          neighbor.copyWith(
            endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
          ),
        );
      }
    }
    // Add the dragged clip at the preview position
    preview.add(
      dragged.copyWith(
        trackId: targetTrackId,
        startTimeOnTrackMs: newStart,
        // Optionally update startTimeInSourceMs/endTimeInSourceMs if you want to preview source trim
      ),
    );
    // Sort by start time
    preview.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );
    return preview;
  }
}
