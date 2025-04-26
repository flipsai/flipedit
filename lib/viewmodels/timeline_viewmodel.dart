import 'dart:async';

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;

import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/services/timeline_logic_service.dart';

class TimelineViewModel extends ChangeNotifier {
  // Add a tag for logging within this class
  void notifyClipsChanged() { // Explicit notification method for clarity
    notifyListeners();
  }
  String get _logTag => runtimeType.toString();

  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();

  // --- State Notifiers ---
  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);
  
  // Helper to check if timeline can be scrolled (has clips)
  bool get canScroll => clipsNotifier.value.isNotEmpty;

  List<int> currentTrackIds = [];

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    if (zoomNotifier.value == value || value < 0.1 || value > 5.0) return;
    zoomNotifier.value = value;
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  static const DEFAULT_EMPTY_DURATION = 600000; // 10 minutes in milliseconds
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFrames = _calculateTotalFrames();
    // Clamp to content duration when present
    final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : ClipModel.msToFrames(DEFAULT_EMPTY_DURATION);
    final clampedValue = value.clamp(0, maxAllowedFrame);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);

  final ValueNotifier<int> timelineEndNotifier = ValueNotifier<int>(0);
  int get timelineEnd => timelineEndNotifier.value;

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  // Added back Notifier for the width of the track label area
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier(120.0);
  double get trackLabelWidth => trackLabelWidthNotifier.value;

  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(
    EditMode.select,
  );
  
  // Notifier for the playhead lock state
  final ValueNotifier<bool> isPlayheadLockedNotifier = ValueNotifier<bool>(false);
  bool get isPlayheadLocked => isPlayheadLockedNotifier.value;

  // Helper to set edit mode and notify
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  // --- Scroll Command Stream ---
  // Notifies the View to scroll to a specific frame.
  final StreamController<int> _scrollToFrameController = StreamController<int>.broadcast();
  Stream<int> get scrollToFrameStream => _scrollToFrameController.stream;
// Scroll to frame handler callback (registered by the view)
  void Function(int frame)? _scrollToFrameHandler;

  /// Allows the view to register a handler for scroll-to-frame actions.
  void registerScrollToFrameHandler(void Function(int frame) handler) {
    _scrollToFrameHandler = handler;
  }

  // Internal listeners
  StreamSubscription? _controllerPositionSubscription;
  StreamSubscription? _clipStreamSubscription;
  List<VoidCallback> _internalListeners = [];

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

  // Timer for continuous frame advancement during playback
  Timer? _playbackTimer;

  // FPS for playback - TODO: Get this from project settings
  final int _fps = 30;

  /// Constructor - Sets up internal listeners
  TimelineViewModel() {
    logger.logInfo('Initializing TimelineViewModel and listeners', _logTag);
    _setupInternalListeners();
    _setupDatabaseListeners(); // Add call to new database listener setup
  }

  void _setupInternalListeners() {
    // Combine listeners for scroll logic
    VoidCallback listener = _checkAndTriggerScroll;
    isPlayingNotifier.addListener(listener);
    isPlayheadLockedNotifier.addListener(listener);
    currentFrameNotifier.addListener(listener);

    // Keep track to remove them later
    _internalListeners.addAll([listener, listener, listener]); // Add references for removal
  }

  // Setup listeners for database changes that affect the timeline state
  void _setupDatabaseListeners() {
    // Listen to changes in the tracks list from the database service
    final tracksListener = () {
      logger.logInfo('👂 Tracks list changed in ProjectDatabaseService. Refreshing clips...', _logTag);
      refreshClips(); // Refresh clips when tracks change
    };
    _projectDatabaseService.tracksNotifier.addListener(tracksListener);
    _internalListeners.add(tracksListener); // Keep track for disposal
  }

  /// Checks conditions and emits scroll command if necessary.
  void _checkAndTriggerScroll() {
    final bool isPlaying = isPlayingNotifier.value;
    final bool isLocked = isPlayheadLockedNotifier.value;
    final int frame = currentFrameNotifier.value;

    // Only trigger scroll if playing, locked, and on a 20-frame interval
    if (isPlaying && isLocked && frame % 20 == 0) {
      logger.logDebug('ViewModel emitting scroll to frame: $frame', _logTag);
      // Call the registered handler instead of emitting to a stream
      _scrollToFrameHandler?.call(frame);
    }
  }
  
  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    isPlayingNotifier.value = true;
    logger.logInfo('▶️ Starting playback from frame $currentFrame', _logTag);
    
    // Start a timer that advances the frame at the specified FPS
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(Duration(milliseconds: (1000 / _fps).round()), (timer) {
      // Advance to next frame
      final nextFrame = currentFrame + 1;
      final totalFrames = totalFramesNotifier.value;
      // Use full duration including empty canvas buffer
      final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : ClipModel.msToFrames(DEFAULT_EMPTY_DURATION);
      
      if (nextFrame > maxAllowedFrame) {
        // Stop at the safe end of the timeline
        stopPlayback();
      } else {
        // Update current frame
        currentFrame = nextFrame;
      }
    });
  }

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    // Cancel the playback timer
    _playbackTimer?.cancel();
    _playbackTimer = null;
    
    isPlayingNotifier.value = false;
    logger.logInfo('⏹️ Stopping playback at frame $currentFrame', _logTag);
  }

  /// Toggles the playback state
  void togglePlayPause() {
    if (isPlayingNotifier.value) {
      stopPlayback();
    } else {
      startPlayback();
    }
  }

  /// Toggles the playhead lock state
  void togglePlayheadLock() {
    isPlayheadLockedNotifier.value = !isPlayheadLockedNotifier.value;
     logger.logInfo('🔒 Playhead Lock toggled: ${isPlayheadLockedNotifier.value}', _logTag);
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
    required int sourceDurationMs,
    required int startTimeOnTrackMs,
    required int endTimeOnTrackMs,
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
        name: '', // Consider deriving name from sourcePath
        type: type,
        sourcePath: sourcePath,
        sourceDurationMs: sourceDurationMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs, // This will be clamped by constructor/service
        startTimeOnTrackMs: startTimeOnTrackMs,
        endTimeOnTrackMs: endTimeOnTrackMs, 
        effects: [],
        metadata: {},
      );
      
      // Create an instance of the AddClipCommand class (imported at the top of the file)
      final command = AddClipCommand(
        vm: this,
        clipData: clipData, // Contains all necessary source info
        trackId: trackId,
        startTimeOnTrackMs: startTimeOnTrackMs, // Only track start time is needed here
        // Removed startTimeInSourceMs, endTimeInSourceMs
      );
      
      await runCommand(command);
      return true;
    } else {
      // For existing clips, use the old direct approach for now
      // This handles updates (moves/resizes) using the logic service
      final placement = _timelineLogicService.prepareClipPlacement(
        clips: clips, // Pass the current clips from the notifier
        clipId: clipId,
        trackId: trackId,
        type: type,
        sourcePath: sourcePath,
        sourceDurationMs: sourceDurationMs, // Added
        startTimeOnTrackMs: startTimeOnTrackMs,
        endTimeOnTrackMs: endTimeOnTrackMs, // Added
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs, // Logic service will clamp this
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
          'endTimeOnTrackMs': placement['newClipData']['endTimeOnTrackMs'], // Added
          'startTimeInSourceMs': placement['newClipData']['startTimeInSourceMs'],
          'endTimeInSourceMs': placement['newClipData']['endTimeInSourceMs'], // This should be the clamped value from placement
          // sourceDurationMs likely doesn't change on move/resize, but could be updated if needed
        },
        log: true, // Enable logging for undo/redo
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
      sourceDurationMs: clip.sourceDurationMs, // Pass source duration
      startTimeOnTrackMs: startTimeOnTrackMs,
      // Calculate initial end time on track based on source duration for a new clip
      endTimeOnTrackMs: startTimeOnTrackMs + clip.durationInSourceMs,
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
      sourceDurationMs: clip.sourceDurationMs, // Pass source duration
      startTimeOnTrackMs: startTimeOnTrackMs,
      // Calculate initial end time on track based on source duration for a new clip
      endTimeOnTrackMs: startTimeOnTrackMs + clip.durationInSourceMs,
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
    // Preserve existing clips if database unavailable
    if (_projectDatabaseService.clipDao == null) {
      logger.logWarning('Clip DAO not available, cannot refresh clips.', _logTag);
      return;
    }
    if (_projectDatabaseService.currentDatabase == null) {
        logger.logWarning('Database connection not available, cannot refresh clips.', _logTag);
        return;
    }

    logger.logInfo('Refreshing clips from database...', _logTag);

    // Fetch all current tracks from the database service's notifier.
    // The tracksNotifier is updated when tracks are added/deleted via ProjectDatabaseService.
    final tracks = _projectDatabaseService.tracksNotifier.value;

    // Fetch *all* clips from the database. This is more reliable than fetching
    // per-track, especially after track deletions.
    // Assuming the clip DAO has a method to get all clips. If not, we might need to add one,
    // or iterate through tracks as before but clearing the list first.
    // Let's check ProjectDatabaseClipDao again quickly to be sure.
    // Based on previous read, it has getClipsForTrack but no getAllClips.
    // So, iterate through tracks and clear the list first.

    List<ClipModel> allClips = []; // Initialize as empty list to rebuild from scratch

    // Fetch clips for each *existing* track and add to the list
    for (final track in tracks.where((t) => t.id != null)) {
      final dbClips = await _projectDatabaseService.clipDao!.getClipsForTrack(track.id!);
      // Map dbClip data to ClipModel, ensuring required fields are provided
      allClips.addAll(dbClips.map((dbClip) {
         // Estimate source duration if missing from DB data
         final sourceDuration = dbClip.sourceDurationMs ?? (dbClip.endTimeInSourceMs - dbClip.startTimeInSourceMs).clamp(0, 1<<30);
         // The factory handles estimating endTimeOnTrackMs internally if needed

         // Use the factory constructor. Pass the dbData and the potentially estimated sourceDuration.
         return ClipModel.fromDbData(
            dbClip,
            sourceDurationMs: sourceDuration, // Pass optional estimated source duration
            // DO NOT pass endTimeOnTrackMs here - the factory handles it.
         );
      }));
    }

    // Sort clips by their start time on the track
    allClips.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );

    // Update the notifier if the list of clips has changed OR if it is now empty.
    // The second condition is needed to ensure the UI reacts when the timeline becomes empty,
    // even if the previous state was also an empty list (e.g., after project load).
    if (!listEquals(clipsNotifier.value, allClips) || allClips.isEmpty) {
      clipsNotifier.value = allClips;
      logger.logInfo('Clips list updated in ViewModel (${allClips.length} clips).', _logTag);
      recalculateAndUpdateTotalFrames(); // Updated call
    } else {
       logger.logInfo('Clips list in ViewModel is already up-to-date and not empty. Notifier not updated.', _logTag);
    }
  }

  int _calculateTotalFrames() {
    if (clipsNotifier.value.isEmpty) {
      return 0;
    }
    // Calculate the maximum end time across all clips
    int maxEndTimeMs = 0;
    for (final clip in clipsNotifier.value) {
      if (clip.endTimeOnTrackMs > maxEndTimeMs) {
        maxEndTimeMs = clip.endTimeOnTrackMs;
      }
    }
    timelineEndNotifier.value = maxEndTimeMs;
    return ClipModel.msToFrames(maxEndTimeMs);
  }

  void recalculateAndUpdateTotalFrames() {
    final totalFrames = _calculateTotalFrames();
    if (totalFramesNotifier.value != totalFrames) {
      totalFramesNotifier.value = totalFrames;
      logger.logInfo('Updated total frames to $totalFrames based on timeline end at ${timelineEndNotifier.value} ms', _logTag);
    }
  }

  bool listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Calculates the scroll offset needed to bring a specific frame into view.
  double calculateScrollOffsetForFrame(
    int frame,
    double viewportWidth,
    double trackLabelWidth,
    {double framePixelWidth = 5.0}
  ) {
    final double scrollableViewportWidth = viewportWidth - trackLabelWidth;
    if (scrollableViewportWidth <= 0) return 0.0; // Cannot calculate if viewport is too small

    final double framePosition = frame * zoom * framePixelWidth;
    final double unclampedTargetOffset = framePosition - (scrollableViewportWidth / 2.0);
    return unclampedTargetOffset;
  }

  /// Updates the width of the track label area.
  void updateTrackLabelWidth(double newWidth) {
    final clampedWidth = newWidth.clamp(80.0, 300.0);
    if (trackLabelWidthNotifier.value != clampedWidth) {
      trackLabelWidthNotifier.value = clampedWidth;
      logger.logInfo('Track label width updated to $clampedWidth', _logTag);
    }
  }
}
