import 'dart:async'; // Import for Timer (debouncing)
import 'dart:io'; // Add File import
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
// Import the standard video_player package
import 'package:video_player/video_player.dart'; 

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import ClipType
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/composite_video_service.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

class PreviewViewModel extends ChangeNotifier {
  final String _logTag = 'PreviewViewModel';

  // --- Injected Dependencies (via DI) ---
  late final TimelineViewModel _timelineViewModel;
  late final TimelineNavigationViewModel _timelineNavigationViewModel;
  late final EditorViewModel _editorViewModel;
  late final ProjectDatabaseService _projectDatabaseService;
  late final ProjectMetadataService _projectMetadataService;
  late final CompositeVideoService _compositeVideoService;

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
    _compositeVideoService = di<CompositeVideoService>();

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

    // Update interaction overlay notifiers (same as before)
    bool overlaysChanged = false;
    if (!listEquals(visibleClipsNotifier.value.map((c) => c.databaseId).toList(), potentiallyVisibleClips.map((c) => c.databaseId).toList())) {
      visibleClipsNotifier.value = potentiallyVisibleClips;
      overlaysChanged = true;
      logger.logInfo('Updated visibleClipsNotifier. New Count: ${potentiallyVisibleClips.length}');
    }

    // Update rects and flips if needed
    if (!mapEquals(clipRectsNotifier.value, currentRects)) {
      clipRectsNotifier.value = currentRects;
      overlaysChanged = true;
    }
    if (!mapEquals(clipFlipsNotifier.value, currentFlips)) {
      clipFlipsNotifier.value = currentFlips;
      overlaysChanged = true;
    }
    
    if (overlaysChanged) {
      notifyListeners(); // Notify view about overlay changes
    }

    // 2. Filter for only video clips for composite display
    final List<ClipModel> activeVideoClips = potentiallyVisibleClips
        .where((clip) => clip.type == ClipType.video)
        .toList();

    // Update the notifier for the active clip ID (keeping for now)
    final newActiveClipId = activeVideoClips.isNotEmpty ? activeVideoClips.first.databaseId : null;
    if (firstActiveVideoClipIdNotifier.value != newActiveClipId) {
      firstActiveVideoClipIdNotifier.value = newActiveClipId;
      logger.logVerbose('Updated firstActiveVideoClipId: $newActiveClipId', _logTag);
    }

    if (activeVideoClips.isEmpty) {
      // No active video clips, dispose controller if it exists
      if (_controller != null) {
        logger.logInfo('No active video clips. Disposing controller.', _logTag);
        await _disposeController();
        _currentSourcePath = null;
        notifyListeners(); // Notify view that controller is gone
      }
      logger.logVerbose('No active video clips at ${currentMs}ms.', _logTag);
      return;
    }
    
    // Skip composite video handling if there are multiple video clips - CompositePreviewPanel handles this now
    if (activeVideoClips.length >= 2) {
      logger.logInfo('Multiple active video clips (${activeVideoClips.length}). Skipping processing as CompositePreviewPanel will handle it.', _logTag);
      // Dispose any existing controller since it's now handled by CompositePreviewPanel
      if (_controller != null) {
        await _disposeController();
        _currentSourcePath = null;
        notifyListeners();
      }
      return;
    }

    try {
      // 3. Use CompositeVideoService to generate the composite display
      logger.logInfo('Generating composite video with ${activeVideoClips.length} clips at ${currentMs}ms', _logTag);
      
      // Pass the container size to the composite service
      final containerSize = containerSizeNotifier.value;
      
      // Call the composite service to generate the video
      final success = await _compositeVideoService.createCompositeVideo(
        clips: activeVideoClips,
        currentTimeMs: currentMs,
        containerSize: containerSize,
      );
      
      if (!success) {
        logger.logError('Failed to create composite video', _logTag);
        
        // For single clip case, fall back to direct video player as backup
        if (activeVideoClips.length == 1) {
          logger.logInfo('Falling back to direct video playback for single clip', _logTag);
          final clip = activeVideoClips.first;
          
          // Calculate the source position
          int positionInClipMs = currentMs - clip.startTimeOnTrackMs;
          positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
          int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
          sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);
          final seekPosition = Duration(milliseconds: sourcePosMs);
          
          // Use direct video player for the single clip
          await _disposeController();
          _controller = VideoPlayerController.file(File(clip.sourcePath));
          _currentSourcePath = clip.sourcePath;
          
          // Initialize and prepare
          _controller!.addListener(notifyListeners);
          await _controller!.initialize();
          await _controller!.seekTo(seekPosition);
          
          // Update playback state based on timeline
          if (isTimelinePlaying) {
            await _controller!.play();
          } else {
            await _controller!.pause();
          }
          
          notifyListeners();
          logger.logInfo('Successfully set up direct playback for single clip', _logTag);
          return;
        }
        
        // Clean up on failure
        await _disposeController();
        _currentSourcePath = null;
        notifyListeners();
        return;
      }
      
      // 4. Get the texture from the composite service and create a VideoPlayerController
      final textureId = _compositeVideoService.textureId;
      if (textureId <= 0) {
        logger.logError('Invalid texture ID from composite service: $textureId', _logTag);
        await _disposeController();
        _currentSourcePath = null;
        notifyListeners();
        return;
      }
      
      // If we have a new texture ID or no controller, create one
      final newSourcePath = "composite_$textureId"; // Use texture ID as part of unique identifier
      if (_controller == null || _currentSourcePath != newSourcePath) {
        // Dispose old controller
        await _disposeController();
        
        // Get the path from the composite service
        final compositePath = _compositeVideoService.getCompositeFilePath();
        if (compositePath == null || compositePath.isEmpty) {
          logger.logError('Invalid composite file path from service', _logTag);
          notifyListeners();
          return;
        }
        
        // Create a new controller using the file path
        _controller = VideoPlayerController.file(
          File(compositePath),
        );
        _currentSourcePath = newSourcePath;
        
        // Initialize and prepare
        _controller!.addListener(notifyListeners);
        await _controller!.initialize();
        
        // Update playback state based on timeline
        if (isTimelinePlaying) {
          await _controller!.play();
        } else {
          await _controller!.pause();
        }
        
        // Notify UI that controller has changed
        notifyListeners();
      } else {
        // Controller exists but we may need to update playback state
        if (isTimelinePlaying && !_controller!.value.isPlaying) {
          await _controller!.play();
        } else if (!isTimelinePlaying && _controller!.value.isPlaying) {
          await _controller!.pause();
        }
      }
      
      logger.logInfo('Successfully updated composite video display', _logTag);
      
    } catch (e, stack) {
      logger.logError('Error creating or displaying composite video: $e', _logTag, stack);
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
}


