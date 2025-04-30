import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart'; // For Size
import 'package:flutter_box_transform/flutter_box_transform.dart'; // For Rect, Flip
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flipedit/services/mdk_player_service.dart';
import 'package:watch_it/watch_it.dart'; // Import watch_it to access 'di'
import 'package:flipedit/services/ffmpeg_composite_service.dart';

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


  CompositeVideoService({MdkPlayerService? mdkPlayerService, FfmpegCompositeService? ffmpegCompositeService}) {
     // Allow injecting mocks for testing, otherwise use Service Locator (di)
    _mdkPlayerService = mdkPlayerService ?? di<MdkPlayerService>();
    _ffmpegCompositeService = ffmpegCompositeService ?? di<FfmpegCompositeService>();
     logger.logInfo('CompositeVideoService initialized.', _logTag);
  }

  /// Creates a composite video frame representing the state at currentTimeMs
  Future<bool> createCompositeVideo({
    required List<ClipModel> clips,
    required Map<int, Rect> positions,
    required Map<int, Flip> flips,
    required int currentTimeMs,
    Size? containerSize, // Represents the desired output canvas size
  }) async {
    // Prevent concurrent operations
    if (_isCompositing) {
      return false; 
    }

    _isCompositing = true;
    isProcessingNotifier.value = true;

    bool success = false;
    try {
        // --- 1. Determine Active Clips ---
        final effectiveTimeMs = currentTimeMs < 1 ? 0 : currentTimeMs; // Handle time 0
        final activeClips = _getActiveClips(clips, positions, flips, effectiveTimeMs);
        logger.logInfo('Found ${activeClips.length} active clips at ${effectiveTimeMs}ms', _logTag); 

        // --- 2. Handle No Active Clips or Select First Clip ---
        if (activeClips.isEmpty) {
            logger.logInfo('No active video clips to display at ${effectiveTimeMs}ms.', _logTag);
            // Don\'t call clearMedia() as it might crash.
            // Instead, set textureId to 0 and pause player.
            // await _mdkPlayerService.clearMedia(); 
            _mdkPlayerService.textureIdNotifier.value = 0; // Signal invalid texture to UI
            await _mdkPlayerService.pause(); // Ensure player is stopped
            success = true;
            // No further processing needed
        } else {
            // --- 3. Process ONLY the First Active Clip ---
            final firstClip = activeClips.first;
            logger.logInfo('Processing only the first active clip: ID ${firstClip.databaseId}, Path: ${firstClip.sourcePath}', _logTag);

            // Calculate source position for the first clip
            int positionInClipMs = effectiveTimeMs - firstClip.startTimeOnTrackMs;
            positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs; // Clamp >= 0
            int sourcePosMs = firstClip.startTimeInSourceMs + positionInClipMs;
            sourcePosMs = sourcePosMs.clamp(firstClip.startTimeInSourceMs, firstClip.endTimeInSourceMs); // Clamp within source bounds

            logger.logInfo('Calculated source position for MDK: ${sourcePosMs}ms', _logTag);

            // --- 4. Load and Prepare Media in MDK Directly ---
            logger.logInfo('Loading and preparing media: ${firstClip.sourcePath}', _logTag);
            // Use setAndPrepareMedia which likely handles loading and initial setup
            final loadPrepareSuccess = await _mdkPlayerService.setAndPrepareMedia(firstClip.sourcePath);

            if (!loadPrepareSuccess) {
                logger.logError('MDK failed to load and prepare media: ${firstClip.sourcePath}', _logTag);
                success = false;
            } else {
                logger.logInfo('Media prepared. Seeking to ${sourcePosMs}ms.', _logTag);
                // Explicitly seek after preparation
                final seekSuccess = await _mdkPlayerService.seek(sourcePosMs, pauseAfterSeek: true); // Assuming pauseAfterSeek is desired

                if (!seekSuccess) {
                    logger.logError('MDK failed to seek to ${sourcePosMs}ms.', _logTag);
                    success = false;
                    // MdkPlayerService should handle cleanup/state internally on seek failure
                } else {
                    logger.logInfo('Seek successful. Preparing frame for display.', _logTag);
                    // Call the new method to update texture without seeking again
                    final textureUpdated = await _mdkPlayerService.updateTextureAfterSeek(); 

                    if (textureUpdated) {
                        final textureId = _mdkPlayerService.textureIdNotifier.value;
                        logger.logInfo('Successfully loaded and prepared frame from source video with texture ID $textureId.', _logTag);
                        success = true;
                    } else {
                        logger.logError('MDK failed to update texture after seek.', _logTag);
                        success = false;
                    }
                }
            }
        }
        
        // --- FFmpeg Steps Removed --- 
        // final canvasWidth = (containerSize?.width ?? 1920).round();
        // final canvasHeight = (containerSize?.height ?? 1080).round();
        // final List<Map<String, dynamic>> videoInputs = [];
        // final List<Map<String, dynamic>> layoutInputs = [];
        // ... (input preparation loop removed) ...
        // final tempDir = await getTemporaryDirectory();
        // final newCompositePath = p.join(...);
        // await _deleteTempFile(_currentCompositeFilePath);
        // _currentCompositeFilePath = newCompositePath;
        // final ffmpegSuccess = await _ffmpegCompositeService.generateCompositeFrame(...);
        // ... (ffmpeg handling removed) ...
        // final playerLoadSuccess = await _mdkPlayerService.setAndPrepareMedia(_currentCompositeFilePath!); 
        // ... (loading composite file removed) ...

        return success;

    } catch (e, stackTrace) {
      logger.logError('Error processing video frame: $e\\n$stackTrace', _logTag);
      // General error handling: Clean up temp file (though none should exist now)
      // await _deleteTempFile(_currentCompositeFilePath); // Removed as it's unused
      // _currentCompositeFilePath = null; // Removed as it's unused
      await _mdkPlayerService.clearMedia(); // Clear player on general error
      success = false;
      return success;
    } finally {
      // --- Release Lock and Update Notifier ---
      isProcessingNotifier.value = false;
      _isCompositing = false;
    }
  }

  /// Filters clips to find those active at the given time.
  List<ClipModel> _getActiveClips(List<ClipModel> clips, Map<int, Rect> positions, Map<int, Flip> flips, int effectiveTimeMs) {
      return clips.where((clip) {
        // Basic checks
        if (clip.type != ClipType.video || clip.databaseId == null) return false;
        if (!positions.containsKey(clip.databaseId) || !flips.containsKey(clip.databaseId)) return false;

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

