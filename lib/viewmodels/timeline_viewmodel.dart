import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/persistence/database/project_database.dart' show Track;
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Added import
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
import 'commands/update_clip_transform_command.dart';
import 'package:flipedit/services/commands/undoable_command.dart'; // Added import
import 'commands/move_clip_command.dart'; // Added import
import 'commands/resize_clip_command.dart'; // Added import
import '../services/canvas_dimensions_service.dart'; // Add this import if it's not already there

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
 final TimelineNavigationViewModel _navigationViewModel =
     di<TimelineNavigationViewModel>(); // Inject Navigation VM
 final CanvasDimensionsService _canvasDimensionsService = di<CanvasDimensionsService>();

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

  // --- Delegated State Getters (from TimelineNavigationViewModel) ---
  ValueNotifier<int> get currentFrameNotifier =>
      _navigationViewModel.currentFrameNotifier;
  int get currentFrame => _navigationViewModel.currentFrame;
  set currentFrame(int value) {
    // Delegate to TimelineNavigationViewModel's setter which handles clamping and notification
    _navigationViewModel.currentFrame = value;
  }

  ValueNotifier<int> get totalFramesNotifier =>
      _navigationViewModel.totalFramesNotifier;
  int get totalFrames => _navigationViewModel.totalFrames;

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

  /// Executes a TimelineCommand. If the command is Undoable, it's processed
  /// via the UndoRedoService. Otherwise, it's executed directly.
  Future<void> runCommand(TimelineCommand cmd) async {
    if (cmd is UndoableCommand) {
      // Determine entityId. This might need to be a property of the command itself,
      // or passed to runCommand. For MoveClipCommand, it's the clipId.
      // For now, let's assume UndoableCommand has an entityId getter or similar.
      // This needs a more robust way to get entityId.
      // For MoveClipCommand, we know it has a `clipId` property.
      String entityId;
      if (cmd is MoveClipCommand) { // Specific check for MoveClipCommand
        entityId = cmd.clipId.toString();
      } else if (cmd is AddClipCommand) {
        // AddClipCommand might not have an ID until after execution.
        // The UndoRedoService.executeCommand might need to handle ID generation
        // or the command itself returns the ID after execution.
        // For now, this highlights a design consideration.
        // Let's assume for AddClip, the entityId might be set after execute,
        // or the command's toChangeLog handles it.
        // This part needs careful thought for commands that create new entities.
        // A temporary placeholder:
        entityId = "unknown_after_execute";
      } else if (cmd is DeleteTrackCommand) {
        entityId = cmd.trackId.toString();
      } else if (cmd is UpdateTrackNameCommand) {
        entityId = cmd.trackId.toString();
      } else if (cmd is ReorderTracksCommand) {
        // ReorderTracks might affect multiple entities or a "project" entity.
        // For now, let's use a generic ID or the first track ID involved.
        entityId = cmd.originalTracks.isNotEmpty ? cmd.originalTracks.first.id.toString() : "reorder_tracks";
      } else if (cmd is AddTrackCommand) {
        entityId = "unknown_track_after_execute"; // Similar to AddClip
      } else if (cmd is RollEditCommand) {
        entityId = cmd.leftClipId.toString(); // Corrected to use leftClipId
      } else if (cmd is UpdateClipTransformCommand) {
        entityId = cmd.clipId.toString();
      } else if (cmd is ResizeClipCommand) {
        entityId = cmd.clipId.toString();
      }
      // Add more 'else if' for other UndoableCommand types
      else {
        // Fallback or throw error if entityId cannot be determined
        logger.logWarning('Cannot determine entityId for UndoableCommand of type ${cmd.runtimeType}', _logTag);
        // Execute directly if entityId is critical and unknown, or throw
        await cmd.execute();
        return;
      }
      await _undoRedoService.executeCommand(cmd as UndoableCommand, entityId);
    } else {
      // If the command is not undoable, execute it directly.
      await cmd.execute();
    }
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

  /// Places a clip on a track at the specified time using the Command pattern.
  Future<bool> placeClipOnTrack({
    int? clipId,
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
      // Get canvas dimensions for the clip preview
      final canvasWidth = _canvasDimensionsService.canvasWidth;
      final canvasHeight = _canvasDimensionsService.canvasHeight;
      
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
        previewWidth: canvasWidth, // Use canvas width instead of default
        previewHeight: canvasHeight, // Use canvas height instead of default
      );

      // Create an instance of the AddClipCommand class (imported at the top of the file)
      final command = AddClipCommand(
        // vm: this, // Removed as AddClipCommand no longer takes vm
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
      projectDatabaseService: _projectDatabaseService,
      clipsNotifier: clipsNotifier, // This is _stateViewModel.clipsNotifier
      stateViewModel: _stateViewModel, // Pass TimelineStateViewModel instance
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

  /// Updates a clip's preview transformation (X, Y, Width, Height) using the UpdateClipTransformCommand.
  Future<void> updateClipPreviewTransform(
    int clipId,
    double newPositionX,
    double newPositionY,
    double newWidth,
    double newHeight,
  ) async {
    logger.logInfo(
      'Attempting to update clip $clipId preview transform to: X=$newPositionX, Y=$newPositionY, W=$newWidth, H=$newHeight',
      _logTag,
    );

    try {
      final clip = _stateViewModel.clips.firstWhere(
        (c) => c.databaseId == clipId,
        orElse: () {
          logger.logError('Clip $clipId not found for transform update.', _logTag);
          throw StateError('Clip $clipId not found');
        },
      );

      final command = UpdateClipTransformCommand(
        projectDatabaseService: _projectDatabaseService,
        clipId: clipId,
        // New values
        newPositionX: newPositionX,
        newPositionY: newPositionY,
        newWidth: newWidth,
        newHeight: newHeight,
        // Old values
        oldPositionX: clip.previewPositionX,
        oldPositionY: clip.previewPositionY,
        oldWidth: clip.previewWidth,
        oldHeight: clip.previewHeight,
      );

      await runCommand(command);
      logger.logInfo(
        'UpdateClipTransformCommand executed for clip $clipId with new transform: X=$newPositionX, Y=$newPositionY, W=$newWidth, H=$newHeight',
        _logTag,
      );
    } catch (e) {
      logger.logError(
        'Error executing UpdateClipTransformCommand for transform update on clip $clipId: $e',
        _logTag,
      );
      // Optionally rethrow or handle as per app's error strategy
    }
  }
  // updateClipPreviewRect method removed as per user request to remove flutter_box_transform

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
    // currentFrameNotifier and totalFramesNotifier are now delegated, not owned.
    // No TODO needed here anymore for them.
    currentEditMode.dispose();
    // Do NOT dispose notifiers owned by TimelineStateViewModel

    super.dispose();
  }
}
