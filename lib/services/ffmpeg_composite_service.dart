import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:ffmpeg_cli/ffmpeg_cli.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:crypto/crypto.dart';

/// Service that handles the creation of composite videos from multiple source clips using ffmpeg_cli
class FfmpegCompositeService {
  final String _logTag = 'FfmpegCompositeService';
  
  // Video player controller
  VideoPlayerController? _videoPlayerController;
  VideoPlayerController? get videoPlayerController => _videoPlayerController;

  // Path to the current composite video file
  String? _currentCompositeFilePath;
  String? get currentCompositeFilePath => _currentCompositeFilePath;
  
  // Hash of the last segment configuration to prevent duplicate processing
  String? _lastConfigHash;

  // Segment caching parameters
  final int _segmentDurationMs = 3000; // 3 seconds of video
  final int _fps = 30; // Fixed 30fps for preview
  int? _segmentStartTimeMs;
  int? _segmentEndTimeMs;
  int? _currentPositionMs;

  // Notifiers for service state
  final ValueNotifier<bool> isProcessingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isPlayerReadyNotifier = ValueNotifier(false);
  
  // This isn't used directly for playback anymore - we rely on TimelineNavigationViewModel
  // But kept for API compatibility
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);

  // Error handling
  int _consecutiveErrorCount = 0;
  final int _maxConsecutiveErrors = 3;
  DateTime? _lastErrorTime;
  bool _isRecoveringFromError = false;
  bool _isProcessing = false;
  
  // Directory for output segments
  Directory? _framesDir;
  
  // Audio options
  final bool _muteAudio = false; // Set to true to mute all audio
  
  FfmpegCompositeService() {
    _setupFramesDirectory();
  }
  
  Future<void> _setupFramesDirectory() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _framesDir = Directory(p.join(tempDir.path, 'flipedit_segments'));
      if (!await _framesDir!.exists()) {
        await _framesDir!.create(recursive: true);
      }
      // Clean old segments
      await _cleanOldSegments();
    } catch (e) {
      logger.logError('Error setting up segments directory: $e', _logTag);
    }
  }
  
  Future<void> _cleanOldSegments() async {
    if (_framesDir == null) return;
    
    try {
      final files = await _framesDir!.list().toList();
      if (files.length > 10) {
        final sortedFiles = files.whereType<File>().toList()
          ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        
        // Keep the 5 most recent files
        for (var i = 0; i < sortedFiles.length - 5; i++) {
          await sortedFiles[i].delete();
        }
      }
    } catch (e) {
      logger.logError('Error cleaning old segments: $e', _logTag);
    }
  }

  /// Creates a composite video segment that includes the current time position
  Future<bool> createCompositeVideo({
    required List<ClipModel> clips,
    required Map<int, Rect> positions,
    required Map<int, Flip> flips,
    required int currentTimeMs,
    Size? containerSize,
  }) async {
    // Skip if we're recovering from errors
    if (_isRecoveringFromError) {
      logger.logInfo('Skipping composite video creation while recovering from errors', _logTag);
      return false;
    }
    
    // Store the current position for seeking
    _currentPositionMs = currentTimeMs;
    
    // Using synchronized pattern
    if (_isProcessing) {
      logger.logInfo('FFmpeg is already processing, skipping duplicate request', _logTag);
      // If we have a player already, seek to the requested position
      if (_videoPlayerController != null && 
          _segmentStartTimeMs != null && 
          _segmentEndTimeMs != null &&
          currentTimeMs >= _segmentStartTimeMs! && 
          currentTimeMs <= _segmentEndTimeMs!) {
        await _seekToPosition(currentTimeMs - _segmentStartTimeMs!);
      }
      return false;
    }
    
    // Check if we already have a segment that contains this time position
    if (_segmentStartTimeMs != null && _segmentEndTimeMs != null && _currentCompositeFilePath != null) {
      if (currentTimeMs >= _segmentStartTimeMs! && currentTimeMs <= _segmentEndTimeMs!) {
        // Current time is within the cached segment, just seek to the position
        if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
          await _seekToPosition(currentTimeMs - _segmentStartTimeMs!);
          return true;
        }
      }
    }
    
    // Calculate segment range around the current time
    final segmentStartMs = _calculateSegmentStart(currentTimeMs);
    final segmentEndMs = segmentStartMs + _segmentDurationMs;
    
    // Filter only video clips that should be visible during this segment
    final activeClips = clips.where((clip) {
      final clipStart = clip.startTimeOnTrackMs;
      final duration = clip.durationInSourceMs ??
          (clip.endTimeInSourceMs > clip.startTimeInSourceMs
              ? clip.endTimeInSourceMs - clip.startTimeInSourceMs
              : 0);
      final clipEnd = clipStart + duration;
      
      // Check file existence
      bool fileExists = false;
      try {
        fileExists = File(clip.sourcePath).existsSync();
        if (!fileExists) {
          logger.logWarning('Source file not found: ${clip.sourcePath}', _logTag);
        }
      } catch (e) {
        logger.logError('Error checking file existence: ${clip.sourcePath} - $e', _logTag);
      }
      
      // Determine if clip overlaps with segment
      bool isVideo = clip.type == ClipType.video;
      bool hasId = clip.databaseId != null;
      bool overlapWithSegment = (clipStart < segmentEndMs && clipEnd > segmentStartMs);
      bool hasPosition = hasId && positions.containsKey(clip.databaseId!);
      bool hasFlip = hasId && flips.containsKey(clip.databaseId!);
      
      return isVideo && hasId && overlapWithSegment && hasPosition && hasFlip && fileExists;
    }).toList();
    
    // Calculate a hash of the current configuration
    final configData = StringBuffer();
    configData.write('range:$segmentStartMs-$segmentEndMs;');
    configData.write('clips:${activeClips.map((c) => '${c.databaseId}-${c.sourcePath}').join(',')};');
    configData.write('positions:${positions.entries.map((e) => '${e.key}-${e.value.left}-${e.value.top}-${e.value.width}-${e.value.height}').join(',')};');
    configData.write('flips:${flips.entries.map((e) => '${e.key}-${e.value.index}').join(',')};');
    configData.write('size:${containerSize?.width ?? 0}-${containerSize?.height ?? 0}');
    configData.write('mute:$_muteAudio');
    
    final configHash = sha256.convert(utf8.encode(configData.toString())).toString();
    
    // If this is the same configuration we processed last time, don't regenerate
    if (configHash == _lastConfigHash && _currentCompositeFilePath != null && _videoPlayerController != null) {
      logger.logInfo("Config hasn't changed, reusing existing segment", _logTag);
      await _seekToPosition(currentTimeMs - segmentStartMs);
      return true;
    }
    
    // Set the new hash
    _lastConfigHash = configHash;
    
    // Start processing
    _isProcessing = true;
    isProcessingNotifier.value = true;
    
    bool result = false;
    
    try {
      logger.logInfo(
        'Creating video segment from ${segmentStartMs}ms to ${segmentEndMs}ms with ${activeClips.length} active clips',
        _logTag,
      );
      
      if (activeClips.isEmpty) {
        logger.logInfo('No active video clips to display in this time range', _logTag);
        await _clearPlayer();
        _segmentStartTimeMs = null;
        _segmentEndTimeMs = null;
        result = true;
        return result;
      }

      // Set canvas size to container size or default if not provided
      final canvasWidth = containerSize?.width.toInt() ?? 1280;
      final canvasHeight = containerSize?.height.toInt() ?? 720;
      
      // Use a deterministic output path based on the config hash
      if (_framesDir == null) {
        await _setupFramesDirectory();
      }
      final outputPath = p.join(_framesDir!.path, 'segment_${configHash.substring(0, 10)}.mp4');
      
      // If the file already exists (from a previous run), just reuse it
      if (File(outputPath).existsSync()) {
        logger.logInfo('Segment file already exists, reusing: $outputPath', _logTag);
        _currentCompositeFilePath = outputPath;
        _segmentStartTimeMs = segmentStartMs;
        _segmentEndTimeMs = segmentEndMs;
        await _updatePlayer(outputPath);
        await _seekToPosition(currentTimeMs - segmentStartMs);
        _isProcessing = false;
        isProcessingNotifier.value = false;
        return true;
      }
      
      // Generate the composite segment with proper FPS
      final command = await _createCompositeSegmentCommand(
        activeClips: activeClips,
        positions: positions,
        flips: flips,
        segmentStartMs: segmentStartMs,
        segmentDurationMs: _segmentDurationMs,
        fps: _fps,
        outputPath: outputPath,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );
      
      // Execute the FFmpeg command
      logger.logInfo('Executing FFmpeg command: ${command.executable} ${command.args.join(' ')}', _logTag);
      
      final process = await runExecutableArguments(
        command.executable,
        command.args,
        stderrEncoding: utf8,
        stdoutEncoding: utf8,
      );
      
      if (process.exitCode != 0) {
        logger.logError(
          'FFmpeg process failed with exit code ${process.exitCode}. Error: ${process.stderr}',
          _logTag,
        );
        _isProcessing = false;
        isProcessingNotifier.value = false;
        return false;
      }
      
      // Check if the output file was created
      if (!File(outputPath).existsSync()) {
        logger.logError('Output file not created: $outputPath', _logTag);
        _isProcessing = false;
        isProcessingNotifier.value = false;
        return false;
      }
      
      _currentCompositeFilePath = outputPath;
      _segmentStartTimeMs = segmentStartMs;
      _segmentEndTimeMs = segmentEndMs;
      
      // Update the video player
      await _updatePlayer(outputPath);
      await _seekToPosition(currentTimeMs - segmentStartMs);
      
      // Clean up old segments
      await _cleanOldSegments();
      
      result = true;
    } catch (e, stackTrace) {
      logger.logError('Error creating composite video: $e\n$stackTrace', _logTag);
      _handleError();
      result = false;
    } finally {
      _isProcessing = false;
      isProcessingNotifier.value = false;
    }
    
    return result;
  }
  
  int _calculateSegmentStart(int currentTimeMs) {
    // Create a segment centered around the current position where possible
    final halfSegment = _segmentDurationMs ~/ 2;
    if (currentTimeMs < halfSegment) {
      return 0;
    }
    return currentTimeMs - halfSegment;
  }
  
  Future<CliCommand> _createCompositeSegmentCommand({
    required List<ClipModel> activeClips,
    required Map<int, Rect> positions,
    required Map<int, Flip> flips,
    required int segmentStartMs,
    required int segmentDurationMs,
    required int fps,
    required String outputPath,
    required int canvasWidth,
    required int canvasHeight,
  }) async {
    final segmentDurationSec = segmentDurationMs / 1000.0;
    
    // Build the command arguments
    final args = <String>[];
    
    // Add global options for a quieter output
    args.addAll(['-v', 'error', '-stats']);
    
    // Use a single active clip for audio to avoid echo
    ClipModel? primaryAudioClip;
    if (!_muteAudio && activeClips.isNotEmpty) {
      // Choose the most dominant clip (largest visible area) for audio
      primaryAudioClip = _findPrimaryAudioClip(activeClips, positions);
    }
    
    // Add input arguments for each clip with seeking
    for (int i = 0; i < activeClips.length; i++) {
      final clip = activeClips[i];
      final clipTimeInSourceMs = segmentStartMs - clip.startTimeOnTrackMs + clip.startTimeInSourceMs;
      final clipTimeInSourceSeconds = clipTimeInSourceMs / 1000.0;
      
      // Only seek if we're not starting from the beginning of the clip
      if (clipTimeInSourceMs > 0) {
        args.add('-ss');
        args.add(clipTimeInSourceSeconds.toStringAsFixed(3));
      }
      
      args.add('-i');
      args.add(clip.sourcePath);
    }
    
    // Add black background input with specified fps
    args.addAll([
      '-f', 'lavfi',
      '-i', 'color=c=black:s=${canvasWidth}x${canvasHeight}:r=$fps:d=$segmentDurationSec',
    ]);
    
    // Create filter complex for video
    final filterComplex = _buildFilterComplex(
      activeClips: activeClips,
      positions: positions,
      flips: flips,
      segmentStartMs: segmentStartMs,
      fps: fps,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      primaryAudioClip: primaryAudioClip,
    );
    
    // Add filter complex
    args.addAll([
      '-filter_complex', filterComplex,
    ]);
    
    // Map output streams
    args.add('-map');
    args.add('[v_out]');  // Video output stream
    
    // Only map audio if we have a primary audio clip and audio isn't muted
    if (!_muteAudio && primaryAudioClip != null) {
      args.add('-map');
      // Get index of primary audio clip
      final primaryAudioIndex = activeClips.indexOf(primaryAudioClip);
      args.add('${primaryAudioIndex}:a');
    }
    
    // Add encoding options
    args.addAll([
      '-t', segmentDurationSec.toStringAsFixed(3),
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-crf', '23',
      '-pix_fmt', 'yuv420p',
      '-r', fps.toString(), // Ensure output fps is consistent
    ]);
    
    // Audio codec options
    if (!_muteAudio && primaryAudioClip != null) {
      args.addAll([
        '-c:a', 'aac',
        '-b:a', '128k',
        '-ar', '48000',
        '-ac', '2',
      ]);
    } else {
      // If no audio or muted, create a video with no audio
      args.add('-an');
    }
    
    // Final output options
    args.addAll([
      '-y', // Overwrite output file
      outputPath,
    ]);
    
    return CliCommand(executable: 'ffmpeg', args: args);
  }
  
  // Find the primary clip to use for audio
  ClipModel? _findPrimaryAudioClip(List<ClipModel> activeClips, Map<int, Rect> positions) {
    if (activeClips.isEmpty) return null;
    
    // If only one clip, use it
    if (activeClips.length == 1) return activeClips[0];
    
    // Find the clip with the largest visible area
    ClipModel? primaryClip;
    double maxArea = 0;
    
    for (final clip in activeClips) {
      if (clip.databaseId == null) continue;
      
      final rect = positions[clip.databaseId!];
      if (rect == null) continue;
      
      final area = rect.width * rect.height;
      if (area > maxArea) {
        maxArea = area;
        primaryClip = clip;
      }
    }
    
    return primaryClip;
  }
  
  String _buildFilterComplex({
    required List<ClipModel> activeClips,
    required Map<int, Rect> positions,
    required Map<int, Flip> flips,
    required int segmentStartMs,
    required int fps,
    required int canvasWidth,
    required int canvasHeight,
    required ClipModel? primaryAudioClip,
  }) {
    // Background is the last input
    final bgIndex = activeClips.length;
    String filterComplex = "";
    
    // Process each clip's video
    for (int i = 0; i < activeClips.length; i++) {
      final clip = activeClips[i];
      if (clip.databaseId == null) continue;
      
      final clipId = clip.databaseId!;
      final rect = positions[clipId] ?? Rect.zero;
      final flip = flips[clipId] ?? Flip.none;
      
      // Video filters: fps, scale, flip
      String clipFilters = "fps=$fps,";
      clipFilters += "scale=${rect.width.toInt()}:${rect.height.toInt()}";
      
      // Handle flip
      if (flip == Flip.horizontal || flip.index == 2) { // 2 is the index for both
        clipFilters += ",hflip";
      }
      if (flip == Flip.vertical || flip.index == 2) { // 2 is the index for both
        clipFilters += ",vflip";
      }
      
      // Set PTS for this clip
      clipFilters += ",setpts=PTS-STARTPTS";
      
      filterComplex += "[$i:v]$clipFilters[v$i];";
    }
    
    // Set up background with proper fps
    filterComplex += "[$bgIndex:v]fps=$fps,setpts=PTS-STARTPTS[bg];";
    
    // Overlay clips on the background
    String lastOutput = "bg";
    for (int i = 0; i < activeClips.length; i++) {
      final clip = activeClips[i];
      if (clip.databaseId == null) continue;
      
      final clipId = clip.databaseId!;
      final rect = positions[clipId] ?? Rect.zero;
      
      // Overlay the clip on the current output
      filterComplex += "[$lastOutput][v$i]overlay=${rect.left.toInt()}:${rect.top.toInt()}";
      
      // Set the output label
      if (i == activeClips.length - 1) {
        filterComplex += "[v_out]";
      } else {
        filterComplex += "[o$i]";
        lastOutput = "o$i";
      }
      
      // Add separator except for the last one
      if (i < activeClips.length - 1) {
        filterComplex += ";";
      }
    }
    
    // If no clips, just pass through the background
    if (activeClips.isEmpty) {
      filterComplex = "[$bgIndex:v]fps=$fps,setpts=PTS-STARTPTS[v_out]";
    }
    
    return filterComplex;
  }
  
  Future<void> _updatePlayer(String filePath) async {
    try {
      // Only recreate the controller if needed
      if (_videoPlayerController?.dataSource != 'file://$filePath') {
        // Dispose the current controller if it exists
        await _videoPlayerController?.dispose();
        isPlayerReadyNotifier.value = false;
        
        // Create a new controller for the file
        _videoPlayerController = VideoPlayerController.file(
          File(filePath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        
        // Initialize the controller
        await _videoPlayerController!.initialize();
        
        // Set to loop for continuous preview
        await _videoPlayerController!.setLooping(true);
        
        isPlayerReadyNotifier.value = true;
      }
      
      // Reset error count on successful update
      _consecutiveErrorCount = 0;
    } catch (e, stackTrace) {
      logger.logError('Error updating video player: $e\n$stackTrace', _logTag);
      _handleError();
    }
  }
  
  Future<void> _seekToPosition(int offsetMs) async {
    try {
      if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
        final offsetSeconds = offsetMs / 1000.0;
        final duration = _videoPlayerController!.value.duration.inMilliseconds / 1000.0;
        
        if (offsetSeconds >= 0 && offsetSeconds < duration) {
          // Using a "show single frame" trick
          final wasPlaying = _videoPlayerController!.value.isPlaying;
          
          // Force play - this helps ensure the frame displays correctly
          await _videoPlayerController!.play();
          
          // Seek to the position
          await _videoPlayerController!.seekTo(Duration(milliseconds: offsetMs));
          
          // Add a tiny delay to ensure the frame is loaded
          await Future.delayed(const Duration(milliseconds: 32));
          
          // Restore original playing state
          if (!wasPlaying) {
            await _videoPlayerController!.pause();
          }
          
          // Update our isPlaying notifier for API compatibility
          isPlayingNotifier.value = _videoPlayerController!.value.isPlaying;
        }
      }
    } catch (e) {
      logger.logError('Error seeking to position: $e', _logTag);
    }
  }
  
  Future<void> _clearPlayer() async {
    try {
      await _videoPlayerController?.pause();
      await _videoPlayerController?.dispose();
      _videoPlayerController = null;
      isPlayerReadyNotifier.value = false;
      isPlayingNotifier.value = false;
    } catch (e) {
      logger.logError('Error clearing player: $e', _logTag);
    }
  }
  
  void _handleError() {
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
      logger.logError('Too many consecutive errors, backing off', _logTag);
      _isRecoveringFromError = true;
      Future.delayed(const Duration(seconds: 2), () {
        _isRecoveringFromError = false;
        _consecutiveErrorCount = 0;
      });
    }
  }
  
  Future<void> dispose() async {
    await _videoPlayerController?.dispose();
    
    // Clean up frames directory
    try {
      if (_framesDir == null) return;
      
      if (await _framesDir!.exists()) {
        await _framesDir!.delete(recursive: true);
      }
    } catch (e) {
      logger.logError('Error cleaning up frames directory: $e', _logTag);
    }
  }
} 