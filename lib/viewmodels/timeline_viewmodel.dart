import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals; // Import foundation's listEquals

import 'package:collection/collection.dart'; // Keep this for other collection utilities if needed
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart' show Track; // Import Track

import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/services/playback_service.dart'; // Added
import 'package:flipedit/services/timeline_navigation_service.dart'; // Added
import 'commands/roll_edit_command.dart';
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
  // Services for delegation
  late final PlaybackService _playbackService;
  late final TimelineNavigationService _navigationService;

  // --- State Notifiers (Managed by this ViewModel) ---
  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);

  // Notifier for the width of the track label area (UI specific)
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier(120.0);
  double get trackLabelWidth => trackLabelWidthNotifier.value;

  // Notifier for the current editing mode (UI specific)
  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(
    EditMode.select,
  );

  // List of current track IDs (Managed here as it relates to DB state)
  List<int> currentTrackIds = [];

  // Notifier for the tracks list itself (Managed here, sourced from DB Service)
  final ValueNotifier<List<Track>> tracksListNotifier = ValueNotifier<List<Track>>([]);
  ValueNotifier<List<Track>> get tracksNotifierForView => tracksListNotifier; // Expose for the View

  // --- Delegated State Notifiers (from Services) ---
  ValueNotifier<double> get zoomNotifier => _navigationService.zoomNotifier;
  ValueNotifier<int> get currentFrameNotifier => _navigationService.currentFrameNotifier;
  ValueNotifier<int> get totalFramesNotifier => _navigationService.totalFramesNotifier;
  ValueNotifier<int> get timelineEndNotifier => _navigationService.timelineEndNotifier;
  ValueNotifier<bool> get isPlayingNotifier => _playbackService.isPlayingNotifier;
  ValueNotifier<bool> get isPlayheadLockedNotifier => _navigationService.isPlayheadLockedNotifier;

  // Expose navigation service for commands/views that need direct access
  TimelineNavigationService get navigationService {
    return _navigationService;
  }
  // --- Delegated Getters/Setters ---
  double get zoom => _navigationService.zoom;
  set zoom(double value) => _navigationService.zoom = value;

  int get currentFrame => _navigationService.currentFrame;
  set currentFrame(int value) => _navigationService.currentFrame = value;

  int get totalFrames => _navigationService.totalFrames;
  int get timelineEnd => _navigationService.timelineEnd;
  bool get isPlaying => _playbackService.isPlaying;
  bool get isPlayheadLocked => _navigationService.isPlayheadLocked;

  // Helper to check if timeline can be scrolled (has clips)
  bool get canScroll => clipsNotifier.value.isNotEmpty;

  // Helper to set edit mode and notify
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  // Removed: void registerScrollToFrameHandler(...) - Replaced by listening to scrollToFrameRequestNotifier

  List<VoidCallback> _internalListeners = [];
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

  /// Constructor - Sets up internal listeners
  TimelineViewModel() {
    logger.logInfo('Initializing TimelineViewModel and listeners', _logTag);

    // Instantiate services and wire dependencies
    _navigationService = TimelineNavigationService(
      getClips: _getClipsForNavService, // Provide function to get clips
      getIsPlaying: _getIsPlayingForNavService, // Provide function to get playback state
    );

    _playbackService = PlaybackService(
      getCurrentFrame: _navigationService.getCurrentFrameValue,
      setCurrentFrame: _navigationService.setCurrentFrameValue,
      getTotalFrames: _navigationService.getTotalFramesValue,
      getDefaultEmptyDurationFrames: _navigationService.getDefaultEmptyDurationFramesValue,
    );

    _setupDatabaseListeners();
    _setupClipListeners(); // Listen to clip changes to update navigation service
  }

  // Helper functions to provide dependencies to services
  List<ClipModel> _getClipsForNavService() => clipsNotifier.value;
  bool _getIsPlayingForNavService() => _playbackService.isPlaying;

  // Setup listeners for database changes that affect the timeline state
  void _setupDatabaseListeners() {
    // Listen to changes in the tracks list from the database service
    final tracksListener = () {
      logger.logInfo('👂 Tracks list changed in ProjectDatabaseService. Refreshing clips...', _logTag);
      tracksListNotifier.value = _projectDatabaseService.tracksNotifier.value; // Update exposed notifier
      refreshClips(); // Refresh clips, which will also update navigation service
    };
    _projectDatabaseService.tracksNotifier.addListener(tracksListener);
    _internalListeners.add(tracksListener); // Keep track for disposal
  }

  /// Setup listener for clip changes to trigger total frame recalculation.
  void _setupClipListeners() {
    final clipListener = () {
      logger.logDebug('👂 Clips list changed in ViewModel. Notifying NavigationService.', _logTag);
      _navigationService.recalculateAndUpdateTotalFrames();
    };
    clipsNotifier.addListener(clipListener);
    _internalListeners.add(clipListener); // Keep track for disposal
  }

  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    await _playbackService.startPlayback();
    // Playback service notifies its own listeners
    _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
  }

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    _playbackService.stopPlayback();
    // Playback service notifies its own listeners
     _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
  }

  /// Toggles the playback state
  void togglePlayPause() {
    _playbackService.togglePlayPause();
    // Playback service notifies its own listeners
    // Incorrectly placed deleteTrack method was here. Removed it.
    _navigationService.recalculateAndUpdateTotalFrames(); // Ensure nav state is aware
  }

  /// Toggles the playhead lock state
  void togglePlayheadLock() {
    _navigationService.togglePlayheadLock();
    // Navigation service notifies its own listeners
  }
/// Deletes a track by its ID.
  Future<void> deleteTrack(int trackId) async {
    try {
      await _projectDatabaseService.deleteTrack(trackId);
      logger.logInfo('Deleted track $trackId via ViewModel', _logTag);
      // Refreshing clips/tracks is handled by listeners on ProjectDatabaseService
    } catch (e) {
      logger.logError('Error deleting track $trackId: $e', _logTag);
      // Optionally, show an error message to the user
    }
  }

  Future<void> loadClipsForProject(int projectId) async {
    logger.logInfo('🔄 Loading clips for project $projectId', _logTag);

    // Incorrectly placed deleteTrack method was here. Removed it.
    final success = await _projectDatabaseService.loadProject(projectId);
    // Check if the database connection is available after attempting load
    if (!success || _projectDatabaseService.currentDatabase == null) {
      logger.logError('❌ Failed to load project $projectId', _logTag);
      clipsNotifier.value = [];
      _navigationService.recalculateAndUpdateTotalFrames(); // Notify nav service directly
      return;
    }

    final tracks = _projectDatabaseService.tracksNotifier.value;
    currentTrackIds.clear(); // Clear before repopulating
    currentTrackIds = tracks.map((t) => t.id).toList();
    logger.logInfo(
      '📊 Loaded ${tracks.length} tracks with IDs: $currentTrackIds',
      _logTag,
    );

    if (tracks.isEmpty) {
      logger.logInfo('⚠️ No tracks found for project $projectId', _logTag);
      clipsNotifier.value = [];
      _navigationService.recalculateAndUpdateTotalFrames(); // Notify nav service directly
      return;
    }

    await refreshClips();
  }

  /// Updates the UI state after clip placement (called by commands after persistence)
  void updateClipsAfterPlacement(List<ClipModel> updatedClips) {
    clipsNotifier.value = updatedClips;
    // Listener on clipsNotifier will trigger recalculation in navigation service
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
    }
    // Removed the 'else' block that handled direct updates/moves/resizes.
    // This logic is now encapsulated within MoveClipCommand and ResizeClipCommand.
    // This method should only be called for adding NEW clips (clipId == null).
    // If called with a clipId, it should now throw an error or log a warning.
    logger.logError('placeClipOnTrack called with existing clipId ($clipId). This should be handled by Move/Resize commands.', _logTag);
    // Optionally, throw an exception:
    // throw ArgumentError('placeClipOnTrack should only be used for adding new clips.');
    return false; // Indicate failure if called incorrectly
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
/// Executes a Roll Edit command based on input from the RollEditHandle widget.
  Future<void> performRollEdit({
    required int leftClipId,
    required int rightClipId,
    required int newBoundaryFrame,
  }) async {
    final command = RollEditCommand(
      leftClipId: leftClipId,
      rightClipId: rightClipId,
      newBoundaryFrame: newBoundaryFrame,
      clipsNotifier: clipsNotifier, // Pass the notifier
    );
    await runCommand(command);
  }

  Future<void> refreshClips() async {
    // Check if the database service is available
    if (_projectDatabaseService.currentDatabase == null) {
        logger.logWarning('Database connection not available, cannot refresh clips.', _logTag);
        return;
    }

    logger.logInfo('Refreshing clips using ProjectDatabaseService.getAllTimelineClips()...', _logTag);

    // Delegate fetching and mapping to the service
    List<ClipModel> allClips = await _projectDatabaseService.getAllTimelineClips();

    // Sort clips by their start time on the track
    allClips.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );

    // Update the notifier if the list of clips has changed OR if it is now empty.
    // Use standard !listEquals syntax - maybe rewriting the whole file fixed the analyzer?
    // Incorrectly placed performRollEdit method was here. Removed it.
    if (!listEquals(clipsNotifier.value, allClips) || allClips.isEmpty) {
      clipsNotifier.value = allClips;
      logger.logDebug('Clips list updated in ViewModel (${allClips.length} clips). Notifier triggered.', _logTag);
      // Note: The recalculation will happen via the listener set up in _setupClipListeners
    } else {
       logger.logDebug('Clips list in ViewModel is already up-to-date and not empty. Notifier not updated.', _logTag);
    }
  }

  // --- Logic Service Delegations ---

  /// Calculates the frame position based on pixel offset, scroll, and zoom.
  /// Delegates to TimelineLogicService.
  int calculateFramePositionForOffset(double pixelPosition, double scrollOffset, double zoom) {
    return _timelineLogicService.calculateFramePosition(pixelPosition, scrollOffset, zoom);
  }

  /// Converts a frame number to milliseconds.
  /// Delegates to TimelineLogicService.
  int frameToMs(int frame) {
    return _timelineLogicService.frameToMs(frame); // Keep delegation for consistency
  }

  /// Calculates the scroll offset needed to bring a specific frame into view.
  /// Delegates to TimelineLogicService.
  double calculateScrollOffsetForFrame(int frame, double zoom) {
    return _timelineLogicService.calculateScrollOffsetForFrame(frame, zoom);
  }

  /// Generates a preview list of clips for a drag operation.
  /// Delegates to TimelineLogicService.
  List<ClipModel> getDragPreviewClips({
    required int draggedClipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    // Corrected method name
    return _timelineLogicService.getPreviewClipsForDrag(
      clips: clips,
      clipId: draggedClipId, // Correct parameter name is clipId
      targetTrackId: targetTrackId,
      targetStartTimeOnTrackMs: targetStartTimeOnTrackMs,
    );
  }

  @override
  void dispose() {
    logger.logInfo('Disposing TimelineViewModel and internal listeners/services', _logTag);
    // Remove internal listeners
    for (final listener in _internalListeners) {
      // Attempt removal from known notifiers
      _projectDatabaseService.tracksNotifier.removeListener(listener);
      clipsNotifier.removeListener(listener);
      // Add removeListener calls for other notifiers if listener was attached elsewhere
    }
    _internalListeners.clear();

    // Dispose owned services
    _playbackService.dispose();
    _navigationService.dispose();

    // Dispose owned ValueNotifiers
    clipsNotifier.dispose();
    trackLabelWidthNotifier.dispose();
    currentEditMode.dispose();
    tracksListNotifier.dispose(); // Dispose the new notifier

    super.dispose();
  }
}
