import 'dart:async';
import 'dart:io';
import 'package:fvp/mdk.dart' as mdk;
import 'package:path_provider/path_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Service that handles the creation of composite videos from multiple source clips
class CompositeVideoService {
  final String _logTag = 'CompositeVideoService';

  // The current player instance
  mdk.Player? _player;
  mdk.Player? get player => _player;

  // Texture ID for rendering
  final ValueNotifier<int> textureIdNotifier = ValueNotifier<int>(-1);
  int get textureId => textureIdNotifier.value;

  // Path to the current composite video frame file
  String? _currentCompositeFilePath;

  // Notifier for player state
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isProcessingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isPlayerReadyNotifier = ValueNotifier(false);

  // Lock to prevent concurrent FFmpeg operations
  final _ffmpegLock = Object();
  bool _isFFmpegProcessing = false;
  
  // Error handling and recovery
  bool _isRecoveringFromError = false;
  int _consecutiveErrorCount = 0;
  final int _maxConsecutiveErrors = 3;
  DateTime? _lastErrorTime;
  
  CompositeVideoService() {
    _initPlayer();
  }

  void _initPlayer() {
    try {
      logger.logInfo('Initializing MDK player...', _logTag);
      
      // Dispose previous player if it exists
      if (_player != null) {
        logger.logInfo('Disposing previous player instance', _logTag);
        try {
          _player?.dispose();
        } catch (e) {
          logger.logError('Error disposing previous player: $e', _logTag);
        }
        _player = null;
      }
      
      // Reset texture ID if we're reinitializing
      textureIdNotifier.value = -1;
      
      try {
        _player = mdk.Player();
        logger.logInfo('Player instance created', _logTag);
      } catch (e, stack) {
        logger.logError('Failed to create MDK player: $e\n$stack', _logTag);
        _handlePlayerCreationError();
        return;
      }

      // Use callback for state changes
      _player?.onStateChanged((oldState, newState) {
        if (_player == null) return;
        isPlayingNotifier.value = newState == mdk.PlaybackState.playing;
        logger.logInfo('Player state changed: $oldState -> $newState', _logTag);
      });

      // Subscribe to media status events
      _player?.onMediaStatus((oldStatus, newStatus) {
        logger.logInfo('Media status changed: $oldStatus -> $newStatus', _logTag);
        return true;
      });

      // Monitor texture ID changes through events
      _player?.onEvent((event) {
        logger.logInfo('Player event received: ${event.category} - ${event.detail}', _logTag);
        
        if (event.category == "video.renderer") {
          final newId = _player?.textureId ?? -1;
          if (newId is int && newId > 0 && newId != textureIdNotifier.value) {
            textureIdNotifier.value = newId;
            logger.logInfo('Texture ID updated: $newId', _logTag);
          }
        }
      });

      logger.logInfo('MDK player initialization completed', _logTag);
    } catch (e, stackTrace) {
      logger.logError('Error initializing player: $e\n$stackTrace', _logTag);
      _handlePlayerCreationError();
    }
  }
  
  void _handlePlayerCreationError() {
    // Track consecutive errors
    final now = DateTime.now();
    if (_lastErrorTime != null) {
      final timeSinceLastError = now.difference(_lastErrorTime!);
      if (timeSinceLastError.inSeconds < 10) {
        _consecutiveErrorCount++;
      } else {
        _consecutiveErrorCount = 1;
      }
    } else {
      _consecutiveErrorCount = 1;
    }
    _lastErrorTime = now;
    
    // If too many consecutive errors, back off
    if (_consecutiveErrorCount >= _maxConsecutiveErrors) {
      logger.logError('Too many consecutive player initialization errors, backing off', _logTag);
      _isRecoveringFromError = true;
      Future.delayed(const Duration(seconds: 2), () {
        _isRecoveringFromError = false;
        _consecutiveErrorCount = 0;
      });
    }
  }

  /// Creates a composite video frame representing the state at currentTimeMs
  Future<bool> createCompositeVideo({
    required List<ClipModel> clips,
    required Map<int, Rect> positions,
    required Map<int, Flip> flips,
    required int currentTimeMs,
    Size? containerSize, // Represents the desired output canvas size
  }) async {
    // Skip if we're recovering from errors
    if (_isRecoveringFromError) {
      logger.logInfo('Skipping composite video creation while recovering from errors', _logTag);
      return false;
    }
    
    // Always process time 0 specially to ensure we don't miss clips at the beginning
    final effectiveTimeMs = currentTimeMs < 1 ? 0 : currentTimeMs;
    
    // Use a lock to prevent multiple FFmpeg processes from running simultaneously
    bool result = false;
    await _synchronized(_ffmpegLock, () async {
      if (_isFFmpegProcessing) {
        logger.logInfo('FFmpeg is already processing, skipping duplicate request', _logTag);
        result = false;
        return;
      }
      
      _isFFmpegProcessing = true;
      isProcessingNotifier.value = true;
      
      try {
        // Log all available clips for debugging
        logger.logInfo('All available clips: ${clips.map((c) => '${c.databaseId}:${c.type}').join(', ')}', _logTag);
        logger.logInfo('Position keys: ${positions.keys.join(', ')}', _logTag);
        logger.logInfo('Flip keys: ${flips.keys.join(', ')}', _logTag);
        
        // Filter only video clips that should be visible at currentTimeMs
        final activeClips =
            clips.where((clip) {
              final clipStart = clip.startTimeOnTrackMs;
              // Ensure duration calculation is safe
              final duration =
                  clip.durationInSourceMs ??
                  (clip.endTimeInSourceMs > clip.startTimeInSourceMs
                      ? clip.endTimeInSourceMs - clip.startTimeInSourceMs
                      : 0);
              final clipEnd = clipStart + duration;
              
              // Check file existence separately for better debugging
              bool fileExists = false;
              try {
                fileExists = File(clip.sourcePath).existsSync();
                if (!fileExists) {
                  logger.logWarning('Source file not found: ${clip.sourcePath}', _logTag);
                }
              } catch (e) {
                logger.logError('Error checking file existence: ${clip.sourcePath} - $e', _logTag);
              }
              
              // Debug log to understand why clips might not be detected at time 0
              logger.logInfo(
                'Evaluating clip ${clip.databaseId}: time=${effectiveTimeMs}ms, start=${clipStart}ms, end=${clipEnd}ms, isVideo=${clip.type == ClipType.video}, ' +
                'hasPositions=${clip.databaseId != null && positions.containsKey(clip.databaseId)}, ' +
                'hasFlips=${clip.databaseId != null && flips.containsKey(clip.databaseId)}, ' +
                'fileExists=$fileExists, sourcePath=${clip.sourcePath}',
                _logTag,
              );
              
              // Use separate variables for debugging
              bool isVideo = clip.type == ClipType.video;
              bool hasId = clip.databaseId != null;
              bool inTimeRange = effectiveTimeMs >= clipStart && effectiveTimeMs < clipEnd;
              bool hasPosition = hasId && positions.containsKey(clip.databaseId!);
              bool hasFlip = hasId && flips.containsKey(clip.databaseId!);
              
              logger.logInfo(
                'Decision for clip ${clip.databaseId}: isVideo=$isVideo, hasId=$hasId, inTimeRange=$inTimeRange, hasPosition=$hasPosition, hasFlip=$hasFlip, fileExists=$fileExists',
                _logTag,
              );
              
              // Return the original check
              return isVideo && hasId && inTimeRange && hasPosition && hasFlip && fileExists;
            }).toList();

        logger.logInfo(
          'Found ${activeClips.length} active clips at ${effectiveTimeMs}ms',
          _logTag,
        );
        
        if (activeClips.isEmpty) {
          logger.logInfo(
            'No active video clips to display at ${effectiveTimeMs}ms',
            _logTag,
          );
          if (_player != null) {
            try {
              _player!.setMedia('', mdk.MediaType.unknown); // Clear media
              _player!.state = mdk.PlaybackState.paused; // <<< MUST BE .paused
            } catch (e) {
              logger.logError('Error clearing media: $e', _logTag);
              _initPlayer(); // Reinitialize on error
            }
          } else {
            logger.logWarning('Player instance was null when trying to clear media for empty clips.', _logTag);
          }
          textureIdNotifier.value = -1;
          isProcessingNotifier.value = false;
          _isFFmpegProcessing = false;
          result = true;
          return;
        }

        logger.logInfo(
          'Starting composite video frame creation for ${activeClips.length} clips at ${effectiveTimeMs}ms',
          _logTag,
        );

        try {
          // Determine canvas size
          final double canvasWidth = containerSize?.width ?? 1920;
          final double canvasHeight = containerSize?.height ?? 1080;

          // Prepare FFmpeg inputs
          final List<String> videoFiles = [];
          final List<Map<String, dynamic>> ffmpegPositions = [];

          for (final clip in activeClips) {
            // Since activeClips already filters for databaseId != null, we can use `!` safely
            final clipId = clip.databaseId!;
            final rect = positions[clipId]!;
            final flip = flips[clipId]!;

            // Calculate the precise time within the source file to seek to
            int positionInClipMs = effectiveTimeMs - clip.startTimeOnTrackMs;
            // Ensure we never get a negative source position
            positionInClipMs = positionInClipMs < 0 ? 0 : positionInClipMs;
            int sourcePosMs = clip.startTimeInSourceMs + positionInClipMs;
            
            // Ensure we're always within source bounds and never negative
            sourcePosMs = sourcePosMs.clamp(
              clip.startTimeInSourceMs,
              clip.endTimeInSourceMs,
            ); 
            
            logger.logInfo(
              'Clip ${clip.databaseId} timing: effectiveTimeMs=${effectiveTimeMs}ms, ' +
              'startTimeOnTrack=${clip.startTimeOnTrackMs}ms, positionInClip=${positionInClipMs}ms, ' +
              'startTimeInSource=${clip.startTimeInSourceMs}ms, endTimeInSource=${clip.endTimeInSourceMs}ms, ' +
              'sourcePosMs=${sourcePosMs}ms',
              _logTag,
            );

            // Ensure rect dimensions are valid and contain a minimum size
            final width = rect.width.clamp(1.0, canvasWidth).round();
            final height = rect.height.clamp(1.0, canvasHeight).round();
            
            // Ensure position is within canvas bounds
            final x = rect.left.round();
            final y = rect.top.round();

            if (!File(clip.sourcePath).existsSync()) {
              logger.logWarning(
                'Source file not found, skipping clip: ${clip.sourcePath}',
                _logTag,
              );
              continue; // Skip this clip if file doesn't exist
            }

            videoFiles.add(clip.sourcePath);
            ffmpegPositions.add({
              'x': x,
              'y': y,
              'width': width,
              'height': height,
              'flip_h': flip == Flip.horizontal,
              'flip_v': flip == Flip.vertical,
              'source_pos_ms': sourcePosMs,
            });
          }

          if (videoFiles.isEmpty) {
            logger.logInfo(
              'No valid video files found after filtering for FFmpeg.',
              _logTag,
            );
            if (_player != null) {
              try {
                _player?.setMedia('', mdk.MediaType.unknown); // Clear media
                _player?.state = mdk.PlaybackState.paused; // <<< MUST BE .paused
              } catch (e) {
                logger.logError('Error clearing media: $e', _logTag);
              }
            }
            textureIdNotifier.value = -1;
            isProcessingNotifier.value = false;
            _isFFmpegProcessing = false;
            result = true;
            return;
          }

          // Generate unique temporary file path
          final tempDir = await getTemporaryDirectory();
          final newCompositePath = p.join(
            tempDir.path,
            'composite_frame_${const Uuid().v4()}.mp4',
          );
          logger.logInfo(
            'Generated temporary path: $newCompositePath',
            _logTag,
          );

          // Clean up previous temp file if exists
          await _deleteTempFile(_currentCompositeFilePath);
          _currentCompositeFilePath = newCompositePath;

          // Generate the composite frame using FFmpeg
          logger.logInfo(
            'Generating composite frame at: $_currentCompositeFilePath',
            _logTag,
          );
          final ffmpegSuccess = await _generateCompositeFrameWithFFmpeg(
            videoFiles,
            ffmpegPositions,
            _currentCompositeFilePath!,
            canvasWidth.round(),
            canvasHeight.round(),
          );

          // Check existence after FFmpeg attempt
          final fileExists = await File(_currentCompositeFilePath!).exists();
          logger.logInfo(
            'Temporary file exists after FFmpeg call: $fileExists',
            _logTag,
          );

          if (!ffmpegSuccess || !fileExists) {
            logger.logError(
              'FFmpeg frame generation failed or file not created. Success: $ffmpegSuccess, Exists: $fileExists',
              _logTag,
            );
            await _deleteTempFile(_currentCompositeFilePath); // Clean up if failed
            _currentCompositeFilePath = null;
            isProcessingNotifier.value = false;
            _isFFmpegProcessing = false;
            result = false;
            return;
          }

          // Safe player reinitialization
          bool playerInitSuccess = await _safePlayerReinit(_currentCompositeFilePath!);
          
          if (!playerInitSuccess) {
            logger.logError('Failed to reinitialize player with new media', _logTag);
            isProcessingNotifier.value = false;
            _isFFmpegProcessing = false;
            result = false;
            return;
          }
          
          isProcessingNotifier.value = false;
          _isFFmpegProcessing = false;
          result = true;
          return;
        } catch (e, stackTrace) {
          logger.logError(
            'Error creating composite video frame: $e\n$stackTrace',
            _logTag,
          );
          isProcessingNotifier.value = false;
          _isFFmpegProcessing = false;
          // Clean up potentially partially created file
          await _deleteTempFile(_currentCompositeFilePath);
          _currentCompositeFilePath = null;
          result = false;
          return;
        }
      } finally {
        _isFFmpegProcessing = false;
        isProcessingNotifier.value = false;
      }
    });
    
    // Return the result from the synchronized block
    return result;
  }
  
  /// Safely reinitialize the player with the new media
  Future<bool> _safePlayerReinit(String mediaPath) async {
    try {
      // Re-initialize player to load the new single-frame video
      _initPlayer();
      
      logger.logInfo('Setting media to: $mediaPath', _logTag);
      if (_player == null) {
        logger.logError('Player is null after reinitialization', _logTag);
        return false;
      }
      
      try {
        _player!.setMedia(mediaPath, mdk.MediaType.video);
        _player!.prepare();
      } catch (e, stack) {
        logger.logError('Error setting media: $e\n$stack', _logTag);
        return false;
      }

      // Wait for player to be ready
      final initialized = _player?.waitFor(mdk.PlaybackState.paused, timeout: 1000) ?? false;
      logger.logInfo('Player initialized after FFmpeg: $initialized', _logTag);

      if (!initialized) {
        logger.logError('Player failed to initialize within timeout', _logTag);
        return false;
      }

      // Get container size
      final videoWidth = _player?.mediaInfo.video?.isNotEmpty == true 
          ? _player?.mediaInfo.video?.first.codec.width ?? 0 
          : 0;
      final videoHeight = _player?.mediaInfo.video?.isNotEmpty == true 
          ? _player?.mediaInfo.video?.first.codec.height ?? 0 
          : 0;
      
      if (videoWidth <= 0 || videoHeight <= 0) {
        logger.logError('Invalid video dimensions: ${videoWidth}x${videoHeight}', _logTag);
        return false;
      }
      
      // Set surface size to match video
      try {
        _player!.setVideoSurfaceSize(videoWidth, videoHeight);
        
        // Ensure the single frame is rendered
        _player!.seek(position: 0); // Seek to beginning of the short clip
        
        // Small delay might help with texture rendering
        await Future.delayed(const Duration(milliseconds: 50));
        
        // Update texture
        final textureId = await _player!.updateTexture(
          width: videoWidth,
          height: videoHeight,
        );
        
        logger.logInfo('Updated texture with ID: $textureId', _logTag);
        
        if (textureId > 0) {
          textureIdNotifier.value = textureId;
          _player!.state = mdk.PlaybackState.paused; // Keep paused to show the frame
          return true;
        } else {
          logger.logError('Failed to update texture, got invalid ID: $textureId', _logTag);
          return false;
        }
      } catch (e, stack) {
        logger.logError('Error during final player setup: $e\n$stack', _logTag);
        return false;
      }
    } catch (e, stack) {
      logger.logError('Error in _safePlayerReinit: $e\n$stack', _logTag);
      return false;
    }
  }

  /// Simple synchronization mechanism to prevent concurrent operations
  Future<void> _synchronized(Object lock, Future<void> Function() callback) async {
    // Skip if already processing
    if (_isFFmpegProcessing) {
      return;
    }
    
    try {
      await callback();
    } finally {
      // Ensure lock is released
    }
  }

  /// Uses FFmpeg to generate a single composite video frame.
  Future<bool> _generateCompositeFrameWithFFmpeg(
    List<String> videoFiles,
    List<Map<String, dynamic>> positions,
    String outputFile,
    int canvasWidth,
    int canvasHeight,
  ) async {
    if (videoFiles.isEmpty) return false;

    try {
      // First validate that all source files exist
      for (final sourcePath in videoFiles) {
        final exists = await File(sourcePath).exists();
        if (!exists) {
          logger.logError('Source file does not exist: $sourcePath', _logTag);
          return false;
        }
      }
      
      // Ensure the output directory exists
      final outputDir = File(outputFile).parent;
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
      
      // If output file exists, delete it first to avoid issues
      final outputFileObj = File(outputFile);
      if (await outputFileObj.exists()) {
        await outputFileObj.delete();
      }

      // Build FFmpeg filter complex command
      String filterComplex = '';
      final List<String> inputs = [];

      // Input processing: Seek to the specific frame time for each input
      for (int i = 0; i < videoFiles.length; i++) {
        final sourcePosMs = positions[i]['source_pos_ms'];
        final sourcePath = videoFiles[i];

        // Add seek argument *before* the input file for speed
        inputs.add('-ss');
        inputs.add('${sourcePosMs / 1000.0}'); // FFmpeg uses seconds

        // Add hardware acceleration option *before* the input file
        inputs.add('-hwaccel');
        inputs.add('auto');

        inputs.add('-i');
        inputs.add(sourcePath);

        // Start building the filter chain for this input
        filterComplex += '[$i:v]';

        // Apply flipping if needed
        List<String> flipFilters = [];
        if (positions[i]['flip_h'] == true) flipFilters.add('hflip');
        if (positions[i]['flip_v'] == true) flipFilters.add('vflip');
        if (flipFilters.isNotEmpty) {
          filterComplex += flipFilters.join(',') + ',';
        }

        // Add scaling
        final targetWidth = positions[i]['width'];
        final targetHeight = positions[i]['height'];
        filterComplex += 'scale=$targetWidth:$targetHeight[v$i];';
      }

      // Create the base canvas
      filterComplex +=
          'color=c=black:s=${canvasWidth}x$canvasHeight:d=1[base];'; // Create a 1-frame duration base

      // Overlay videos onto the base canvas
      String lastOverlayOutput = '[base]';
      for (int i = 0; i < videoFiles.length; i++) {
        final x = positions[i]['x'];
        final y = positions[i]['y'];
        final overlayOutput =
            (i == videoFiles.length - 1)
                ? '[out]'
                : '[ovr$i]'; // Final output is [out]

        filterComplex +=
            '$lastOverlayOutput[v$i]overlay=x=$x:y=$y:shortest=1$overlayOutput;'; // Use shortest=1 for single frame
        if (i < videoFiles.length - 1) {
          lastOverlayOutput = overlayOutput;
        }
      }

      // Set up the FFmpeg command arguments
      final ffmpegArgs = [
        ...inputs, // Seeked inputs first
        '-filter_complex',
        filterComplex.trim().endsWith(';')
            ? filterComplex.trim().substring(0, filterComplex.length - 1)
            : filterComplex,
        '-map', '[out]', // Map the final overlay output
        '-frames:v', '1', // Output exactly one video frame
        '-c:v', 'libx264', // Use H.264 encoding
        '-preset', 'ultrafast', // Prioritize speed
        '-tune', 'fastdecode', // Optimize for fast decoding
        '-pix_fmt', 'yuv420p', // Standard pixel format
        '-flags', '+low_delay', // Optimize for low delay
        '-threads', '0', // Use all available CPU threads
        // '-hwaccel', 'auto', // Enable hardware acceleration - MOVED TO INPUTS
        '-an', // Disable audio stream
        '-sn', // Disable subtitle stream
        '-y', // Overwrite output file if it exists
        outputFile,
      ];

      final commandString = 'ffmpeg ${ffmpegArgs.join(" ")}';
      logger.logInfo('Running FFmpeg command: $commandString', _logTag);

      // Execute FFmpeg
      final result = await runExecutableArguments(
        'ffmpeg',
        ffmpegArgs,
        verbose: true,
      ); // Add verbose for debugging

      // Log FFmpeg result regardless of exit code for debugging crashes
      logger.logInfo(
        'FFmpeg Result (Exit Code: ${result.exitCode}):\nSTDOUT: ${result.stdout}\nSTDERR: ${result.stderr}',
        _logTag,
      );

      if (result.exitCode != 0) {
        logger.logError(
          'FFmpeg failed with exit code ${result.exitCode}.',
          _logTag,
        );
        return false;
      }

      // Double check that the file was actually created
      final fileCreated = await File(outputFile).exists();
      if (!fileCreated) {
        logger.logError(
          'FFmpeg process completed successfully but output file was not created: $outputFile',
          _logTag,
        );
        return false;
      }
      
      // Check the file size to make sure it's valid
      final fileSize = await File(outputFile).length();
      if (fileSize < 100) { // Less than 100 bytes is probably not a valid video
        logger.logError(
          'FFmpeg output file too small (${fileSize} bytes), might be corrupt: $outputFile',
          _logTag,
        );
        return false;
      }

      logger.logInfo('FFmpeg frame generation successful.', _logTag);
      return true;
    } catch (e, stackTrace) {
      logger.logError('Error in FFmpeg processing: $e\n$stackTrace', _logTag);
      return false;
    }
  }

  Future<void> pause() async {
    _player?.state = mdk.PlaybackState.paused;
  }

  Future<void> play() async {
    _player?.state = mdk.PlaybackState.playing;
  }

  Future<void> seek(int timeMs) async {
    _player?.seek(position: timeMs);
  }

  Future<void> dispose() async {
    _player?.dispose();
    _player = null;

    // Clean up temporary file
    await _deleteTempFile(_currentCompositeFilePath);
    _currentCompositeFilePath = null; // Clear the path
  }

  // Helper to delete temp file safely
  Future<void> _deleteTempFile(String? filePath) async {
    if (filePath != null) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          logger.logInfo(
            'Deleted temporary composite file: $filePath',
            _logTag,
          );
        }
      } catch (e) {
        logger.logError(
          'Error cleaning up composite file $filePath: $e',
          _logTag,
        );
      }
    }
  }
}
