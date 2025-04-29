import 'dart:async';
import 'package:flutter/foundation.dart'; // Required for ChangeNotifier, ValueNotifier, VoidCallback, listEquals

// Keep this for other collection utilities if needed
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart' show Track;

import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'commands/delete_track_command.dart';
import 'commands/update_track_name_command.dart';
import 'commands/reorder_tracks_command.dart';
import 'commands/add_track_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';
// PlaybackService is now managed by TimelineNavigationViewModel
// TimelineNavigationService is now managed by TimelineNavigationViewModel
import 'commands/roll_edit_command.dart';
import 'package:flipedit/services/timeline_logic_service.dart';

/// ViewModel responsible for managing timeline data (Tracks, Clips),
/// selection state, and executing timeline-modifying commands.
/// Navigation and playback are handled by TimelineNavigationViewModel.
class TimelineViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineViewModel';

  // --- Injected Services ---
  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final TimelineLogicService _timelineLogicService = di<TimelineLogicService>();
  // Removed PlaybackService and TimelineNavigationService instances

  // --- State Notifiers (Managed by this ViewModel) ---
  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);

  // Flag to track when playhead is being intentionally dragged
  final ValueNotifier<bool> _isPlayheadDraggingNotifier = ValueNotifier<bool>(false);
  bool get isPlayheadDragging => _isPlayheadDraggingNotifier.value;
  set isPlayheadDragging(bool value) {
    if (_isPlayheadDraggingNotifier.value != value) {
      _isPlayheadDraggingNotifier.value = value;
      logger.logDebug('Playhead dragging: $value', _logTag);
    }
  }

  // Added track label width notifier for the width of the track label area
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier<double>(120.0);
  double get trackLabelWidth => trackLabelWidthNotifier.value;
  set trackLabelWidth(double value) {
    final clampedWidth = value.clamp(80.0, 300.0);
    if (trackLabelWidthNotifier.value != clampedWidth) {
      trackLabelWidthNotifier.value = clampedWidth;
      logger.logInfo('Track label width updated to $clampedWidth', _logTag);
    }
  }

  // Added currentFrame property for TimelineNavigationViewModel compatibility
  // This should delegate to the navigation viewmodel in a full implementation
  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  static const DEFAULT_EMPTY_DURATION = 600000; // 10 minutes in milliseconds
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFrames = totalFramesNotifier.value;
    // Clamp to content duration when present
    final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : ClipModel.msToFrames(DEFAULT_EMPTY_DURATION);
    final clampedValue = value.clamp(0, maxAllowedFrame);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
    logger.logDebug('Current frame updated to $clampedValue', _logTag);
  }

  // Added totalFrames notifier
  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);
  int get totalFrames => totalFramesNotifier.value;

  final ValueNotifier<int?> selectedTrackIdNotifier = ValueNotifier<int?>(null);
  int? get selectedTrackId => selectedTrackIdNotifier.value;
  set selectedTrackId(int? value) {
    if (selectedTrackIdNotifier.value != value) {
      logger.logInfo('Track selection changed: ${selectedTrackIdNotifier.value} -> $value', _logTag);
      selectedTrackIdNotifier.value = value;

      // When a track is selected, ensure the selected clip belongs to it.
      if (value != null && selectedClipId != null) {
        ClipModel? selectedClip;
        try {
          selectedClip = clipsNotifier.value.firstWhere(
            (clip) => clip.databaseId == selectedClipId
          );
        } catch (e) {
          // Clip not found, ignore
          selectedClip = null;
        }

        if (selectedClip != null && selectedClip.trackId != value) {
          logger.logInfo('Deselecting clip $selectedClipId as it doesn\'t belong to newly selected track $value', _logTag);
          selectedClipId = null; // Deselect clip if it's not on the new track
        }
      }
    }
  }

  final ValueNotifier<int?> selectedClipIdNotifier = ValueNotifier<int?>(null);
  int? get selectedClipId => selectedClipIdNotifier.value;
  set selectedClipId(int? value) {
    if (selectedClipIdNotifier.value != value) {
      logger.logInfo('Clip selection changed: ${selectedClipIdNotifier.value} -> $value', _logTag);
      selectedClipIdNotifier.value = value;
      
      selectedClipIdNotifier.value = value;

      // When a clip is selected, automatically select its parent track.
      if (value != null) {
        try {
          final clip = clipsNotifier.value.firstWhere(
            (c) => c.databaseId == value
          );
          
          // Prevent potential infinite loop if track selection clears clip selection.
          if (selectedTrackIdNotifier.value != clip.trackId) {
            logger.logInfo('Setting track ${clip.trackId} based on clip selection $value', _logTag);
            selectedTrackIdNotifier.value = clip.trackId; // Select the clip's track
          }
        } catch (e) {
          logger.logWarning('Could not find clip with ID $value in clips list', _logTag);
          logger.logWarning('Could not find clip with ID $value in clips list to update track selection', _logTag);
        }
      }
    }
  }

  // Current editing mode (Consider if this truly belongs in ViewModel or View)
  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(EditMode.select);

  // List of current track IDs (Derived from tracksListNotifier)
  List<int> get currentTrackIds => tracksListNotifier.value.map((t) => t.id).toList();

  // Notifier for the tracks list itself (Sourced from DB Service via listener)
  final ValueNotifier<List<Track>> tracksListNotifier = ValueNotifier<List<Track>>([]);
  ValueNotifier<List<Track>> get tracksNotifierForView => tracksListNotifier; // Expose for the View binding

  // Removed Delegated State Notifiers (zoom, currentFrame, totalFrames, timelineEnd, isPlaying, isPlayheadLocked)
  // Removed navigationService getter
  // Removed Delegated Getters/Setters (zoom, currentFrame, totalFrames, timelineEnd, isPlaying, isPlayheadLocked)

  // Helper to check if timeline has content (used for UI logic like scrollbars)
  bool get hasContent => clipsNotifier.value.isNotEmpty || tracksListNotifier.value.isNotEmpty;

  // Sets the current editing mode (local state)
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  final List<VoidCallback> _internalListeners = []; // Store listeners for disposal

  /// Executes a TimelineCommand and registers it with the Undo/Redo service.
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

  ValueNotifier<bool> get canUndoNotifier => _undoRedoService.canUndo; // Delegated
  ValueNotifier<bool> get canRedoNotifier => _undoRedoService.canRedo; // Delegated

  // Expose project database service primarily for Commands
  ProjectDatabaseService get projectDatabaseService => _projectDatabaseService;

  /// Constructor: Initializes services and sets up listeners.
  TimelineViewModel() {
    logger.logInfo('Initializing TimelineViewModel', _logTag);
    // Removed instantiation of Navigation and Playback services
    _setupServiceListeners();
    _initialLoad();
  } // END OF CONSTRUCTOR

  // --- Internal Methods ---

  /// Loads initial track data from the service. Clips are loaded separately.
  void _initialLoad() {
     final serviceTracks = _projectDatabaseService.tracksNotifier.value;
     if (!listEquals(tracksListNotifier.value, serviceTracks)) {
        logger.logInfo('Performing initial sync of ${serviceTracks.length} tracks from service to ViewModel', _logTag);
        tracksListNotifier.value = List.from(serviceTracks); // Use List.from for a new list
     }
     // Note: Clip loading is typically triggered by project load, not here.
     // refreshClips() might be called elsewhere after project selection.
  } // Removed helper functions _getClipsForNavService, _getIsPlayingForNavService

  /// Sets up listeners for relevant service changes (DB Tracks).
  void _setupServiceListeners() {
    // Listen to track changes from the ProjectDatabaseService
    tracksListener() {
      final serviceTracks = _projectDatabaseService.tracksNotifier.value;
       // Use listEquals for robust comparison
      if (!listEquals(tracksListNotifier.value, serviceTracks)) {
          logger.logInfo('👂 Tracks list changed in Service. Updating ViewModel (${serviceTracks.length} tracks).', _logTag);
          tracksListNotifier.value = List.from(serviceTracks); // Update with a new list
          // Clips might need refreshing if tracks changed significantly (e.g., deletion)
          // Consider if refreshClips() is always needed here or only on specific track changes.
          refreshClips();
      }
    }
    _projectDatabaseService.tracksNotifier.addListener(tracksListener);
    _internalListeners.add(() => _projectDatabaseService.tracksNotifier.removeListener(tracksListener));

    // Optional: Listen to internal clip changes if needed for other logic *within this ViewModel*.
    // Removed the listener that notified NavigationService directly.
    // The view layer or parent ViewModel should observe clipsNotifier if TimelineNavigationViewModel
    // needs to be updated based on clip changes handled by *this* ViewModel.
    // Example (if needed):
    // final internalClipListener = () {
    //   logger.logDebug('👂 Clips list changed in TimelineViewModel.', _logTag);
    //   // Perform actions *within TimelineViewModel* if necessary
    // };
    // clipsNotifier.addListener(internalClipListener);
    // _internalListeners.add(() => clipsNotifier.removeListener(internalClipListener));
  }

  // Removed playback methods: startPlayback, stopPlayback, togglePlayPause
  // Removed togglePlayheadLock method

  // --- Public Methods ---

  /// Deletes a track using the Command pattern.
  Future<void> deleteTrack(int trackId) async {
    final command = DeleteTrackCommand(vm: this, trackId: trackId);
    await runCommand(command);
    // State update is handled by the listener on projectDatabaseService.tracksNotifier
  }

  /// Reorders tracks using the Command pattern.
  Future<void> reorderTracks(int oldIndex, int newIndex) async {
    final tracks = tracksListNotifier.value;
    // Check if the indices are valid for the *current* list state
    if (oldIndex < 0 || oldIndex >= tracks.length || newIndex < 0 || newIndex >= tracks.length) {
      logger.logError(
          'Invalid indices provided for track reordering: old=$oldIndex, new=$newIndex, count=${tracks.length}',
          _logTag);
      return;
    }
    if (oldIndex == newIndex) {
       logger.logInfo('Attempted to reorder track to the same position: $oldIndex -> $newIndex', _logTag);
       return; // No operation needed
    }

    final command = ReorderTracksCommand(
      vm: this,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    await runCommand(command);
  }

  Future<void> loadClipsForProject(int projectId) async {
    logger.logInfo('🔄 Loading clips for project $projectId', _logTag);

    logger.logInfo('🔄 Loading project $projectId using ProjectDatabaseService', _logTag);
    final success = await _projectDatabaseService.loadProject(projectId);

    if (!success) {
      logger.logError('❌ Failed to load project $projectId via service', _logTag);
      // Clear local state if project load failed
      // No need to update navigation service from here
      tracksListNotifier.value = [];
      clipsNotifier.value = [];
      return;
    }

    logger.logInfo('✅ Project $projectId loaded successfully. Triggering initial sync and clip refresh.', _logTag);
    // Service listeners should handle updating tracksListNotifier.
    // Explicitly trigger refreshClips after successful load.
    _initialLoad(); // Ensure tracks are synced immediately after load
    await refreshClips(); // Load clips for the now-loaded project
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
    required int endTimeInSourceMs, // TODO: Review if needed - AddClipCommand derives this
  }) async {

    // Use the AddClipCommand for adding new clips.
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
    // 1. Create the track using AddTrackCommand
    final addTrackCmd = AddTrackCommand(
      vm: this,
      name: 'Track 1', // Default name for new track
      type: clip.type.name,
    );
    await runCommand(addTrackCmd);
    final newTrackId = addTrackCmd.newTrackId; // Get ID from executed command

    if (newTrackId == null) {
      logger.logError('Failed to create new track via AddTrackCommand', _logTag);
      return false;
    }
     logger.logInfo('New track created via command with ID: $newTrackId', _logTag);

    // 2. Place the clip on the newly created track using AddClipCommand
    // (placeClipOnTrack already uses AddClipCommand internally)
    final success = await placeClipOnTrack(
      clipId: null, // Ensure it's treated as a new clip
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

  /// Updates the name of a track using the Command pattern.
  Future<void> updateTrackName(int trackId, String newName) async {
    final command = UpdateTrackNameCommand(
      vm: this,
      trackId: trackId,
      newName: newName,
    );
    await runCommand(command);
     // State update is handled by the listener on projectDatabaseService.tracksNotifier
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

    // Update the notifier only if the list content has actually changed.
    if (!listEquals(clipsNotifier.value, allClips)) {
        clipsNotifier.value = allClips; // Update local state
        logger.logDebug('Clips list updated in ViewModel (${allClips.length} clips). Notifier triggered.', _logTag);
        // The View/Parent ViewModel observing clipsNotifier should handle updating
        // TimelineNavigationViewModel if needed (e.g., calling recalculateTotalFrames).
    } else {
        logger.logDebug('Refreshed clips list is identical to current ViewModel state. No update needed.', _logTag);
    }
  }

  // --- Logic Service Delegations (Helper methods using TimelineLogicService) ---

  /// Calculates the frame corresponding to a pixel offset on the timeline.
  int calculateFramePositionForOffset(double pixelPosition, double scrollOffset, double zoom) {
    return _timelineLogicService.calculateFramePosition(pixelPosition, scrollOffset, zoom);
  }

  /// Converts a frame number to milliseconds.
  /// Converts a frame number to milliseconds.
  int frameToMs(int frame) {
    return _timelineLogicService.frameToMs(frame);
  }

  /// Calculates the scroll offset required to center a specific frame.
  double calculateScrollOffsetForFrame(int frame, double zoom) {
    return _timelineLogicService.calculateScrollOffsetForFrame(frame, zoom);
  }

  /// Generates a preview list of clips for drag visualization.
  List<ClipModel> getDragPreviewClips({
    required int draggedClipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    return _timelineLogicService.getPreviewClipsForDrag(
      clips: clips,
      clipId: draggedClipId, // Correct parameter name is clipId
      targetTrackId: targetTrackId,
      targetStartTimeOnTrackMs: targetStartTimeOnTrackMs,
    );
  }

  @override
  void dispose() {
    logger.logInfo('Disposing TimelineViewModel', _logTag);

    // Execute stored removal logic for listeners
    for (final removeListener in _internalListeners) {
      removeListener(); // Calls the stored remover function
    }
    _internalListeners.clear();

    // Dispose owned ValueNotifiers
    clipsNotifier.dispose();
    _isPlayheadDraggingNotifier.dispose(); // Dispose the new notifier
    trackLabelWidthNotifier.dispose(); // Dispose the track label width notifier
    currentFrameNotifier.dispose(); // Dispose the current frame notifier
    totalFramesNotifier.dispose(); // Dispose the total frames notifier
    currentEditMode.dispose();
    tracksListNotifier.dispose();
    selectedTrackIdNotifier.dispose();
    selectedClipIdNotifier.dispose();

    super.dispose();
  }
}
