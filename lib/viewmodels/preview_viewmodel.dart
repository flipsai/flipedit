import 'dart:async';
import 'dart:io';
import 'package:flipedit/services/ffmpeg_composite_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/playback_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PreviewViewModel extends ChangeNotifier {
  final String _logTag = 'PreviewViewModel';

  // --- Injected Dependencies (via DI) ---
  late final TimelineViewModel _timelineViewModel;
  late final TimelineNavigationViewModel _timelineNavigationViewModel;
  late final ProjectMetadataService _projectMetadataService;
  late final FfmpegCompositeService _ffmpegCompositeService; // Initialize in constructor
  late final PlaybackService _playbackService; // Inject PlaybackService

  // --- State Notifiers (Exposed to View) ---
  final ValueNotifier<String?> compositeFramePathNotifier = ValueNotifier(null); // Path to the generated frame image
  final ValueNotifier<bool> isGeneratingFrameNotifier = ValueNotifier(false); // Loading indicator

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

  // --- Getters for simplified access ---
  Size? get containerSize => containerSizeNotifier.value;
  String? get compositeFramePath => compositeFramePathNotifier.value;
  bool get isGeneratingFrame => isGeneratingFrameNotifier.value;

  // Removed: String? _currentSourcePath;
  String? _lastGeneratedFramePath; // Keep track to delete old frames
  final Uuid _uuid = const Uuid(); // For generating unique filenames

  PreviewViewModel() {
    logger.logInfo('PreviewViewModel initializing...', _logTag);
    // Get dependencies from DI
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _projectMetadataService = di<ProjectMetadataService>();
    _ffmpegCompositeService = di<FfmpegCompositeService>();
    _playbackService = di<PlaybackService>(); // Get PlaybackService from DI

    // --- Setup Listeners ---
    _timelineNavigationViewModel.currentFrameNotifier.addListener(
      _onFrameChanged, // Use a new handler that checks playback state first
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
    _timelineNavigationViewModel.currentFrameNotifier.removeListener(_onFrameChanged); // Update listener removal
    _timelineNavigationViewModel.isPlayingNotifier.removeListener(_handlePlaybackStateChange); // Remove new listener
    _timelineViewModel.clipsNotifier.removeListener(_handleTimelineOrTransformChange);
    _timelineViewModel.selectedClipIdNotifier.removeListener(_updateSelection);
    _projectMetadataService.currentProjectMetadataNotifier.removeListener(_handleProjectLoaded);
    // Remove listeners related to CompositeVideoService
    // _compositeVideoService.textureIdNotifier.removeListener(_updateTextureId);
    // _compositeVideoService.isProcessingNotifier.removeListener(_updateIsProcessing);
    
    // Removed: _disposeController();
    _deleteLastGeneratedFrame(); // Clean up the last frame if it exists
    super.dispose();
  }

  // --- Listener Callbacks & Update Logic ---

  // New handler for frame changes that checks playback state first
  void _onFrameChanged() {
    // Only trigger the full update logic if NOT playing
    if (!_playbackService.isPlayingNotifier.value) {
      logger.logVerbose('Frame changed while paused/scrubbing, updating preview.', _logTag);
      _handleTimelineOrTransformChange(); // Call the existing logic
    } else {
      // During playback, do nothing here. The preview remains static.
      logger.logVerbose('Playback active, skipping preview update on frame change.', _logTag);
    }
  }

  // Listener for play/pause state changes
  void _handlePlaybackStateChange() {
    // Playback state changes don't directly affect the static frame generation.
    // If the view needs to react instantly to play/pause (e.g., show an overlay),
    // it can listen directly to _timelineNavigationViewModel.isPlayingNotifier.
    // Triggering a frame update here is likely unnecessary.
    logger.logVerbose('Playback state changed. Frame update handled by frame changes.', _logTag);
  }

  // The core logic to update the preview content based on current state (Made public)
  Future<void> updatePreviewContent() async {
    if (isGeneratingFrameNotifier.value) {
      logger.logVerbose('Frame generation already in progress, skipping.', _logTag);
      return; // Avoid concurrent generations
    }

    // --- Check Playback State ---
    if (_playbackService.isPlayingNotifier.value) {
      logger.logVerbose('Playback active, skipping composite frame generation.', _logTag);
      // Optionally clear the frame or leave the last one showing
      // If we want to show the frame *before* playback started, we might need
      // additional logic in _handlePlaybackStateChange to store/restore the path.
      // For now, just skip generation.
      return;
    }
    // --- End Playback State Check ---

    final currentFrame = _timelineNavigationViewModel.currentFrameNotifier.value;
    final currentMs = ClipModel.framesToMs(currentFrame);
    final allClips = _timelineViewModel.clipsNotifier.value;

    logger.logVerbose(
      'Attempting to update preview content for frame $currentFrame (${currentMs}ms)',
      _logTag,
    );

    // 1. Determine potentially visible clips for interaction overlays
    final List<ClipModel> potentiallyVisibleClips = [];
    final Map<int, Rect> currentRects = {};
    final Map<int, Flip> currentFlips = {};
    final Set<int> visibleClipIds = {};

    for (final clip in allClips) {
      if (clip.databaseId != null &&
          currentMs >= clip.startTimeOnTrackMs &&
          currentMs < clip.endTimeOnTrackMs &&
          (clip.type == ClipType.video || clip.type == ClipType.image)) { // Include images for overlays
        potentiallyVisibleClips.add(clip);
        visibleClipIds.add(clip.databaseId!);
        currentRects[clip.databaseId!] = clip.previewRect ?? const Rect.fromLTWH(0, 0, 1, 1); // Default if null
        currentFlips[clip.databaseId!] = clip.previewFlip;
      }
    }

    // Update interaction overlay notifiers
    bool overlaysChanged = false;
    if (!listEquals(visibleClipsNotifier.value.map((c) => c.databaseId).toList(), potentiallyVisibleClips.map((c) => c.databaseId).toList())) {
      visibleClipsNotifier.value = potentiallyVisibleClips;
      overlaysChanged = true;
      logger.logInfo('Updated visibleClipsNotifier. New Count: ${potentiallyVisibleClips.length}');
    }
    if (!mapEquals(clipRectsNotifier.value, currentRects)) {
      clipRectsNotifier.value = currentRects;
      overlaysChanged = true;
    }
    if (!mapEquals(clipFlipsNotifier.value, currentFlips)) {
      clipFlipsNotifier.value = currentFlips;
      overlaysChanged = true;
    }
    // 2. Filter for only *video* clips for the composite video generation
    final List<ClipModel> activeVideoClips = potentiallyVisibleClips
        .where((clip) => clip.type == ClipType.video)
        .toList();

    // Update the first active video clip ID (might still be useful for some UI elements)
    final newActiveClipId = activeVideoClips.isNotEmpty ? activeVideoClips.first.databaseId : null;
    if (firstActiveVideoClipIdNotifier.value != newActiveClipId) {
      firstActiveVideoClipIdNotifier.value = newActiveClipId;
      logger.logVerbose('Updated firstActiveVideoClipId: $newActiveClipId', _logTag);
    }

    // Get container size for canvas dimensions
    final Size? size = containerSizeNotifier.value;
    if (size == null || size.isEmpty || size.width <= 0 || size.height <= 0) {
      logger.logWarning('Container size is invalid ($size). Cannot generate composite video.', _logTag);
      // Ensure frame path is null if we can't generate
      if (compositeFramePathNotifier.value != null) {
        await _deleteLastGeneratedFrame();
        compositeFramePathNotifier.value = null;
      }
      return;
    }
    
    // Use floor to avoid potential issues with FFmpeg filters if dimensions aren't integers
    final int canvasWidth = size.width.floor();
    final int canvasHeight = size.height.floor();

    // If no *video* clips are active, clear the frame
    if (activeVideoClips.isEmpty) {
      logger.logVerbose('No active video clips at ${currentMs}ms. Clearing preview.', _logTag);
      if (compositeFramePathNotifier.value != null) {
        await _deleteLastGeneratedFrame();
        compositeFramePathNotifier.value = null;
      }
      return;
    }

    // Generate a unique output path in the temporary directory
    final tempDir = await getTemporaryDirectory();
    // Use .mp4 extension for video instead of png
    final outputFileName = 'flipedit_preview_${_uuid.v4()}.mp4';
    final outputFilePath = '${tempDir.path}/$outputFileName';

    isGeneratingFrameNotifier.value = true;

    try {
      // 3. Prepare inputs for FfmpegCompositeService
      final List<Map<String, dynamic>> videoInputs = [];
      final List<Map<String, dynamic>> layoutInputs = [];

      for (final clip in activeVideoClips) {
        // Calculate source position in milliseconds
        int positionInClipMs = currentMs - clip.startTimeOnTrackMs;
        positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs; // Clamp at start
        int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
        // Clamp at end based on source duration
        sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);

        videoInputs.add({
          'path': clip.sourcePath,
          'source_pos_ms': sourcePosMs,
        });

        // Convert normalized Rect (0-1) to absolute pixel values for FFmpeg layout
        final Rect normRect = clip.previewRect ?? const Rect.fromLTWH(0, 0, 1, 1); // Default to full if null
        layoutInputs.add({
          'x': (normRect.left * canvasWidth).round().clamp(0, canvasWidth),
          'y': (normRect.top * canvasHeight).round().clamp(0, canvasHeight),
          'width': (normRect.width * canvasWidth).round().clamp(1, canvasWidth),
          'height': (normRect.height * canvasHeight).round().clamp(1, canvasHeight),
          'flip_h': clip.previewFlip == Flip.horizontal,
          'flip_v': clip.previewFlip == Flip.vertical,
        });
      }

      logger.logInfo(
        'Generating composite video with ${activeVideoClips.length} clips at ${currentMs}ms. Output: $outputFilePath',
        _logTag);

      // 4. Call FfmpegCompositeService to generate a short video segment (1 second)
      // This replaces the single-frame PNG generation with video generation
      final success = await _ffmpegCompositeService.generateVideoSegment(
        videoInputs: videoInputs,
        layoutInputs: layoutInputs,
        outputFile: outputFilePath,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        durationMs: 1000,
        fps: 30,
      );

      if (success) {
        logger.logInfo('Composite video generated successfully: $outputFilePath', _logTag);
        // Delete the previous file *before* updating the notifier
        await _deleteLastGeneratedFrame();
        compositeFramePathNotifier.value = outputFilePath;
        _lastGeneratedFramePath = outputFilePath; // Store the new path
      } else {
        logger.logError('Failed to generate composite video.', _logTag);
        // Clear the path on failure
        await _deleteLastGeneratedFrame();
        compositeFramePathNotifier.value = null;
        _lastGeneratedFramePath = null;
        // Attempt to delete the failed output file
        try {
          final failedFile = File(outputFilePath);
          if (await failedFile.exists()) {
            await failedFile.delete();
            logger.logInfo('Deleted failed output file: $outputFilePath', _logTag);
          }
        } catch (e) {
          logger.logWarning('Could not delete failed output file $outputFilePath: $e', _logTag);
        }
      }
    } catch (e, stack) {
      logger.logError('Error generating composite video: $e', _logTag, stack);
      await _deleteLastGeneratedFrame();
      compositeFramePathNotifier.value = null;
      _lastGeneratedFramePath = null;
    } finally {
      isGeneratingFrameNotifier.value = false;
    }
  }

  void _handleTimelineOrTransformChange() {
    updatePreviewContent(); 
  }

  // --- Helper Methods ---
  
  Future<void> _deleteLastGeneratedFrame() async {
    if (_lastGeneratedFramePath != null) {
      final pathToDelete = _lastGeneratedFramePath!;
      _lastGeneratedFramePath = null; // Reset path immediately
      try {
        final file = File(pathToDelete);
        if (await file.exists()) {
          await file.delete();
          logger.logVerbose('Deleted old frame: $pathToDelete', _logTag);
        }
      } catch (e) {
        logger.logWarning('Failed to delete old frame: $pathToDelete - $e', _logTag);
      }
    }
  }

  // Listener for project load
  void _handleProjectLoaded() {
    logger.logInfo('New project loaded, resetting preview state.', _logTag);
    _updateAspectRatio(); // Update aspect ratio from new project if needed
    updatePreviewContent(); // Trigger preview update for the new project
    _updateSelection(); // Update selection state
  }

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

  /// Generates a pre-rendered video segment starting from the specified frame
  /// and containing the specified number of frames.
  ///
  /// This is used for smooth playback of video segments without generating frames on-the-fly.
  ///
  /// Parameters:
  /// - `startFrame`: The frame to start rendering from
  /// - `frameCount`: Number of frames to render (default: 100)
  /// - `outputPath`: Path where the output MP4 file will be saved
  ///
  /// Returns `true` if video was successfully generated, `false` otherwise
  Future<bool> generatePreRenderedVideo({
    required int startFrame,
    int frameCount = 1000,
    required String outputPath,
  }) async {
    logger.logInfo('Generating pre-rendered video segment starting at frame $startFrame with $frameCount frames: $outputPath', _logTag);
    
    isGeneratingFrameNotifier.value = true;
    
    try {
      // Convert frame numbers to milliseconds
      final startTimeMs = ClipModel.framesToMs(startFrame);
      final durationMs = ClipModel.framesToMs(frameCount);
      final endTimeMs = startTimeMs + durationMs;
      
      // Get all active clips for the time range
      final activeClips = _getTimeRangeClips(startTimeMs, endTimeMs);
      if (activeClips.isEmpty) {
        logger.logWarning('No active clips for the time range ${startTimeMs}ms-${endTimeMs}ms', _logTag);
        return false;
      }
      
      // Get container size for canvas dimensions
      final Size? size = containerSizeNotifier.value;
      if (size == null || size.isEmpty || size.width <= 0 || size.height <= 0) {
        logger.logWarning('Container size is invalid ($size). Cannot generate video segment.', _logTag);
        return false;
      }
      
      // Use floor to avoid potential issues with FFmpeg filters if dimensions aren't integers
      final int canvasWidth = size.width.floor();
      final int canvasHeight = size.height.floor();
      
      // Build FFmpeg command to generate a video segment
      final List<String> ffmpegArgs = [];
      final List<Map<String, dynamic>> videoInputs = [];
      final List<Map<String, dynamic>> layoutInputs = [];
      
      // Prepare inputs for each active clip
      for (final clip in activeClips) {
        // Calculate source position at start time
        int positionInClipMs = startTimeMs - clip.startTimeOnTrackMs;
        positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
        int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
        sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);
        
        videoInputs.add({
          'path': clip.sourcePath,
          'source_pos_ms': sourcePosMs,
        });
        
        // Convert normalized Rect (0-1) to absolute pixel values for FFmpeg layout
        final Rect normRect = clip.previewRect ?? const Rect.fromLTWH(0, 0, 1, 1); // Default to full if null
        layoutInputs.add({
          'x': (normRect.left * canvasWidth).round().clamp(0, canvasWidth),
          'y': (normRect.top * canvasHeight).round().clamp(0, canvasHeight),
          'width': (normRect.width * canvasWidth).round().clamp(1, canvasWidth),
          'height': (normRect.height * canvasHeight).round().clamp(1, canvasHeight),
          'flip_h': clip.previewFlip == Flip.horizontal,
          'flip_v': clip.previewFlip == Flip.vertical,
        });
      }
      
      // Use FFmpegCompositeService to generate a video segment instead of a single frame
      final result = await _ffmpegCompositeService.generateVideoSegment(
        videoInputs: videoInputs,
        layoutInputs: layoutInputs,
        outputFile: outputPath,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        durationMs: durationMs
      );
      
      if (!result) {
        logger.logError('Failed to generate pre-rendered video segment', _logTag);
        return false;
      }
      
      logger.logInfo('Successfully generated pre-rendered video segment at: $outputPath', _logTag);
      return true;
    } catch (e, stack) {
      logger.logError('Error generating pre-rendered video segment: $e', _logTag, stack);
      return false;
    } finally {
      isGeneratingFrameNotifier.value = false;
    }
  }
  
  /// Helper method to get all clips that are active during a time range
  List<ClipModel> _getTimeRangeClips(int startTimeMs, int endTimeMs) {
    final allClips = _timelineViewModel.clipsNotifier.value;
    final List<ClipModel> activeClips = [];
    
    for (final clip in allClips) {
      // Clip is active if any part of it overlaps with the time range
      final clipStartMs = clip.startTimeOnTrackMs;
      final clipEndMs = clip.endTimeOnTrackMs;
      
      // Check if there's an overlap between the clip and the time range
      if (!(clipEndMs <= startTimeMs || clipStartMs >= endTimeMs)) {
        activeClips.add(clip);
      }
    }
    
    return activeClips;
  }
}


