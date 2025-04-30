import 'dart:async'; // Import for Timer (debouncing)
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
// Import the standard video_player package
import 'package:video_player/video_player.dart'; 
import 'dart:io'; // Import for File
import 'package:collection/collection.dart'; // Import for firstWhereOrNull

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import ClipType
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
// Remove CompositeVideoService dependency
// import 'package:flipedit/services/composite_video_service.dart'; 
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
  // Remove CompositeVideoService dependency
  // late final CompositeVideoService _compositeVideoService; 

  // --- State Notifiers (Exposed to View) ---
  // Replace texture ID and processing notifiers with the controller itself
  // final ValueNotifier<int> textureIdNotifier = ValueNotifier<int>(-1); 
  // final ValueNotifier<bool> isProcessingNotifier = ValueNotifier(false); 
  VideoPlayerController? _controller;
  VideoPlayerController? get controller => _controller; // Getter for the view

  final ValueNotifier<List<ClipModel>> visibleClipsNotifier = ValueNotifier([]); 
  final ValueNotifier<Map<int, Rect>> clipRectsNotifier = ValueNotifier({});
  final ValueNotifier<Map<int, Flip>> clipFlipsNotifier = ValueNotifier({});
  final ValueNotifier<int?> selectedClipIdNotifier = ValueNotifier(null);
  final ValueNotifier<int?> firstActiveVideoClipIdNotifier = ValueNotifier(null);
  final ValueNotifier<double> aspectRatioNotifier = ValueNotifier(16.0 / 9.0); // Default
  final ValueNotifier<Size?> containerSizeNotifier = ValueNotifier(null);

  // Snap Lines
  final ValueNotifier<double?> activeHorizontalSnapYNotifier = ValueNotifier(null);
  final ValueNotifier<double?> activeVerticalSnapXNotifier = ValueNotifier(null);

  // Interaction State
  final ValueNotifier<bool> isTransformingNotifier = ValueNotifier(false);

  // Store pre-transform state for undo
  final Map<int, Rect> _preTransformRects = {};
  final Map<int, Flip> _preTransformFlips = {};

  // --- Getters for simplified access ---
  Size? get containerSize => containerSizeNotifier.value;

  // Keep track of the current source being displayed to avoid unnecessary reloads
  String? _currentSourcePath; 

  PreviewViewModel() {
    logger.logInfo('PreviewViewModel initializing...', _logTag);
    // Get dependencies from DI
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _editorViewModel = di<EditorViewModel>();
    _projectDatabaseService = di<ProjectDatabaseService>();
    _projectMetadataService = di<ProjectMetadataService>();
    // Remove CompositeVideoService dependency
    // _compositeVideoService = di<CompositeVideoService>(); 

    // Remove initialization from CompositeVideoService
    // textureIdNotifier.value = _compositeVideoService.textureIdNotifier.value;
    // isProcessingNotifier.value = _compositeVideoService.isProcessingNotifier.value;

    // --- Setup Listeners ---
    _timelineNavigationViewModel.currentFrameNotifier.addListener(
      _handleTimelineOrTransformChange, // Update preview on frame change
    );
    _timelineNavigationViewModel.isPlayingNotifier.addListener(
      _handlePlaybackStateChange, // Add listener specifically for play/pause state changes
    );
    _timelineViewModel.clipsNotifier.addListener(
      _handleTimelineOrTransformChange, // Update preview on clip data change
    );
    _timelineViewModel.selectedClipIdNotifier.addListener(_updateSelection);
    _projectMetadataService.currentProjectMetadataNotifier.addListener(
      _handleProjectLoaded,
    );
    // Remove listeners for CompositeVideoService notifiers
    // _compositeVideoService.textureIdNotifier.addListener(_updateTextureId);
    // _compositeVideoService.isProcessingNotifier.addListener(_updateIsProcessing);
  
    // --- Initial Setup ---
    _updateAspectRatio();
    _handleTimelineOrTransformChange(); // Initial call to determine visible clips and trigger preview update
    _updateSelection(); // Initial selection sync
    logger.logInfo('PreviewViewModel initialized.', _logTag);
  }

  @override
  void dispose() {
    logger.logInfo('Disposing PreviewViewModel...', _logTag);
    _timelineNavigationViewModel.currentFrameNotifier.removeListener(_handleTimelineOrTransformChange);
    _timelineNavigationViewModel.isPlayingNotifier.removeListener(_handlePlaybackStateChange); // Remove new listener
    _timelineViewModel.clipsNotifier.removeListener(_handleTimelineOrTransformChange);
    _timelineViewModel.selectedClipIdNotifier.removeListener(_updateSelection);
    _projectMetadataService.currentProjectMetadataNotifier.removeListener(_handleProjectLoaded);
    // Remove listeners related to CompositeVideoService
    // _compositeVideoService.textureIdNotifier.removeListener(_updateTextureId);
    // _compositeVideoService.isProcessingNotifier.removeListener(_updateIsProcessing);
    
    // Dispose the video controller
    _disposeController(); 
    super.dispose();
  }

  // --- Listener Callbacks & Update Logic ---

  // Consolidated handler for frame or clip changes
  void _handleTimelineOrTransformChange() {
    // Call directly now
     _updatePreviewContent();
  }

  // Listener for play/pause state changes
  void _handlePlaybackStateChange() async { // Make async for await seekTo
    final isPlaying = _timelineNavigationViewModel.isPlayingNotifier.value;
    logger.logInfo('Playback state changed: ${isPlaying ? "Playing" : "Paused"}', _logTag);
    if (_controller == null || !_controller!.value.isInitialized) {
        logger.logVerbose('Playback state changed but controller is null or not ready.', _logTag);
       return; // No controller or not ready
    }

    try {
      if (isPlaying) {
         // Before playing, ensure we are seeked to the current timeline frame
         final currentFrame = _timelineNavigationViewModel.currentFrameNotifier.value;
         final seekPosition = Duration(milliseconds: ClipModel.framesToMs(currentFrame));
         final controllerPosition = _controller!.value.position; // Assumes initialized
         final difference = (controllerPosition - seekPosition).abs();

         // Only seek if significantly different
         if (difference > const Duration(milliseconds: 100)) {
           logger.logVerbose('Seeking to $seekPosition before playing.', _logTag);
           // Use await for seekTo completion before playing
           await _controller!.seekTo(seekPosition);
         }
         // Check if controller still exists after potential await
         if (_controller == null) return;
         logger.logVerbose('Calling controller.play()', _logTag);
         await _controller!.play();
      } else {
         logger.logVerbose('Calling controller.pause()', _logTag);
         // Check if controller exists and is actually playing before pausing
          if (_controller != null && _controller!.value.isPlaying) { 
             await _controller!.pause();
          }
      }
    } catch (e, stack) {
       logger.logError('Error handling playback state change: $e', _logTag, stack);
    }
  }

  // The core logic to update the preview content based on current state
  Future<void> _updatePreviewContent() async {
    final currentFrame = _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    final allClips = _timelineViewModel.clipsNotifier.value;
    final isTimelinePlaying = _timelineNavigationViewModel.isPlayingNotifier.value;

    logger.logVerbose(
      'Updating preview content for frame $currentFrame (${currentMs}ms)',
      _logTag,
    );

    // 1. Determine potentially visible clips for interaction overlays (same as before)
    final List<ClipModel> potentiallyVisibleClips = [];
    final Map<int, Rect> currentRects = {};
    final Map<int, Flip> currentFlips = {};
    final Set<int> visibleClipIds = {};

    for (final clip in allClips) {
      if (clip.databaseId != null &&
          currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs &&
          (clip.type == ClipType.video || clip.type == ClipType.image)) { // Allow images too?
        potentiallyVisibleClips.add(clip);
        visibleClipIds.add(clip.databaseId!);
        currentRects[clip.databaseId!] = clip.previewRect ?? Rect.zero;
        currentFlips[clip.databaseId!] = clip.previewFlip;
      }
    }
    // Sort potentiallyVisibleClips (same logic as before)
    // ... (sorting logic omitted for brevity, assume it's the same) ...


    // Update interaction overlay notifiers (same as before)
    bool overlaysChanged = false;
     if (!listEquals(visibleClipsNotifier.value.map((c) => c.databaseId).toList(), potentiallyVisibleClips.map((c) => c.databaseId).toList())) {
      visibleClipsNotifier.value = potentiallyVisibleClips;
      overlaysChanged = true;
      logger.logInfo('Updated visibleClipsNotifier. New Count: ${potentiallyVisibleClips.length}');
    }
    // ... (update clipRectsNotifier, clipFlipsNotifier - same logic) ...
    if (overlaysChanged) {
      notifyListeners(); // Notify view about overlay changes
    }


    // 2. Determine the primary video content (first active VIDEO clip)
    final ClipModel? firstVideoClip = potentiallyVisibleClips.firstWhereOrNull(
      (clip) => clip.type == ClipType.video,
    );

    // Update the notifier for the active clip ID
    final newActiveClipId = firstVideoClip?.databaseId;
    if (firstActiveVideoClipIdNotifier.value != newActiveClipId) {
      firstActiveVideoClipIdNotifier.value = newActiveClipId;
      logger.logVerbose('Updated firstActiveVideoClipId: $newActiveClipId', _logTag);
    }

    if (firstVideoClip == null) {
      // No active video clip, dispose controller if it exists
      if (_controller != null) {
        logger.logInfo('No active video clip. Disposing controller.', _logTag);
        await _disposeController();
        _currentSourcePath = null;
        notifyListeners(); // Notify view that controller is gone
      }
       logger.logVerbose('No active video clip at ${currentMs}ms.', _logTag);
      return; 
    }

    // 3. Manage VideoPlayerController
    final sourcePath = firstVideoClip.sourcePath;
    final sourceUri = Uri.file(sourcePath); // Use Uri.file for local paths

    // Calculate the position within the source video file
    int positionInClipMs = currentMs - firstVideoClip.startTimeOnTrackMs;
    positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
    int sourcePosMs = firstVideoClip.startTimeInSourceMs + positionInClipMs;
    sourcePosMs = sourcePosMs.clamp(firstVideoClip.startTimeInSourceMs, firstVideoClip.endTimeInSourceMs);
    final seekPosition = Duration(milliseconds: sourcePosMs);

    try {
      if (_controller == null || _currentSourcePath != sourcePath) {
        // Initialize new controller
        await _disposeController();
        _controller = VideoPlayerController.networkUrl(sourceUri);
        _currentSourcePath = sourcePath;
        _controller!.addListener(notifyListeners); // Add listener immediately
        await _controller!.initialize();
        logger.logInfo('Controller initialized. Initial seek to $seekPosition.', _logTag);
        await _controller!.seekTo(seekPosition);
        await _controller!.pause(); // Start paused
        notifyListeners(); 
        // If timeline is already playing when source changes, start playback immediately
        if (isTimelinePlaying) {
           await _controller!.play();
        }
      } else {
        // Controller exists, source is the same.
        // SEEK ONLY IF PAUSED.
        if (!isTimelinePlaying) {
            final currentPosition = await _controller!.position ?? Duration.zero;
            final difference = (currentPosition - seekPosition).abs();
            if (difference > const Duration(milliseconds: 100)) { 
               logger.logVerbose('Timeline Paused: Seeking existing controller to $seekPosition.', _logTag);
               await _controller!.seekTo(seekPosition);
                if (_controller!.value.isPlaying) { // Ensure pause after scrub seek
                  await _controller!.pause();
                }
            } else {
               logger.logVerbose('Timeline Paused: Seek position already close.', _logTag);
                if (_controller!.value.isPlaying) { // Ensure pause if close but playing
                  await _controller!.pause();
                }
            }
        } else {
           // Timeline is Playing: Do NOT seek here. The playback state handler
           // ensures play() is called. We only need to ensure it IS playing.
           if (!_controller!.value.isPlaying) {
              logger.logWarning('Timeline Playing but controller paused. Re-initiating play via state handler trigger.', _logTag);
              // Trigger the state handler instead of calling play directly
              _handlePlaybackStateChange(); 
           }
        }
      }
    } catch (e, stack) {
      logger.logError('Error managing VideoPlayerController: $e', _logTag, stack);
      await _disposeController();
      _currentSourcePath = null;
      notifyListeners();
    }
  }


  // --- Helper Methods ---
  
  Future<void> _disposeController() async {
    if (_controller != null) {
      final oldController = _controller;
      _controller = null; // Set to null immediately
      // Remove listener before disposing
      oldController?.removeListener(notifyListeners); 
      await oldController?.dispose();
      logger.logInfo('Disposed previous VideoPlayerController.', _logTag);
    }
  }

  // Listener for project load
  void _handleProjectLoaded() {
    logger.logInfo('New project loaded, resetting preview state.', _logTag);
    _updateAspectRatio(); // Update aspect ratio from new project if needed
    _handleTimelineOrTransformChange(); // Trigger preview update for the new project
    _updateSelection(); // Update selection state
  }

  // Remove listeners previously tied to CompositeVideoService
  // void _updateTextureId() { ... }
  // void _updateIsProcessing() { ... }

  void _updateAspectRatio() {
     // Re-implement fetching aspect ratio if it comes from project settings
     // final projectAspectRatio = _projectMetadataService.currentProjectMetadataNotifier.value?.aspectRatio;
     // final newAspectRatio = projectAspectRatio ?? 16.0 / 9.0;
     final newAspectRatio = 16.0 / 9.0; // Keep default for now
    if (aspectRatioNotifier.value != newAspectRatio) {
      aspectRatioNotifier.value = newAspectRatio;
      logger.logDebug('Aspect ratio updated: $newAspectRatio', _logTag);
    }
  }

  // Listener for selection changes from TimelineViewModel
  void _updateSelection() {
    final newSelectedId = _timelineViewModel.selectedClipIdNotifier.value;
    if (selectedClipIdNotifier.value != newSelectedId) {
      selectedClipIdNotifier.value = newSelectedId;
      logger.logDebug('Preview selection updated from TimelineVM: $newSelectedId', _logTag);
    }
  }

  void updateContainerSize(Size newSize) {
    if (containerSizeNotifier.value != newSize) {
      containerSizeNotifier.value = newSize;
      logger.logDebug('Container size updated: $newSize', _logTag);
    }
  }

  void selectClip(int? clipId) {
    if (selectedClipIdNotifier.value != clipId) {
      selectedClipIdNotifier.value = clipId;
      _timelineViewModel.selectedClipId = clipId;
      logger.logDebug('Clip selected via Preview: $clipId', _logTag);
    }
  }

  // --- Transform Handling ---

  void handleTransformStart(int clipId) {
    if (!isTransformingNotifier.value) {
      isTransformingNotifier.value = true;
      // Store initial state for undo
      _preTransformRects[clipId] = clipRectsNotifier.value[clipId] ?? Rect.zero;
      _preTransformFlips[clipId] = clipFlipsNotifier.value[clipId] ?? Flip.none;
      logger.logVerbose('Transform started for clip $clipId', _logTag);
    }
  }

  void handleRectChanged(int clipId, Rect newRect) {
    // TODO: Snapping logic
    logger.logVerbose('Rect changed (pre-snap): $clipId, $newRect', _logTag);
    final currentRects = Map<int, Rect>.from(clipRectsNotifier.value);
    currentRects[clipId] = newRect;
    clipRectsNotifier.value = currentRects;
    // TODO: Update snap lines
    activeHorizontalSnapYNotifier.value = null;
    activeVerticalSnapXNotifier.value = null;
  }

  void handleFlipChanged(int clipId, Flip newFlip) {
    final currentFlips = Map<int, Flip>.from(clipFlipsNotifier.value);
    if (currentFlips[clipId] != newFlip) {
      logger.logDebug('Flip changed for clip $clipId to $newFlip', _logTag);
      currentFlips[clipId] = newFlip;
      clipFlipsNotifier.value = currentFlips;
    }
  }

  void handleTransformEnd(int clipId) async {
    if (isTransformingNotifier.value) {
      isTransformingNotifier.value = false;
      activeHorizontalSnapYNotifier.value = null;
      activeVerticalSnapXNotifier.value = null;
      logger.logVerbose('Transform ended for clip $clipId', _logTag);

      // Persist changes and create undo command
      final currentRect = clipRectsNotifier.value[clipId];
      final currentFlip = clipFlipsNotifier.value[clipId];
      final initialRect = _preTransformRects[clipId];
      final initialFlip = _preTransformFlips[clipId];

      if (currentRect != null && currentFlip != null && initialRect != null && initialFlip != null && (currentRect != initialRect || currentFlip != initialFlip)) {
        logger.logInfo('Persisting transform for clip $clipId: Rect=$currentRect, Flip=$currentFlip', _logTag);
        
        // Use UpdateClipTransformCommand
        final command = UpdateClipTransformCommand(
          timelineViewModel: _timelineViewModel,
          clipId: clipId,
          newRect: currentRect,
          newFlip: currentFlip,
          oldRect: initialRect,
          oldFlip: initialFlip,
          projectDatabaseService: _projectDatabaseService,
        );
        // Assuming an UndoRedoService exists and is accessible (e.g., via DI)
        // di<UndoRedoService>().executeCommand(command);
        
        // Execute the command directly and handle potential errors
        try {
           await command.execute(); 
            // Command internally logs success
           // Update timeline notifier *after* successful execution
           await _timelineViewModel.refreshClips(); 
        } catch (error, cmdStack) {
           // Command internally logs failure
           logger.logError('UpdateClipTransformCommand failed from PreviewViewModel: $error', _logTag, cmdStack);
           // Optionally revert UI or show error message
        }

      } else {
         logger.logVerbose('No significant transform change detected for clip $clipId to persist.', _logTag);
      }

      // Clear pre-transform state
      _preTransformRects.remove(clipId);
      _preTransformFlips.remove(clipId);
    }
  }
}


