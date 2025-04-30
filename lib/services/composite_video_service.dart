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
      // logger.logInfo('Compositing is already in progress, skipping request.', _logTag); // Removed log
      return false; // Removed duplicate return
    }

    _isCompositing = true;
    isProcessingNotifier.value = true;

    bool success = false;
    try {
        // --- 1. Determine Active Clips ---
        final effectiveTimeMs = currentTimeMs < 1 ? 0 : currentTimeMs; // Handle time 0
        // logger.logInfo('Calling _getActiveClips...', _logTag); // Removed log
        final activeClips = _getActiveClips(clips, positions, flips, effectiveTimeMs);
        logger.logInfo('Found ${activeClips.length} active clips at ${effectiveTimeMs}ms', _logTag); // Kept summary log

        // --- 2. Handle No Active Clips ---
        if (activeClips.isEmpty) {
            logger.logInfo('No active video clips to display at ${effectiveTimeMs}ms. Player state remains unchanged.', _logTag); // Updated log
            // await _mdkPlayerService.clearMedia(); // REMOVED potentially unsafe call
            // logger.logInfo('Player clearMedia call completed.', _logTag); // Removed log
            // No compositing needed, operation successful in its own way
            success = true;
            return success; // Early exit
        }

        // --- 3. Prepare Data for FFmpeg ---
        final canvasWidth = (containerSize?.width ?? 1920).round();
        final canvasHeight = (containerSize?.height ?? 1080).round();

        final List<Map<String, dynamic>> videoInputs = [];
        final List<Map<String, dynamic>> layoutInputs = [];

        // logger.logInfo('Preparing FFmpeg data for ${activeClips.length} clips...', _logTag); // Removed log
        for (final clip in activeClips) {
             // logger.logInfo('Processing clip ID: ${clip.databaseId}', _logTag); // Removed log
             // We know these are non-null due to _getActiveClips filter
            final clipId = clip.databaseId!;
            final rect = positions[clipId]!;
            final flip = flips[clipId]!;

            // Calculate source position
             int positionInClipMs = effectiveTimeMs - clip.startTimeOnTrackMs;
             positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs; // Clamp >= 0
             int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
             sourcePosMs = sourcePosMs.clamp(clip.startTimeInSourceMs, clip.endTimeInSourceMs); // Clamp within source bounds

             videoInputs.add({
                'path': clip.sourcePath,
                'source_pos_ms': sourcePosMs,
             });

             layoutInputs.add({
                'x': rect.left.round(),
                'y': rect.top.round(),
                'width': rect.width.clamp(1.0, canvasWidth.toDouble()).round(),
                'height': rect.height.clamp(1.0, canvasHeight.toDouble()).round(),
                'flip_h': flip == Flip.horizontal,
                'flip_v': flip == Flip.vertical,
             });
        }
        // logger.logInfo('Finished preparing FFmpeg data.', _logTag); // Removed log

        // --- 4. Generate Temporary File Path ---
        // logger.logInfo('Getting temporary directory...', _logTag); // Removed log
        final tempDir = await getTemporaryDirectory();
        // logger.logInfo('Got temporary directory: ${tempDir.path}', _logTag); // Removed log
        final newCompositePath = p.join(
          tempDir.path,
          'composite_frame_${const Uuid().v4()}.mp4',
        );
        logger.logInfo('Generated temporary path for composite frame: $newCompositePath', _logTag);

        // Clean up previous temp file *before* generating new one
        await _deleteTempFile(_currentCompositeFilePath);
        _currentCompositeFilePath = newCompositePath;

        // --- 5. Generate Frame using FfmpegCompositeService ---
        logger.logInfo('Calling FfmpegCompositeService to generate frame $newCompositePath...', _logTag); // Simplified log
        final ffmpegSuccess = await _ffmpegCompositeService.generateCompositeFrame(
          videoInputs: videoInputs,
          layoutInputs: layoutInputs,
          outputFile: _currentCompositeFilePath!,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
        );

        // --- 6. Handle FFmpeg Failure ---
        if (!ffmpegSuccess) {
            logger.logError('FFmpeg frame generation failed for $newCompositePath.', _logTag);
            await _deleteTempFile(_currentCompositeFilePath); // Clean up failed file
            _currentCompositeFilePath = null;
            // Consider clearing the player or attempting recovery? For now, just fail.
            // await _mdkPlayerService.clearMedia(); // Ensure this is commented out
            success = false;
            return success; // Early exit on failure
        }

        // --- 7. Load Frame into MdkPlayerService ---
        logger.logInfo('FFmpeg success. Loading frame $newCompositePath into MDK player.', _logTag);
        final playerLoadSuccess = await _mdkPlayerService.setAndPrepareMedia(_currentCompositeFilePath!);

        if (!playerLoadSuccess) {
            logger.logError('Failed to load generated frame into MDK player.', _logTag);
            await _deleteTempFile(_currentCompositeFilePath); // Clean up unused file
             _currentCompositeFilePath = null;
             // Clear player just in case it's in a bad state
             // await _mdkPlayerService.clearMedia(); // Ensure this is commented out
            success = false;
            return success; // Early exit on failure
        }

        // --- 8. Final Player Setup (Surface Size, Texture Update) ---
        // Get dimensions from the player after loading
        final videoInfo = _mdkPlayerService.player?.mediaInfo.video?.firstOrNull?.codec;
        final loadedWidth = videoInfo?.width;
        final loadedHeight = videoInfo?.height;

        if (loadedWidth == null || loadedHeight == null || loadedWidth <= 0 || loadedHeight <= 0) {
            logger.logError('Could not get valid dimensions from loaded media: ${loadedWidth}x$loadedHeight', _logTag);
            await _deleteTempFile(_currentCompositeFilePath);
            _currentCompositeFilePath = null;
            // await _mdkPlayerService.clearMedia(); // Ensure this is commented out
            success = false;
            return success;
        }

        logger.logInfo('Setting player surface size to ${loadedWidth}x$loadedHeight', _logTag);
        _mdkPlayerService.setVideoSurfaceSize(loadedWidth, loadedHeight);

        // Seek to the start (it's a single frame video) and update texture
        await _mdkPlayerService.seek(0, pauseAfterSeek: true); // Ensure paused
        final textureId = await _mdkPlayerService.updateTexture(width: loadedWidth, height: loadedHeight);

        if (textureId > 0) {
            logger.logInfo('Successfully created composite frame, loaded into player, and updated texture ($textureId).', _logTag);
            success = true;
        } else {
             logger.logError('Failed to update texture after loading composite frame.', _logTag);
             await _deleteTempFile(_currentCompositeFilePath);
             _currentCompositeFilePath = null;
             // await _mdkPlayerService.clearMedia(); // Ensure this is commented out
             success = false;
        }

        return success;

    } catch (e, stackTrace) {
      logger.logError('Error creating composite video frame: $e\n$stackTrace', _logTag);
      // General error handling: Clean up temp file
      await _deleteTempFile(_currentCompositeFilePath);
      _currentCompositeFilePath = null;
      // await _mdkPlayerService.clearMedia(); // Ensure this is commented out
      success = false;
      return success;
    } finally {
      // --- Release Lock and Update Notifier ---
      isProcessingNotifier.value = false;
      _isCompositing = false;
       // logger.logInfo('Compositing process finished. Success: $success', _logTag); // Ensure this is removed/commented
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
