import 'dart:async'; // Import for Timer (debouncing)
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:video_player/video_player.dart';
// Add prefix
import 'dart:io'; // Import for File

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import ClipType
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/composite_video_service.dart'; // Import CompositeVideoService
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
  late final CompositeVideoService _compositeVideoService; // Add CompositeVideoService dependency

  // --- State Notifiers (Exposed to View) ---
  final ValueNotifier<List<ClipModel>> visibleClipsNotifier = ValueNotifier([]); // Clips currently visible for interaction overlays
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
      _handleTimelineOrTransformChange, // Consolidate update triggers
    );
    // Remove listener for isPlayingNotifier, handled by frame changes
    // _timelineNavigationViewModel.isPlayingNotifier.addListener(_handlePlayStateChange);
  
    // Listen to selection changes to update the selectedClipIdNotifier
    _timelineViewModel.selectedClipIdNotifier.addListener(_updateSelection);
    // Listen for project load events through the ProjectMetadataService
    _projectMetadataService.currentProjectMetadataNotifier.addListener(
      _handleProjectLoaded,
    );

    // --- Initial Setup ---
    _updateAspectRatio();
    _handleTimelineOrTransformChange(); // Initial call to determine visible clips and trigger composite
    _updateSelection(); // Initial selection sync
    logger.logInfo('PreviewViewModel initialized.', _logTag);
  }

  // --- Listener Callbacks ---

  // Listener for frame changes from TimelineNavigationViewModel
  void _updatePlaybackPosition() {
    final currentFrame = _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    logger.logVerbose(
      'Playback position update triggered: ${currentMs}ms (Frame: $currentFrame). Triggering composite update.',
      _logTag,
    );
    _triggerCompositeUpdate();
  }

  // Listener for changes in timeline clips or clip transforms
  void _handleTimelineOrTransformChange() {
    final currentFrame = _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    final allClips = _timelineViewModel.clipsNotifier.value;

    logger.logInfo(
      'Timeline/Transform change detected. CurrentFrame: $currentFrame, TotalClipsAvailable: ${allClips.length}',
      _logTag,
    );

    // 1. Determine which clips are potentially visible for interaction
    final List<ClipModel> potentiallyVisibleClips = [];
    final Map<int, Rect> currentRects = {};
    final Map<int, Flip> currentFlips = {};
    final Set<int> visibleClipIds = {};

    for (final clip in allClips) {
      if (clip.databaseId != null &&
          currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs &&
          (clip.type == ClipType.video || clip.type == ClipType.image)) {
        potentiallyVisibleClips.add(clip);
        visibleClipIds.add(clip.databaseId!);
        currentRects[clip.databaseId!] = clip.previewRect ?? Rect.zero;
        currentFlips[clip.databaseId!] = clip.previewFlip;
      }
    }

    // Sort by track order (higher tracks on top)
    final tracks = _timelineViewModel.tracksNotifierForView.value;
    final trackOrderMap = { for (var i = 0; i < tracks.length; i++) tracks[i].id: i };
    potentiallyVisibleClips.sort((a, b) {
      final orderA = trackOrderMap[a.trackId] ?? -1;
      final orderB = trackOrderMap[b.trackId] ?? -1;
      return orderB.compareTo(orderA); // Higher index (visually lower track) comes first
    });

    logger.logVerbose(
      'Visible clip IDs for interaction overlays at ${currentMs}ms: $visibleClipIds',
      _logTag,
    );

    // 2. Update Notifiers for the View's interactive overlays
    // Only update if the lists/maps actually changed to avoid unnecessary rebuilds
    bool changed = false;
    if (!listEquals(visibleClipsNotifier.value.map((c) => c.databaseId).toList(), potentiallyVisibleClips.map((c) => c.databaseId).toList())) {
      visibleClipsNotifier.value = potentiallyVisibleClips;
      changed = true;
      logger.logInfo('Updated visibleClipsNotifier. New Count: ${potentiallyVisibleClips.length}');
    }
    if (!mapEquals(clipRectsNotifier.value, currentRects)) {
      clipRectsNotifier.value = currentRects;
      changed = true;
      logger.logVerbose('Updated clipRectsNotifier');
    }
    if (!mapEquals(clipFlipsNotifier.value, currentFlips)) {
      clipFlipsNotifier.value = currentFlips;
      changed = true;
      logger.logVerbose('Updated clipFlipsNotifier');
    }

    // 3. Trigger composite update regardless of notifier changes,
    //    as the underlying timeline data might have changed even if visible set is same.
    _triggerCompositeUpdate();

    // 4. Notify listeners if visual state for overlays changed
    if (changed) {
      notifyListeners(); // Let the View know overlay data changed
    }
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

  // Method to handle flip changes from the UI
  void handleFlipChanged(int clipId, Flip newFlip) {
    final currentFlips = Map<int, Flip>.from(clipFlipsNotifier.value);
    if (currentFlips[clipId] != newFlip) {
      logger.logDebug('Flip changed for clip $clipId to $newFlip', _logTag);
      currentFlips[clipId] = newFlip;
      clipFlipsNotifier.value = currentFlips;

      // Trigger persistence and composite update immediately after flip change
      // We can reuse handleTransformEnd logic, passing the current rect and the new flip
      final currentRect = clipRectsNotifier.value[clipId];
      if (currentRect != null) {
         handleTransformEnd(clipId, currentRect, newFlip); // Pass explicit flip
      } else {
         logger.logWarning('Cannot persist flip change for clip $clipId, rect is missing.', _logTag);
      }
    }
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

  // Overload or modify handleTransformEnd to accept optional final states for flips
  void handleTransformEnd(int clipId, [Rect? explicitRect, Flip? explicitFlip]) {
    isTransformingNotifier.value = false;
    activeHorizontalSnapYNotifier.value = null;
    activeVerticalSnapXNotifier.value = null;

    final finalRect = explicitRect ?? clipRectsNotifier.value[clipId];
    final finalFlip = explicitFlip ?? clipFlipsNotifier.value[clipId];

    if (finalRect == null) {
      logger.logError('Cannot persist transform end, final rect state not found for clip $clipId', _logTag);
      _preTransformRects.remove(clipId);
      _preTransformFlips.remove(clipId);
      return;
    }
    final finalFlipNonNull = finalFlip ?? Flip.none;

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
        oldFlip: oldFlip,
      );
      // Use TimelineViewModel's runCommand to execute and register for undo
      _timelineViewModel.runCommand(command).then((_) {
         // Trigger composite update AFTER the command successfully updates the model
         logger.logInfo('Transform persisted, triggering composite update.', _logTag);
         _triggerCompositeUpdate();
      }).catchError((e) {
        logger.logError('Error running UpdateClipTransformCommand: $e', _logTag);
        // Optionally revert UI state or show error
      });
    } else {
      logger.logDebug('No change detected after transform for clip $clipId. Skipping persistence.', _logTag);
      // No need to trigger composite update if nothing changed
    }
  }

  // Removed _handlePlayStateChange as it's covered by frame updates

  // Method to reinitialize preview when a project is loaded
  void _handleProjectLoaded() {
    final currentProject = _projectMetadataService.currentProjectMetadataNotifier.value;
    if (currentProject != null) {
      logger.logInfo('Project loaded: ${currentProject.name}. Reinitializing preview panel', _logTag);
      // Reset state related to previous project if necessary (e.g., clear visible clips)
      visibleClipsNotifier.value = [];
      clipRectsNotifier.value = {};
      clipFlipsNotifier.value = {};
      selectedClipIdNotifier.value = null; // Deselect

      // Trigger initial update for the new project
      _handleTimelineOrTransformChange();
    }
  }


  // --- Composite Update Trigger ---

  // Debounce mechanism to avoid excessive FFmpeg calls
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 100); // Adjust as needed

  void _triggerCompositeUpdate() {
     if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

     _debounceTimer = Timer(_debounceDuration, () async {
        logger.logInfo('Debounced: Triggering composite video creation...', _logTag);
        final currentMs = ClipModel.framesToMs(_timelineNavigationViewModel.currentFrameNotifier.value);
        final clips = _timelineViewModel.clipsNotifier.value; // Use the source of truth
        final positions = clipRectsNotifier.value; // Use the latest UI state
        final flips = clipFlipsNotifier.value; // Use the latest UI state
        final size = containerSizeNotifier.value;

        // Filter clips based on current time *before* passing to service
        // This ensures the service only gets clips relevant to the requested time
         final activeClips = clips.where((clip) {
             if (clip.databaseId == null) return false;
             final clipStart = clip.startTimeOnTrackMs;
             final duration = clip.durationInSourceMs;
             final clipEnd = clipStart + duration;
             return currentMs >= clipStart && currentMs < clipEnd && (clip.type == ClipType.video || clip.type == ClipType.image);
         }).toList();


        if (activeClips.isEmpty && currentMs > 0) {
            logger.logInfo('No active clips at ${currentMs}ms, skipping FFmpeg. Player state remains.', _logTag);
            // Optionally clear the player texture if desired when no clips are active
            // await _compositeVideoService.clearPlayer(); // Need to add this method
            return;
        }

         logger.logVerbose('Calling createCompositeVideo with ${activeClips.length} active clips, time ${currentMs}ms, size $size', _logTag);

        try {
          await _compositeVideoService.createCompositeVideo(
            clips: activeClips, // Pass only active clips
            positions: positions, // Pass all known positions
            flips: flips,         // Pass all known flips
            currentTimeMs: currentMs,
            containerSize: size,
          );
          logger.logInfo('Composite video creation request finished.', _logTag);
        } catch (e, stack) {
          logger.logError('Error calling createCompositeVideo: $e\n$stack', _logTag);
        }
     });
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
    _timelineNavigationViewModel.currentFrameNotifier.removeListener(_updatePlaybackPosition);
    _timelineViewModel.clipsNotifier.removeListener(_handleTimelineOrTransformChange);
    // _timelineNavigationViewModel.isPlayingNotifier.removeListener(_handlePlayStateChange); // Removed listener
    _timelineViewModel.selectedClipIdNotifier.removeListener(_updateSelection);
    _projectMetadataService.currentProjectMetadataNotifier.removeListener(
      _handleProjectLoaded,
    );
  
    // Cancel debounce timer if active
    _debounceTimer?.cancel();
  
    // No video controllers to dispose
  
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
    // initializedControllerIdsNotifier.dispose(); // Removed
  
    super.dispose();
    logger.logInfo('PreviewViewModel disposed.', _logTag);
  }
}
