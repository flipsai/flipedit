import 'dart:async';

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;

import 'package:flipedit/viewmodels/timeline_utils.dart';
import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/services/timeline_logic_service.dart';

class TimelineViewModel {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();

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
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

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

  StreamSubscription? _controllerPositionSubscription;

  StreamSubscription? _clipStreamSubscription;

  /// Executes a timeline command and refreshes undo stack
  Future<void> runCommand(TimelineCommand cmd) async {
    await cmd.execute();
    await _undoRedoService.init();
  }

  /// Undoes the last operation via service
  Future<void> undo() async {
    await _undoRedoService.undo();
  }

  /// Redoes the last undone operation via service
  Future<void> redo() async {
    await _undoRedoService.redo();
  }

  /// Notifiers for UI binding
  ValueNotifier<bool> get canUndoNotifier => _undoRedoService.canUndo;
  ValueNotifier<bool> get canRedoNotifier => _undoRedoService.canRedo;

  // Expose project database for commands
  ProjectDatabaseService get projectDatabaseService => _projectDatabaseService;

  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    isPlayingNotifier.value = true;
    logger.logInfo('▶️ Starting playback from frame $currentFrame', _logTag);
  }

  // Removed method to update current frame based on engine position during playback
  // as playhead is now fixed

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    isPlayingNotifier.value = false;
    logger.logInfo('⏹️ Stopping playback at frame $currentFrame', _logTag);
  }

  Future<void> loadClipsForProject(int projectId) async {
    logger.logInfo('🔄 Loading clips for project $projectId', _logTag);

    final success = await _projectDatabaseService.loadProject(projectId);
    if (!success) {
      logger.logError('❌ Failed to load project $projectId', _logTag);
      clipsNotifier.value = [];
      recalculateAndUpdateTotalFrames();
      return;
    }

    final tracks = _projectDatabaseService.tracksNotifier.value;
    currentTrackIds = tracks.map((t) => t.id).toList();
    logger.logInfo(
      '📊 Loaded ${tracks.length} tracks with IDs: $currentTrackIds',
      _logTag,
    );

    if (tracks.isEmpty) {
      logger.logInfo('⚠️ No tracks found for project $projectId', _logTag);
      clipsNotifier.value = [];
      recalculateAndUpdateTotalFrames();
      return;
    }

    await refreshClips();
  }
  
  /// Updates the UI state after clip placement (called by commands after persistence)
  void updateClipsAfterPlacement(List<ClipModel> updatedClips) {
    clipsNotifier.value = updatedClips;
    recalculateAndUpdateTotalFrames();
  }
  
  /// Legacy method for backward compatibility - delegates to command pattern
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
    
    // For new clips, use the command pattern
    if (clipId == null) {
      final clipData = ClipModel(
        databaseId: null,
        trackId: trackId,
        name: '',
        type: type,
        sourcePath: sourcePath,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
        startTimeOnTrackMs: startTimeOnTrackMs,
        effects: [],
        metadata: {},
      );
      
      // Create an instance of the AddClipCommand class (imported at the top of the file)
      final command = AddClipCommand(
        vm: this,
        clipData: clipData,
        trackId: trackId,
        // Pass the required startTimeOnTrackMs from the method's arguments
        startTimeOnTrackMs: startTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );
      
      await runCommand(command);
      return true;
    } else {
      // For existing clips, use the old direct approach for now
      // This could be refactored to use a MoveClipCommand or similar
      final placement = _timelineLogicService.prepareClipPlacement(
        clips: clips, // Pass the current clips
        clipId: clipId,
        trackId: trackId,
        type: type,
        sourcePath: sourcePath,
        startTimeOnTrackMs: startTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );
      
      if (!placement['success']) return false;
      
      // Apply updates to database
      for (final update in placement['clipUpdates']) {
        await _projectDatabaseService.clipDao!.updateClipFields(
          update['id'],
          update['fields'],
          log: false,
        );
      }
      
      // Remove clips
      for (final id in placement['clipsToRemove']) {
        await _projectDatabaseService.clipDao!.deleteClip(id);
      }
      
      // Update existing clip
      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        {
          'trackId': trackId,
          'startTimeOnTrackMs': placement['newClipData']['startTimeOnTrackMs'],
          'startTimeInSourceMs': placement['newClipData']['startTimeInSourceMs'],
          'endTimeInSourceMs': placement['newClipData']['endTimeInSourceMs'],
        },
        log: true,
      );
      
      // Update UI
      clipsNotifier.value = placement['updatedClips'];
      recalculateAndUpdateTotalFrames();
      
      await _undoRedoService.init();
      logger.logInfo('Moved/resized clip $clipId (optimistic update)', _logTag);
      return true;
    }
  }

  /// Handles dropping a clip onto an empty timeline by creating a new track and placing the clip.
  Future<bool> handleClipDropToEmptyTimeline({
    required ClipModel clip,
    required int startTimeOnTrackMs,
  }) async {
    final databaseService = _projectDatabaseService;
    final newTrackId = await databaseService.addTrack(
      name: 'Track 1',
      type: clip.type.name,
    );
    if (newTrackId == null) {
      logger.logError('Failed to create new track', _logTag);
      return false;
    }
    logger.logInfo('New track created with ID: $newTrackId', _logTag);

    final success = await placeClipOnTrack(
      trackId: newTrackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
    );
    if (success) {
      logger.logInfo(
        'Clip "${clip.name}" added to new track $newTrackId',
        _logTag,
      );
    } else {
      logger.logError('Failed to add clip to new track $newTrackId', _logTag);
    }
    return success;
  }

  /// Updates the name of a track.
  Future<bool> updateTrackName(int trackId, String newName) async {
    final success = await _projectDatabaseService.updateTrackName(
      trackId,
      newName,
    );
    if (success) {
      logger.logInfo('Track $trackId renamed to "$newName"', _logTag);
    } else {
      logger.logError('Failed to rename track $trackId', _logTag);
    }
    return success;
  }

  /// Handles dropping a clip onto a track at the specified start time.
  Future<bool> handleClipDrop({
    required ClipModel clip,
    required int trackId,
    required int startTimeOnTrackMs,
  }) async {
    final success = await placeClipOnTrack(
      trackId: trackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
    );
    if (success) {
      logger.logInfo(
        'Clip "${clip.name}" added to track $trackId at $startTimeOnTrackMs ms',
        _logTag,
      );
    } else {
      logger.logError('Failed to add clip to track $trackId', _logTag);
    }
    return success;
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
    recalculateAndUpdateTotalFrames(); // Updated call
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

  // Made public for commands to call when necessary
  void recalculateAndUpdateTotalFrames() {
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
    trackLabelWidthNotifier.dispose(); // Added back disposal
    currentEditMode.dispose();

    trackContentHorizontalScrollController.dispose();

    _controllerPositionSubscription?.cancel();
    _clipStreamSubscription?.cancel();
  }
}

