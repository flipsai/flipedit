import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:video_player/video_player.dart';
// Add prefix
import 'dart:io'; // Import for File

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import ClipType
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart'; // Add import for ProjectMetadataService
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'commands/update_clip_transform_command.dart';
import 'package:watch_it/watch_it.dart';

// TODO: Consider refining visibility logic (e.g., only top-most clip per track)
class PreviewViewModel extends ChangeNotifier {
  final String _logTag = 'PreviewViewModel';

  // --- Injected Dependencies (via DI) ---
  late final TimelineViewModel _timelineViewModel;
  late final TimelineNavigationViewModel _timelineNavigationViewModel;
  late final EditorViewModel _editorViewModel;
  late final ProjectDatabaseService _projectDatabaseService;
  late final ProjectMetadataService _projectMetadataService;
  // Add UndoRedoService if needed directly, or rely on TimelineVM's runCommand

  // --- State Notifiers (Exposed to View) ---
  final ValueNotifier<List<ClipModel>> visibleClipsNotifier = ValueNotifier([]);
  final ValueNotifier<Map<int, Rect>> clipRectsNotifier = ValueNotifier({});
  final ValueNotifier<Map<int, Flip>> clipFlipsNotifier = ValueNotifier({});
  final ValueNotifier<int?> selectedClipIdNotifier = ValueNotifier(null);
  final ValueNotifier<double> aspectRatioNotifier = ValueNotifier(
    16.0 / 9.0,
  ); // Default
  final ValueNotifier<Size?> containerSizeNotifier = ValueNotifier(null);

  // Snap Lines
  final ValueNotifier<double?> activeHorizontalSnapYNotifier = ValueNotifier(
    null,
  );
  final ValueNotifier<double?> activeVerticalSnapXNotifier = ValueNotifier(
    null,
  );

  // Interaction State
  final ValueNotifier<bool> isTransformingNotifier = ValueNotifier(false);

  // Notifier to track which controller IDs have finished initializing
  final ValueNotifier<Set<int>> initializedControllerIdsNotifier =
      ValueNotifier({});

  // Video Controllers (Managed Internally)
  final Map<int, VideoPlayerController> _videoControllers = {};
  Map<int, VideoPlayerController> get videoControllers =>
      Map.unmodifiable(_videoControllers);

  // Store pre-transform state for undo
  final Map<int, Rect> _preTransformRects = {};
  final Map<int, Flip> _preTransformFlips = {};

  // --- Getters for simplified access ---
  Size? get containerSize => containerSizeNotifier.value;

  PreviewViewModel() {
    logger.logInfo('PreviewViewModel initializing...', _logTag);
    // Get dependencies from DI (di refers to GetIt instance from service_locator.dart)
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _editorViewModel = di<EditorViewModel>();
    _projectDatabaseService = di<ProjectDatabaseService>();
    _projectMetadataService = di<ProjectMetadataService>();

    // --- Setup Listeners ---
    _timelineNavigationViewModel.currentFrameNotifier.addListener(
      _updatePlaybackPosition,
    );
    _timelineViewModel.clipsNotifier.addListener(
      _updateVisibleClipsAndControllers,
    );
    _timelineNavigationViewModel.isPlayingNotifier.addListener(
      _handlePlayStateChange,
    );
    // Listen to selection changes to update the selectedClipIdNotifier
    _timelineViewModel.selectedClipIdNotifier.addListener(_updateSelection);
    // Listen for project load events through the ProjectMetadataService
    _projectMetadataService.currentProjectMetadataNotifier.addListener(
      _handleProjectLoaded,
    );

    // --- Initial Setup ---
    _updateAspectRatio();
    _updateVisibleClipsAndControllers(); // Initial call to load clips
    _updateSelection(); // Initial selection sync
    logger.logInfo('PreviewViewModel initialized.', _logTag);
  }

  // --- Listener Callbacks ---

  void _updatePlaybackPosition() {
    // Get current frame and convert to milliseconds
    final currentFrame =
        _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    logger.logVerbose(
      'Playback position update triggered: ${currentMs}ms (Frame: $currentFrame)',
      _logTag,
    );

    for (var entry in _videoControllers.entries) {
      final clipId = entry.key;
      final controller = entry.value;
      // Find the clip model from the TimelineViewModel's list
      final clip = _findClipByIdInternal(clipId);

      if (clip == null || !controller.value.isInitialized) {
        logger.logVerbose(
          'Skipping position update for clip $clipId (Clip found: ${clip != null}, Controller init: ${controller.value.isInitialized})',
          _logTag,
        );
        continue; // Skip if clip not found or controller not ready
      }

      // Calculate the position within the source video
      final positionInClipMs = currentMs - clip.startTimeOnTrackMs;
      final sourcePositionMs = clip.startTimeInSourceMs + positionInClipMs;

      // Check if the current time is actually within the clip's duration on the timeline
      if (currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs) {
        // Seek the video controller to the calculated source position
        // Add a small tolerance to avoid potential floating point issues if needed
        final seekPosition = Duration(
          milliseconds: sourcePositionMs.clamp(0, clip.sourceDurationMs),
        );

        // Only seek if the position is significantly different or if paused
        if ((controller.value.position - seekPosition).abs() >
                const Duration(milliseconds: 50) ||
            !controller.value.isPlaying) {
          logger.logVerbose(
            'Seeking clip $clipId to ${seekPosition.inMilliseconds}ms (source)',
            _logTag,
          );
          controller.seekTo(seekPosition);
        }
      } else {
        // If the controller is playing but shouldn't be, pause it
        if (controller.value.isPlaying) {
          logger.logVerbose(
            'Pausing clip $clipId (outside active range)',
            _logTag,
          );
          controller.pause();
        }
      }
    }
    // Also trigger an update for visible clips, as playback position might affect visibility
    _updateVisibleClipsAndControllers();
  }

  void _updateVisibleClipsAndControllers() {
    final currentFrame =
        _timelineNavigationViewModel.currentFrameNotifier.value;
    final initialCall =
        !visibleClipsNotifier.value.isNotEmpty; // Heuristic for initial call
    final allClips = _timelineViewModel.clipsNotifier.value; // Keep this one

    logger.logInfo(
      'Visible clips update triggered. InitialCall: $initialCall, CurrentFrame: $currentFrame, TotalClipsAvailable: ${allClips.length}',
      _logTag,
    );
    // Get current frame and convert to milliseconds
    final currentMs = ClipModel.framesToMs(currentFrame);
    // final allClips = _timelineViewModel.clipsNotifier.value; // Remove duplicate definition
    final List<ClipModel> currentlyVisibleClips = [];
    final Map<int, Rect> currentRects = {};
    final Map<int, Flip> currentFlips = {};
    final Set<int> visibleClipIds = {};

    // Log the total clips available for debugging
    logger.logVerbose('Total clips in timeline: ${allClips.length}', _logTag);

    // 1. Determine which clips are visible at the current time
    // Iterate directly over the list of clips
    for (final clip in allClips) {
      if (clip.databaseId != null &&
          currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs) {
        // TODO: Implement logic for track layering (e.g., only show top-most video)
        // For now, consider all overlapping clips "visible" for controller management
        if (clip.type == ClipType.video || clip.type == ClipType.image) {
          // Only manage controllers for visual types
          currentlyVisibleClips.add(clip);
          visibleClipIds.add(clip.databaseId!);
          // Use the correct getters from ClipModel for transform state
          currentRects[clip.databaseId!] =
              clip.previewRect ?? Rect.zero; // Use stored rect or default
          currentFlips[clip.databaseId!] =
              clip.previewFlip; // Use stored flip or default
        }
      }
    }

    // Special case: If we're at frame 0 and no clips are visible, check if there are video clips
    // starting at frame 0 or nearby that should be initialized
    if (currentFrame == 0 && visibleClipIds.isEmpty && allClips.isNotEmpty) {
      // Added check for allClips.isNotEmpty
      logger.logInfo(
        'INITIAL CHECK: At frame 0 with no visible clips found yet. Checking for clips starting near frame 0 (first 10 frames)... Total clips checked: ${allClips.length}', // Added total clips for context
        _logTag,
      ); // Correctly closes the logInfo call here

      for (final clip in allClips) {
        // Look for video clips starting within the first few frames
        if (clip.databaseId != null &&
            clip.startTimeOnTrackMs <= ClipModel.framesToMs(10) &&
            (clip.type == ClipType.video || clip.type == ClipType.image)) {
          logger.logInfo(
            'Pre-initializing clip that starts soon: ID ${clip.databaseId} at frame ${ClipModel.msToFrames(clip.startTimeOnTrackMs)}',
            _logTag,
          );

          // Add to visible clips for initialization
          currentlyVisibleClips.add(clip);
          visibleClipIds.add(clip.databaseId!);
          // Use the correct getters from ClipModel for transform state
          currentRects[clip.databaseId!] = clip.previewRect ?? Rect.zero;
          currentFlips[clip.databaseId!] = clip.previewFlip;
        }
      }
    }

    final tracks = _timelineViewModel.tracksNotifierForView.value;
    final trackOrderMap = {
      for (var i = 0; i < tracks.length; i++) tracks[i].id: i
    };

    currentlyVisibleClips.sort((a, b) {
      final orderA = trackOrderMap[a.trackId] ?? -1;
      final orderB = trackOrderMap[b.trackId] ?? -1;
      return orderB.compareTo(orderA);
    });

    logger.logVerbose(
      'Visible clip IDs at ${currentMs}ms: $visibleClipIds',
      _logTag,
    );

    // 2. Dispose controllers for clips no longer visible
    final Set<int> existingControllerIds = _videoControllers.keys.toSet();
    final Set<int> idsToDispose = existingControllerIds.difference(
      visibleClipIds,
    );
    for (final clipId in idsToDispose) {
      logger.logDebug('Disposing controller for clip $clipId', _logTag);
      _videoControllers[clipId]?.dispose();
      _videoControllers.remove(clipId);
      // Remove from initialized set when disposing
      final currentInitialized = Set<int>.from(
        initializedControllerIdsNotifier.value,
      );
      if (currentInitialized.remove(clipId)) {
        initializedControllerIdsNotifier.value = currentInitialized;
        logger.logVerbose(
          'Removed $clipId from initializedControllerIdsNotifier',
          _logTag,
        );
      }
    }

    // 3. Initialize controllers for newly visible clips
    final Set<int> idsToInitialize = visibleClipIds.difference(
      existingControllerIds,
    );
    for (final clipId in idsToInitialize) {
      // Find the clip model from the TimelineViewModel's list
      final clip = _findClipByIdInternal(clipId);
      if (clip != null &&
          clip.type == ClipType.video &&
          File(clip.sourcePath).existsSync()) {
        logger.logDebug(
          'Initializing controller for clip $clipId (Source: ${clip.sourcePath})',
          _logTag,
        );
        final controller = VideoPlayerController.file(File(clip.sourcePath));
        _videoControllers[clipId] = controller;
        controller
            .initialize()
            .then((_) async {
              // Find the clip model again inside the .then block, in case state changed
              final currentClip = _findClipByIdInternal(clipId);
              if (currentClip == null) {
                logger.logWarning(
                  'Clip $clipId disappeared before controller initialization finished.',
                  _logTag,
                );
                controller
                    .dispose(); // Dispose the controller if the clip is gone
                _videoControllers.remove(clipId);
                // Ensure it's also removed from initialized set if initialization fails/clip disappears
                final currentInitializedOnFail = Set<int>.from(
                  initializedControllerIdsNotifier.value,
                );
                if (currentInitializedOnFail.remove(clipId)) {
                  initializedControllerIdsNotifier.value =
                      currentInitializedOnFail;
                }
                return; // Exit early
              }

              // --- Controller Initialization Successful ---
              logger.logInfo(
                'Controller initialized successfully for clip $clipId',
                _logTag,
              );
              controller.setLooping(false);
              controller.setVolume(0.0); // Start muted

              // Calculate the precise starting position within the source video
              final currentFrame =
                  _timelineNavigationViewModel.currentFrameNotifier.value;
              final currentMs = ClipModel.framesToMs(currentFrame);
              final positionInClipMs =
                  currentMs - currentClip.startTimeOnTrackMs;
              final sourcePositionMs =
                  currentClip.startTimeInSourceMs + positionInClipMs;
              final seekPosition = Duration(
                milliseconds: sourcePositionMs.clamp(
                  0,
                  currentClip.sourceDurationMs,
                ),
              );

              logger.logVerbose(
                'Seeking newly initialized clip $clipId to ${seekPosition.inMilliseconds}ms (source) based on current frame $currentFrame',
                _logTag,
              );
              await controller.seekTo(
                seekPosition,
              ); // Seek to the correct start position
              await controller.pause(); // Ensure it starts paused

              // Now check if playback is active and if this clip *should* be playing
              final isPlaying =
                  _timelineNavigationViewModel.isPlayingNotifier.value;
              if (isPlaying &&
                  currentMs >= currentClip.startTimeOnTrackMs &&
                  currentMs < currentClip.endTimeOnTrackMs) {
                logger.logVerbose(
                  'Playback active, starting newly initialized controller for clip $clipId',
                  _logTag,
                );
                controller.play();
                controller.setVolume(1.0); // Set volume if playing
              }

              // Update the initialized set
              final currentInitialized = Set<int>.from(
                initializedControllerIdsNotifier.value,
              );
              if (currentInitialized.add(clipId)) {
                initializedControllerIdsNotifier.value = currentInitialized;
                logger.logInfo(
                  'Added $clipId to initializedControllerIdsNotifier. New set: $currentInitialized',
                  _logTag,
                );
              }

              // NOTE: No need for the old notifyListeners() call here anymore,
              // the ValueNotifier update handles signaling automatically to its listeners.
              // notifyListeners();
            })
            .catchError((error) {
              // Remove from initialized set on error too
              final currentInitializedOnError = Set<int>.from(
                initializedControllerIdsNotifier.value,
              );
              if (currentInitializedOnError.remove(clipId)) {
                initializedControllerIdsNotifier.value =
                    currentInitializedOnError;
              }
              logger.logError(
                'Error initializing controller for clip $clipId: $error',
                _logTag,
              );
              _videoControllers.remove(clipId); // Remove failed controller
            });
      } else if (clip?.type != ClipType.video) {
        logger.logVerbose(
          'Skipping controller init for non-video clip $clipId (Type: ${clip?.type})',
          _logTag,
        );
      } else if (clip != null && !File(clip.sourcePath).existsSync()) {
        logger.logError(
          'Video file not found for clip $clipId at path: ${clip.sourcePath}',
          _logTag,
        );
      }
    }

    // 4. Update Notifiers if changed
    // Use deep equality check for lists/maps if necessary, or simple check for now
    logger.logInfo(
      'Visible clips calculated. Count: ${currentlyVisibleClips.length}. IDs: ${currentlyVisibleClips.map((c) => c.databaseId).toList()}',
      _logTag,
    );
    if (!listEquals(visibleClipsNotifier.value, currentlyVisibleClips)) {
      visibleClipsNotifier.value = currentlyVisibleClips;
      logger.logInfo(
        'Updated visibleClipsNotifier. New Count: ${currentlyVisibleClips.length}',
        _logTag,
      );
    }
    // Using toString comparison for maps as a simple check; replace with deep equality if needed
    if (clipRectsNotifier.value.toString() != currentRects.toString()) {
      clipRectsNotifier.value = currentRects;
      logger.logVerbose('Updated clipRectsNotifier', _logTag);
    }
    if (clipFlipsNotifier.value.toString() != currentFlips.toString()) {
      clipFlipsNotifier.value = currentFlips;
      logger.logVerbose('Updated clipFlipsNotifier', _logTag);
    }

    // 5. Trigger a general state update for the view
    notifyListeners();
  }

  void _updateAspectRatio() {
    // final newAspectRatio = _editorViewModel.aspectRatioNotifier.value ?? 16.0 / 9.0; // Removed
    // Hardcode or fetch from Project settings if needed elsewhere
    final newAspectRatio = 16.0 / 9.0; // Defaulting
    if (aspectRatioNotifier.value != newAspectRatio) {
      aspectRatioNotifier.value = newAspectRatio;
      logger.logDebug(
        'Aspect ratio updated: $newAspectRatio (Using default)',
        _logTag,
      );
    }
  }

  // Listener for selection changes from TimelineViewModel
  void _updateSelection() {
    final newSelectedId = _timelineViewModel.selectedClipIdNotifier.value;
    if (selectedClipIdNotifier.value != newSelectedId) {
      selectedClipIdNotifier.value = newSelectedId;
      logger.logDebug(
        'Preview selection updated from TimelineVM: $newSelectedId',
        _logTag,
      );
    }
  }

  void updateContainerSize(Size newSize) {
    if (containerSizeNotifier.value != newSize) {
      containerSizeNotifier.value = newSize;
      logger.logDebug('Container size updated: $newSize', _logTag);
      // TODO: Recalculate snapping guides if needed? Or handled in rect changed?
    }
  }

  void selectClip(int? clipId) {
    if (selectedClipIdNotifier.value != clipId) {
      selectedClipIdNotifier.value = clipId;
      // Also update the timeline view model's selection
      _timelineViewModel.selectedClipId = clipId;
      logger.logDebug('Clip selected via Preview: $clipId', _logTag);
    }
  }

  void handleRectChanged(int clipId, Rect newRect) {
    // TODO: Implement snapping logic here, potentially updating the newRect
    // TODO: Update the clipRectsNotifier[clipId] = potentiallySnappedRect;
    // TODO: Update active snap line notifiers during drag
    logger.logVerbose('Rect changed (pre-snap): $clipId, $newRect', _logTag);
    final currentRects = Map<int, Rect>.from(clipRectsNotifier.value);
    currentRects[clipId] =
        newRect; // Update with potentially snapped rect later
    clipRectsNotifier.value = currentRects;
    // Clear snap lines after temporary update (will be recalculated if still snapping)
    activeHorizontalSnapYNotifier.value = null;
    activeVerticalSnapXNotifier.value = null;
  }

  void handleTransformStart(int clipId) {
    if (!isTransformingNotifier.value) isTransformingNotifier.value = true;
    final currentRect = clipRectsNotifier.value[clipId];
    final currentFlip = clipFlipsNotifier.value[clipId];
    if (currentRect != null && currentFlip != null) {
      _preTransformRects[clipId] = currentRect;
      _preTransformFlips[clipId] = currentFlip;
      logger.logDebug(
        'Transform started for clip $clipId. Stored state: Rect=$currentRect, Flip=$currentFlip',
        _logTag,
      );
    } else {
      logger.logWarning(
        'Could not store pre-transform state for clip $clipId - current state missing.',
        _logTag,
      );
      // Store defaults to avoid null errors later, though undo might be wrong
      _preTransformRects[clipId] = Rect.zero;
      _preTransformFlips[clipId] = Flip.none;
    }
  }

  void handleTransformEnd(int clipId) {
    isTransformingNotifier.value = false; // Assume only one transform at a time
    activeHorizontalSnapYNotifier.value = null; // Clear snap lines
    activeVerticalSnapXNotifier.value = null;

    final finalRect = clipRectsNotifier.value[clipId];
    final finalFlip =
        clipFlipsNotifier.value[clipId]; // TODO: Handle flip changes if needed

    if (finalRect == null) {
      logger.logError(
        'Cannot persist transform end, final rect state not found for clip $clipId',
        _logTag,
      );
      _preTransformRects.remove(clipId); // Clean up stored state
      _preTransformFlips.remove(clipId);
      return;
    }
    final finalFlipNonNull = finalFlip ?? Flip.none; // Use default if null

    // Retrieve the state before the transform began
    final oldRect = _preTransformRects.remove(clipId);
    final oldFlip = _preTransformFlips.remove(clipId);

    if (oldRect == null || oldFlip == null) {
      logger.logError(
        'Cannot persist transform end, pre-transform state not found for clip $clipId',
        _logTag,
      );
      return;
    }

    // Compare final state with pre-transform state
    if (finalRect != oldRect || finalFlipNonNull != oldFlip) {
      logger.logInfo(
        'Persisting transform for clip $clipId: Rect=$finalRect, Flip=$finalFlipNonNull',
        _logTag,
      );
      final command = UpdateClipTransformCommand(
        timelineViewModel: _timelineViewModel, // Pass TimelineVM
        projectDatabaseService: _projectDatabaseService, // Pass DB service
        clipId: clipId,
        newRect: finalRect,
        newFlip: finalFlipNonNull, // Use non-null version
        oldRect: oldRect, // Pass old state for undo
        oldFlip: oldFlip, // Pass old state for undo
      );
      // Use TimelineViewModel's runCommand to execute and register for undo
      _timelineViewModel.runCommand(command).catchError((e) {
        logger.logError(
          'Error running UpdateClipTransformCommand: $e',
          _logTag,
        );
        // Handle error appropriately, maybe show a message to the user
      });
    } else {
      logger.logDebug(
        'No change detected after transform for clip $clipId. Skipping persistence.',
        _logTag,
      );
    }
  }

  void _handlePlayStateChange() {
    final isPlaying = _timelineNavigationViewModel.isPlayingNotifier.value;
    final currentFrame =
        _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    logger.logDebug(
      'Play state change detected: ${isPlaying ? "Playing" : "Paused"}',
      _logTag,
    );

    for (var entry in _videoControllers.entries) {
      final clipId = entry.key;
      final controller = entry.value;
      final clip = _findClipByIdInternal(clipId);

      if (clip == null || !controller.value.isInitialized) continue;

      // Check if this clip is active at the current time
      if (currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs) {
        if (isPlaying) {
          if (!controller.value.isPlaying) {
            logger.logVerbose(
              'Handling Play: Starting controller for clip $clipId',
              _logTag,
            );
            controller.play();
            controller.setVolume(1.0); // Ensure volume on play
          }
        } else {
          // Paused state
          if (controller.value.isPlaying) {
            logger.logVerbose(
              'Handling Pause: Pausing controller for clip $clipId',
              _logTag,
            );
            controller.pause();
          }
        }
      } else {
        // If the clip is not active at the current time, ensure it's paused
        // This handles cases where playback stops exactly at a clip boundary
        if (controller.value.isPlaying) {
          logger.logVerbose(
            'Handling Play State Change: Pausing inactive clip $clipId',
            _logTag,
          );
          controller.pause();
        }
      }
    }
    // We might still need _updatePlaybackPosition to be called if the frame *also* changed,
    // but this handler specifically addresses the direct play/pause toggle action.
  }

  // Method to reinitialize preview when a project is loaded
  void _handleProjectLoaded() {
    final currentProject =
        _projectMetadataService.currentProjectMetadataNotifier.value;
    if (currentProject != null) {
      logger.logInfo(
        'Project loaded: ${currentProject.name}. Reinitializing preview panel',
        _logTag,
      );
      // Dispose any existing controllers
      for (final controller in _videoControllers.values) {
        controller.dispose();
      }
      _videoControllers.clear();

      _updatePlaybackPosition();
      _updateVisibleClipsAndControllers();
    }
  }

  // --- Internal Helper Methods ---

  /// Finds a clip by its ID within the TimelineViewModel's current clips list.
  ClipModel? _findClipByIdInternal(int clipId) {
    try {
      return _timelineViewModel.clipsNotifier.value.firstWhere(
        (clip) => clip.databaseId == clipId,
      );
    } catch (e) {
      // firstWhere throws if no element is found
      return null;
    }
  }

  @override
  void dispose() {
    logger.logInfo('PreviewViewModel disposing...', _logTag);
    // --- Remove Listeners ---
    _timelineNavigationViewModel.currentFrameNotifier.removeListener(
      _updatePlaybackPosition,
    );
    _timelineViewModel.clipsNotifier.removeListener(
      _updateVisibleClipsAndControllers,
    );
    _timelineNavigationViewModel.isPlayingNotifier.removeListener(
      _handlePlayStateChange,
    );
    // _editorViewModel.aspectRatioNotifier.removeListener(_updateAspectRatio); // Removed
    _timelineViewModel.selectedClipIdNotifier.removeListener(_updateSelection);
    _projectMetadataService.currentProjectMetadataNotifier.removeListener(
      _handleProjectLoaded,
    );

    // Dispose all video controllers
    for (final controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();

    // Dispose notifiers
    visibleClipsNotifier.dispose();
    clipRectsNotifier.dispose();
    clipFlipsNotifier.dispose();
    selectedClipIdNotifier.dispose();
    aspectRatioNotifier.dispose();
    containerSizeNotifier.dispose();
    activeHorizontalSnapYNotifier.dispose();
    activeVerticalSnapXNotifier.dispose();
    isTransformingNotifier.dispose();

    super.dispose();
    logger.logInfo('PreviewViewModel disposed.', _logTag);
  }
}
