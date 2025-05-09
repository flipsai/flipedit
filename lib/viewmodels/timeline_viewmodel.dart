import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Rect;
import 'package:flutter_box_transform/flutter_box_transform.dart' show Flip;

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart' show Track;
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'commands/delete_track_command.dart';
import 'commands/update_track_name_command.dart';
import 'commands/reorder_tracks_command.dart';
import 'commands/add_track_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'commands/roll_edit_command.dart';
import 'package:flipedit/services/timeline_logic_service.dart';
import 'package:flipedit/services/preview_sync_service.dart';
import 'commands/update_clip_preview_flip_command.dart';
import 'commands/update_clip_transform_command.dart';

class TimelineViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineViewModel';

  // --- Injected Services & ViewModels ---
  final ProjectDatabaseService _projectDatabaseService =
      di<
        ProjectDatabaseService
      >(); // Needed by some commands directly? Review later.
  final UndoRedoService _undoRedoService = di<UndoRedoService>();
  final TimelineLogicService _timelineLogicService =
      di<TimelineLogicService>(); // Needed for calculations
  final PreviewSyncService _previewSyncService =
      di<
        PreviewSyncService
      >(); // Needed by some commands directly? Review later.
  final TimelineStateViewModel _stateViewModel =
      di<TimelineStateViewModel>(); // Inject State VM

  // --- State Notifiers (Managed by this ViewModel - Interaction State Only) ---

  // Flag to track when playhead is being intentionally dragged (Interaction State)
  final ValueNotifier<bool> _isPlayheadDraggingNotifier = ValueNotifier<bool>(
    false,
  );
  bool get isPlayheadDragging => _isPlayheadDraggingNotifier.value;
  set isPlayheadDragging(bool value) {
    if (_isPlayheadDraggingNotifier.value != value) {
      _isPlayheadDraggingNotifier.value = value;
      logger.logDebug('Playhead dragging: $value', _logTag);
    }
  }

  // Added track label width notifier for the width of the track label area
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier<double>(
    120.0,
  );
  double get trackLabelWidth => trackLabelWidthNotifier.value;
  set trackLabelWidth(double value) {
    final clampedWidth = value.clamp(80.0, 300.0);
    if (trackLabelWidthNotifier.value != clampedWidth) {
      trackLabelWidthNotifier.value = clampedWidth;
      logger.logInfo('Track label width updated to $clampedWidth', _logTag);
    }
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  static const DEFAULT_EMPTY_DURATION = 600000; // 10 minutes in milliseconds
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFrames = totalFramesNotifier.value;
    // Clamp to content duration when present
    final int maxAllowedFrame =
        totalFrames > 0
            ? totalFrames - 1
            : ClipModel.msToFrames(DEFAULT_EMPTY_DURATION);
    final clampedValue = value.clamp(0, maxAllowedFrame);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
    logger.logDebug('Current frame updated to $clampedValue', _logTag);
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);
  int get totalFrames => totalFramesNotifier.value;

  // --- Delegated State Getters (from TimelineStateViewModel) ---
  ValueNotifier<List<ClipModel>> get clipsNotifier =>
      _stateViewModel.clipsNotifier;
  List<ClipModel> get clips => _stateViewModel.clips;
  ValueNotifier<List<Track>> get tracksNotifierForView =>
      _stateViewModel.tracksNotifierForView;
  List<int> get currentTrackIds => _stateViewModel.currentTrackIds;
  ValueNotifier<int?> get selectedTrackIdNotifier =>
      _stateViewModel.selectedTrackIdNotifier;
  int? get selectedTrackId => _stateViewModel.selectedTrackId;
  set selectedTrackId(int? value) =>
      _stateViewModel.selectedTrackId = value; // Delegate setter
  ValueNotifier<int?> get selectedClipIdNotifier =>
      _stateViewModel.selectedClipIdNotifier;
  int? get selectedClipId => _stateViewModel.selectedClipId;
  set selectedClipId(int? value) =>
      _stateViewModel.selectedClipId = value; // Delegate setter
  bool get hasContent => _stateViewModel.hasContent; // Delegate getter

  // Current editing mode (Interaction State)
  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(
    EditMode.select,
  );

  // Sets the current editing mode (Interaction Logic)
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  final List<VoidCallback> _internalListeners =
      []; // Store listeners for disposal

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

  ValueNotifier<bool> get canUndoNotifier =>
      _undoRedoService.canUndo; // Delegated
  ValueNotifier<bool> get canRedoNotifier =>
      _undoRedoService.canRedo; // Delegated

  // Expose project database service primarily for Commands
  ProjectDatabaseService get projectDatabaseService => _projectDatabaseService;

  TimelineViewModel() {
    logger.logInfo('Initializing TimelineViewModel (Interaction)', _logTag);
  } // END OF CONSTRUCTOR

  // --- Public Methods ---

  /// Deletes a track using the Command pattern.
  Future<void> deleteTrack(int trackId) async {
    final command = DeleteTrackCommand(vm: this, trackId: trackId);
    await runCommand(command);
    // State update is handled by the listener in TimelineStateViewModel
  }

  /// Reorders tracks using the Command pattern.
  Future<void> reorderTracks(int oldIndex, int newIndex) async {
    final originalTracks = List<Track>.from(
      _stateViewModel.tracksListNotifier.value,
    );

    // Basic validation
    if (oldIndex < 0 ||
        oldIndex >= originalTracks.length ||
        newIndex < 0 ||
        newIndex >= originalTracks.length) {
      logger.logError(
        'Invalid indices for track reordering: old=$oldIndex, new=$newIndex, count=${originalTracks.length}',
        _logTag,
      );
      return;
    }
    if (oldIndex == newIndex) return; // No operation needed

    // Run the command to persist the change
    final command = ReorderTracksCommand(
      vm: this, // Or pass stateViewModel?
      originalTracks: originalTracks,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    try {
      await runCommand(command);
      // State update is handled by the listener in TimelineStateViewModel
    } catch (e) {
      logger.logError('Error running ReorderTracksCommand: $e.', _logTag);
      // No optimistic update to revert here. State VM listener handles consistency.
    }
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
        endTimeInSourceMs:
            endTimeInSourceMs, // This will be clamped by constructor/service
        startTimeOnTrackMs: startTimeOnTrackMs,
        endTimeOnTrackMs: endTimeOnTrackMs,
        effects: [],
        metadata: {},
      );

      // Create an instance of the AddClipCommand class (imported at the top of the file)
      final command = AddClipCommand(
        vm: this, // Or pass stateViewModel?
        clipData: clipData,
        trackId: trackId,
        startTimeOnTrackMs:
            startTimeOnTrackMs, // Only track start time is needed here
      );

      await runCommand(command);
      return true;
    }
    logger.logError(
      'placeClipOnTrack called with existing clipId ($clipId). This should be handled by Move/Resize commands.',
      _logTag,
    );
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
      vm: this, // Or pass stateViewModel?
      name: 'Track 1',
      type: clip.type.name,
    );
    await runCommand(addTrackCmd);
    final newTrackId = addTrackCmd.newTrackId; // Get ID from executed command

    if (newTrackId == null) {
      logger.logError(
        'Failed to create new track via AddTrackCommand',
        _logTag,
      );
      return false;
    }
    logger.logInfo(
      'New track created via command with ID: $newTrackId',
      _logTag,
    );

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
      vm: this, // Or pass stateViewModel?
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
      clipsNotifier:
          _stateViewModel.clipsNotifier, // Pass notifier from State VM
    );
    await runCommand(command);
  }

  // Removed refreshClips - Handled by TimelineStateViewModel

  // --- Logic Service Delegations (Helper methods using TimelineLogicService) ---

  /// Calculates the frame corresponding to a pixel offset on the timeline.
  int calculateFramePositionForOffset(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    return _timelineLogicService.calculateFramePosition(
      pixelPosition,
      scrollOffset,
      zoom,
    );
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
    // Get clips from State VM
    return _timelineLogicService.getPreviewClipsForDrag(
      clips: _stateViewModel.clips,
      clipId: draggedClipId,
      targetTrackId: targetTrackId,
      targetStartTimeOnTrackMs: targetStartTimeOnTrackMs,
    );
  }

  // Update clip's flip setting using the command pattern
  Future<void> updateClipPreviewFlip(int clipId, Flip flip) async {
    final command = UpdateClipPreviewFlipCommand(clipId: clipId, newFlip: flip);
    try {
      await runCommand(command);
      // State update and preview sync are handled within the command
    } catch (e) {
      logger.logError(
        'Error running UpdateClipPreviewFlipCommand: $e',
        _logTag,
      );
      // Consider showing user feedback about the error
    }
  }

  // Update clip's preview rectangle using the command pattern
  Future<void> updateClipPreviewRect(int clipId, Rect newRect) async {
    logger.logInfo(
      'Attempting to update clip $clipId preview rect to: $newRect',
      _logTag,
    );

    try {
      // Get the current clip state to retrieve oldRect and oldFlip for the command
      final clip = _stateViewModel.clips.firstWhere(
        (c) => c.databaseId == clipId,
        orElse: () {
          logger.logError('Clip $clipId not found for rect update.', _logTag);
          throw StateError('Clip $clipId not found');
        },
      );

      final oldRect = clip.previewRect ??
          const Rect.fromLTWH(
            0,
            0,
            1280,
            720,
          ); // Provide a sensible default if null
      final oldFlip = clip.previewFlip ?? Flip.none; // Provide a default

      final command = UpdateClipTransformCommand(
        projectDatabaseService: _projectDatabaseService,
        clipId: clipId,
        newRect: newRect,
        newFlip: oldFlip, // Keep the existing flip value
        oldRect: oldRect,
        oldFlip: oldFlip,
      );

      await runCommand(command);
      logger.logInfo(
        'UpdateClipTransformCommand executed for clip $clipId with new rect: $newRect',
        _logTag,
      );
      // State update and preview sync are handled by the command and TimelineStateViewModel listeners
    } catch (e) {
      logger.logError(
        'Error running UpdateClipTransformCommand for rect update: $e',
        _logTag,
      );
      // Optionally, rethrow or show user feedback
    }
  }

  @override
  void dispose() {
    logger.logInfo('Disposing TimelineViewModel', _logTag);

    // Execute stored removal logic for listeners (if any remain in this VM)
    // for (final removeListener in _internalListeners) {
    //   removeListener();
    // }
    // _internalListeners.clear(); // Clear if used

    // Dispose owned ValueNotifiers (Interaction State Only)
    _isPlayheadDraggingNotifier.dispose();
    trackLabelWidthNotifier.dispose();
    currentFrameNotifier.dispose(); // TODO: Move to Nav VM?
    totalFramesNotifier.dispose(); // TODO: Move to Nav VM?
    currentEditMode.dispose();
    // Do NOT dispose notifiers owned by TimelineStateViewModel

    super.dispose();
  }
}
