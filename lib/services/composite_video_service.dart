import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart'; // Add VideoPlayerController import
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flipedit/services/mdk_player_service.dart';
import 'package:watch_it/watch_it.dart'; // Import watch_it to access 'di'
import 'package:flipedit/services/ffmpeg_composite_service.dart';
import 'package:flutter/material.dart';

class CompositeVideoService {
  final String _logTag = 'CompositeVideoService';

  // Dependencies (obtained via Service Locator or constructor)
  late final MdkPlayerService _mdkPlayerService;
  late final FfmpegCompositeService _ffmpegCompositeService;

  // Path to the current composite video frame file
  String? _currentCompositeFilePath;

  // Notifier for the compositing process state
  final ValueNotifier<bool> isProcessingNotifier = ValueNotifier(false);

  // Lock to prevent concurrent compositing operations (FFmpeg is likely not thread-safe)
  // Using a simple boolean flag as FfmpegCompositeService handles the actual execution.
  bool _isCompositing = false;

  // --- Expose relevant notifiers from MdkPlayerService ---
  ValueNotifier<int> get textureIdNotifier => _mdkPlayerService.textureIdNotifier;
  ValueNotifier<bool> get isPlayingNotifier => _mdkPlayerService.isPlayingNotifier;
  ValueNotifier<bool> get isPlayerReadyNotifier => _mdkPlayerService.isPlayerReadyNotifier;
  int get textureId => textureIdNotifier.value;

  /// Gets the current composite file path
  String? getCompositeFilePath() {
    return _currentCompositeFilePath;
  }

  CompositeVideoService({MdkPlayerService? mdkPlayerService, FfmpegCompositeService? ffmpegCompositeService}) {
     // Allow injecting mocks for testing, otherwise use Service Locator (di)
    _mdkPlayerService = mdkPlayerService ?? di<MdkPlayerService>();
    _ffmpegCompositeService = ffmpegCompositeService ?? di<FfmpegCompositeService>();
    logger.logInfo('CompositeVideoService initialized. MDK Service: ${_mdkPlayerService != null}, FFmpeg Service: ${_ffmpegCompositeService != null}', _logTag);
  }

  /// Creates a composite video frame representing the state at currentTimeMs
  Future<bool> createCompositeVideo({
    required List<ClipModel> clips,
    required int currentTimeMs,
    Size? containerSize, // Represents the desired output canvas size
  }) async {
    // Prevent concurrent operations
    if (_isCompositing) {
      logger.logWarning('Composite operation already in progress, skipping request', _logTag);
      return false; 
    }

    _isCompositing = true;
    isProcessingNotifier.value = true;

    try {
        // --- 1. Determine Active Clips ---
        final effectiveTimeMs = currentTimeMs < 1 ? 0 : currentTimeMs; // Handle time 0
        final activeClips = _getActiveClips(clips, effectiveTimeMs);
        logger.logInfo('Found ${activeClips.length} active clips at ${effectiveTimeMs}ms', _logTag); 
        
        if (activeClips.isEmpty) {
            logger.logInfo('No active video clips to display at ${effectiveTimeMs}ms.', _logTag);
            _mdkPlayerService.textureIdNotifier.value = 0; // Signal invalid texture to UI
            await _mdkPlayerService.pause(); // Ensure player is stopped
            return true;
        }
        
        // Debug log all active clips
        for (int i = 0; i < activeClips.length; i++) {
          final clip = activeClips[i];
          logger.logInfo('Active clip[$i]: ID=${clip.databaseId}, Path=${clip.sourcePath}, Start=${clip.startTimeOnTrackMs}ms, End=${clip.endTimeOnTrackMs}ms', _logTag);
        }

        if (activeClips.length == 1) {
            // Single clip mode - use MDK directly for better performance
            final clip = activeClips.first;
            logger.logInfo('Processing single active clip: ID ${clip.databaseId}, Path: ${clip.sourcePath}', _logTag);

            // Verify file exists
            final file = File(clip.sourcePath);
            if (!await file.exists()) {
              logger.logError('Source file does not exist: ${clip.sourcePath}', _logTag);
              return false;
            }

            // Calculate source position
            int positionInClipMs = effectiveTimeMs - clip.startTimeOnTrackMs;
            positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
            int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
            sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);
            
            logger.logInfo('Setting media: ${clip.sourcePath} and seeking to ${sourcePosMs}ms', _logTag);
            
            try {
              // Load and prepare media
              final loadPrepareSuccess = await _mdkPlayerService.setAndPrepareMedia(clip.sourcePath);
              if (!loadPrepareSuccess) {
                  logger.logError('MDK failed to load and prepare media: ${clip.sourcePath}', _logTag);
                  return false;
              }
              
              final seekSuccess = await _mdkPlayerService.seek(sourcePosMs, pauseAfterSeek: true);
              if (!seekSuccess) {
                  logger.logError('MDK failed to seek to ${sourcePosMs}ms.', _logTag);
                  return false;
              }
              
              final textureUpdated = await _mdkPlayerService.updateTextureAfterSeek();
              if (textureUpdated) {
                  final textureId = _mdkPlayerService.textureIdNotifier.value;
                  logger.logInfo('Successfully loaded single clip with texture ID $textureId.', _logTag);
                  return true;
              } else {
                  logger.logError('MDK failed to update texture after seek.', _logTag);
                  return false;
              }
            } catch (e, stack) {
              logger.logError('Exception in single clip processing: $e\n$stack', _logTag);
              return false;
            }
        } else {
            // Multiple clips mode - use FFmpeg to composite them
            logger.logInfo('Processing ${activeClips.length} active clips for composite view', _logTag);
            
            try {
              // Prepare FFmpeg inputs
              final canvasWidth = (containerSize?.width ?? 1920).round();
              final canvasHeight = (containerSize?.height ?? 1080).round();
              final List<Map<String, dynamic>> videoInputs = [];
              
              // Calculate source positions for each clip
              for (final clip in activeClips) {
                  // Calculate source position
                  int positionInClipMs = effectiveTimeMs - clip.startTimeOnTrackMs;
                  positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
                  int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
                  sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);
                  
                  // Verify file exists
                  final file = File(clip.sourcePath);
                  if (!await file.exists()) {
                    logger.logError('Source file does not exist: ${clip.sourcePath}', _logTag);
                    continue; // Skip this clip but try to process others
                  }
                  
                  videoInputs.add({
                      'path': clip.sourcePath,
                      'source_pos_ms': sourcePosMs,
                  });
              }
              
              // Exit if no valid video inputs
              if (videoInputs.isEmpty) {
                logger.logError('No valid video files to composite', _logTag);
                return false;
              }
              
              // Take only the first two clips if there are more than 2
              if (videoInputs.length > 2) {
                  logger.logInfo('Limiting composite view to first 2 clips out of ${videoInputs.length}', _logTag);
                  videoInputs.removeRange(2, videoInputs.length);
              }
              
              // Setup dummy layout inputs to match the new FFmpeg service implementation
              final List<Map<String, dynamic>> layoutInputs = [];
              for (int i = 0; i < videoInputs.length; i++) {
                  layoutInputs.add({
                      'x': 0,
                      'y': 0,
                      'width': canvasWidth,
                      'height': canvasHeight,
                      'flip_h': false,
                      'flip_v': false,
                  });
              }
              
              // Generate composite frame
              final tempDir = await getTemporaryDirectory();
              final uuid = const Uuid().v4();
              final newCompositePath = p.join(tempDir.path, 'composite_$uuid.mp4');
              
              // Delete previous composite file if exists
              await _deleteTempFile(_currentCompositeFilePath);
              _currentCompositeFilePath = newCompositePath;
              
              logger.logInfo('Generating side-by-side layout using hstack filter: ${videoInputs.length} videos, canvas: ${canvasWidth}x${canvasHeight}', _logTag);
              
              final ffmpegSuccess = await _ffmpegCompositeService.generateCompositeFrame(
                  outputFile: newCompositePath,
                  canvasWidth: canvasWidth,
                  canvasHeight: canvasHeight,
                  videoInputs: videoInputs,
                  layoutInputs: layoutInputs,
              );
              
              if (!ffmpegSuccess) {
                  logger.logError('FFmpeg failed to generate composite frame', _logTag);
                  return false;
              }
              
              // Composite file generated successfully by FFmpeg.
              // The path is stored in _currentCompositeFilePath.
              // CompositePreviewPanel will handle loading this path into its own player.
              // Clear the MDK texture ID as we are now in multi-clip (FFmpeg) mode.
              _mdkPlayerService.textureIdNotifier.value = 0;
              logger.logInfo('Successfully generated composite frame for ${activeClips.length} clips at: $_currentCompositeFilePath', _logTag);
              return true; // Indicate success, path is available via getCompositeFilePath()
            } catch (e, stack) {
              logger.logError('Exception in multiple clip processing: $e\n$stack', _logTag);
              return false;
            }
        }

    } catch (e, stackTrace) {
      logger.logError('Error processing video frame: $e\n$stackTrace', _logTag);
      // Clean up resources
      await _deleteTempFile(_currentCompositeFilePath);
      _currentCompositeFilePath = null;
      await _mdkPlayerService.clearMedia();
      return false;
    } finally {
      // --- Release Lock and Update Notifier ---
      isProcessingNotifier.value = false;
      _isCompositing = false;
    }
  }

  /// Filters clips to find those active at the given time.
  List<ClipModel> _getActiveClips(List<ClipModel> clips, int effectiveTimeMs) {
      return clips.where((clip) {
        // Basic checks
        if (clip.type != ClipType.video || clip.databaseId == null) return false;

        // Time check
        final clipStart = clip.startTimeOnTrackMs;
        final duration = clip.durationInSourceMs ??
            (clip.endTimeInSourceMs > clip.startTimeInSourceMs
                ? clip.endTimeInSourceMs - clip.startTimeInSourceMs
                : 0);
        final clipEnd = clipStart + duration;
        if (!(effectiveTimeMs >= clipStart && effectiveTimeMs < clipEnd)) return false;

        // File existence check (with error handling)
        try {
          final fileExists = File(clip.sourcePath).existsSync();
          if (!fileExists) {
            logger.logWarning('Source file not found during clip filtering: ${clip.sourcePath}', _logTag);
            return false;
          }
          return true; // All checks passed
        } catch (e) {
          logger.logError('Error checking file existence for ${clip.sourcePath}: $e', _logTag);
          return false;
        }
      }).toList();
  }

  /// Generates a composite side-by-side video without trying to load it into MDK
  /// Returns the path to the generated file if successful
  Future<String?> generateCompositeVideoFile({
    required List<ClipModel> clips,
    required int currentTimeMs,
    Size? containerSize,
  }) async {
    if (_isCompositing) {
      logger.logWarning('Composite operation already in progress, skipping request', _logTag);
      return null; 
    }

    _isCompositing = true;
    isProcessingNotifier.value = true;

    try {
      // --- Determine Active Clips ---
      final effectiveTimeMs = currentTimeMs < 1 ? 0 : currentTimeMs;
      final activeClips = _getActiveClips(clips, effectiveTimeMs);
      logger.logInfo('Found ${activeClips.length} active clips at ${effectiveTimeMs}ms', _logTag); 
      
      if (activeClips.isEmpty || activeClips.length < 2) {
        logger.logInfo('Need at least 2 active clips for side-by-side view', _logTag);
        return null;
      }
      
      // --- Prepare FFmpeg inputs ---
      final canvasWidth = (containerSize?.width ?? 1920).round();
      final canvasHeight = (containerSize?.height ?? 1080).round();
      final List<Map<String, dynamic>> videoInputs = [];
      
      // Calculate source positions for each clip
      for (final clip in activeClips) {
        int positionInClipMs = effectiveTimeMs - clip.startTimeOnTrackMs;
        positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
        int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
        sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs);
        
        final file = File(clip.sourcePath);
        if (!await file.exists()) {
          logger.logError('Source file does not exist: ${clip.sourcePath}', _logTag);
          continue;
        }
        
        videoInputs.add({
          'path': clip.sourcePath,
          'source_pos_ms': sourcePosMs,
        });
      }
      
      if (videoInputs.length < 2) {
        logger.logError('Not enough valid video files to composite', _logTag);
        return null;
      }
      
      // Take only the first two clips
      if (videoInputs.length > 2) {
        logger.logInfo('Limiting composite view to first 2 clips out of ${videoInputs.length}', _logTag);
        videoInputs.removeRange(2, videoInputs.length);
      }
      
      // Setup dummy layout inputs
      final List<Map<String, dynamic>> layoutInputs = [];
      for (int i = 0; i < videoInputs.length; i++) {
        layoutInputs.add({
          'x': 0,
          'y': 0,
          'width': canvasWidth,
          'height': canvasHeight,
          'flip_h': false,
          'flip_v': false,
        });
      }
      
      // Generate composite frame
      final tempDir = await getTemporaryDirectory();
      final uuid = const Uuid().v4();
      final newCompositePath = p.join(tempDir.path, 'composite_$uuid.mp4');
      
      // Delete previous composite file if exists
      await _deleteTempFile(_currentCompositeFilePath);
      _currentCompositeFilePath = newCompositePath;
      
      logger.logInfo('Generating side-by-side layout using hstack filter: ${videoInputs.length} videos, canvas: ${canvasWidth}x${canvasHeight}', _logTag);
      
      final ffmpegSuccess = await _ffmpegCompositeService.generateCompositeFrame(
        outputFile: newCompositePath,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        videoInputs: videoInputs,
        layoutInputs: layoutInputs,
      );
      
      if (!ffmpegSuccess) {
        logger.logError('FFmpeg failed to generate composite frame', _logTag);
        return null;
      }
      
      logger.logInfo('Successfully generated composite frame at: $_currentCompositeFilePath', _logTag);
      return _currentCompositeFilePath;
    } catch (e, stackTrace) {
      logger.logError('Error generating composite video file: $e\n$stackTrace', _logTag);
      return null;
    } finally {
      isProcessingNotifier.value = false;
      _isCompositing = false;
    }
  }

  /// Plays the given video using the standard VideoPlayerController instead of MDK
  /// Useful for the composite view when MDK player is having issues
  Future<void> syncPlaybackState(bool isPlaying, VideoPlayerController? controller) async {
    if (controller == null || !controller.value.isInitialized) return;
    
    try {
      if (isPlaying && !controller.value.isPlaying) {
        logger.logInfo('Playing direct composite video controller', _logTag);
        await controller.play();
      } else if (!isPlaying && controller.value.isPlaying) {
        logger.logInfo('Pausing direct composite video controller', _logTag);
        await controller.pause();
      }
    } catch (e, stack) {
      logger.logError('Failed to sync playback state: $e', _logTag, stack);
    }
  }

  // --- Player Control Delegation ---

  Future<void> pause() async {
    await _mdkPlayerService.pause();
  }

  Future<void> play() async {
     // Note: Playing the composite frame doesn't make sense as it's static.
     // This method might need reconsideration based on how playback is intended.
     // For now, it just delegates, but likely shouldn't be used for the composite frame.
     logger.logWarning('Attempted to play a static composite frame. Pausing instead.', _logTag);
    // await _mdkPlayerService.play();
     await _mdkPlayerService.pause(); // Keep it paused
  }

  Future<void> seek(int timeMs) async {
     // Seeking also doesn't make much sense for a single frame.
     // We might want to trigger a new composite frame generation instead.
     // For now, just seek to 0 within the 1-frame video.
     logger.logInfo('Seeking in composite frame - effectively seeking to 0.', _logTag);
     await _mdkPlayerService.seek(0, pauseAfterSeek: true);
     // Consider if this should trigger createCompositeVideo(currentTimeMs: timeMs)?
  }

  // --- Cleanup ---

  Future<void> dispose() async {
    logger.logInfo('Disposing CompositeVideoService.', _logTag);
    // No need to dispose injected services here if they are managed elsewhere (like ServiceLocator)
    // _mdkPlayerService.dispose(); // Assuming locator handles disposal
    isProcessingNotifier.dispose();

    // Clean up the last temporary file on dispose
    await _deleteTempFile(_currentCompositeFilePath);
    _currentCompositeFilePath = null;
  }

  // Helper to delete temp file safely
  Future<void> _deleteTempFile(String? filePath) async {
    if (filePath == null) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        logger.logInfo('Deleted temporary composite file: $filePath', _logTag);
      }
    } catch (e) {
      logger.logError('Error deleting temp composite file $filePath: $e', _logTag);
    }
  }
}

