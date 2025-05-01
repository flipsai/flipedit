import 'dart:io';
import 'package:process_run/process_run.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// Service responsible for generating composite video frames using FFmpeg.
class FfmpegCompositeService {
  final String _logTag = 'FfmpegCompositeService';

  /// Uses FFmpeg to generate a single composite video frame.
  ///
  /// Parameters:
  /// - `videoInputs`: A list of maps, each containing 'path' (String) and 'source_pos_ms' (int).
  /// - `layoutInputs`: A list of maps, each containing 'x', 'y', 'width', 'height' (int/double),
  ///   'flip_h' (bool), 'flip_v' (bool). Must correspond 1:1 with `videoInputs`.
  /// - `outputFile`: The path where the output frame will be saved.
  /// - `canvasWidth`: The width of the output canvas.
  /// - `canvasHeight`: The height of the output canvas.
  ///
  /// Returns `true` if the frame generation was successful, `false` otherwise.
  Future<bool> generateCompositeFrame({
    required List<Map<String, dynamic>> videoInputs,
    required List<Map<String, dynamic>> layoutInputs,
    required String outputFile,
    required int canvasWidth,
    required int canvasHeight,
  }) async {
    if (videoInputs.isEmpty || videoInputs.length != layoutInputs.length) {
      logger.logError(
        'Invalid input: Video inputs list is empty or does not match layout inputs length.',
        _logTag,
      );
      return false;
    }

    try {
      // --- Input Validation ---
      for (int i = 0; i < videoInputs.length; i++) {
        final sourcePath = videoInputs[i]['path'] as String?;
        final sourcePosMs = videoInputs[i]['source_pos_ms'] as int?;
        final layout = layoutInputs[i];

        if (sourcePath == null ||
            sourcePosMs == null ||
            layout['x'] == null ||
            layout['y'] == null ||
            layout['width'] == null ||
            layout['height'] == null ||
            layout['flip_h'] == null ||
            layout['flip_v'] == null) {
          logger.logError(
            'Invalid input data for item $i: Missing required fields.',
            _logTag,
          );
          return false;
        }

        final exists = await File(sourcePath).exists();
        if (!exists) {
          logger.logError('Source file does not exist: $sourcePath', _logTag);
          return false;
        }
      }

      // --- Directory and File Preparation ---
      final outputDir = File(outputFile).parent;
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
        logger.logInfo('Created output directory: ${outputDir.path}', _logTag);
      }

      final outputFileObj = File(outputFile);
      if (await outputFileObj.exists()) {
        logger.logWarning('Output file exists, deleting: $outputFile', _logTag);
        await outputFileObj.delete();
      }

      // --- Build FFmpeg Command ---
      final List<String> ffmpegInputArgs = [];

      // Ensure canvas dimensions are even for libx264 compatibility
      final int evenCanvasWidth =
          canvasWidth.isOdd ? canvasWidth - 1 : canvasWidth;
      final int evenCanvasHeight =
          canvasHeight.isOdd ? canvasHeight - 1 : canvasHeight;

      // If dimensions changed, log a warning as it might slightly affect layout
      if (evenCanvasWidth != canvasWidth || evenCanvasHeight != canvasHeight) {
        logger.logWarning(
          'Canvas dimensions adjusted to be even: ${canvasWidth}x${canvasHeight} -> ${evenCanvasWidth}x${evenCanvasHeight}.',
          _logTag,
        );
      }

      // Prepare input args with seeking (Seek after input for accuracy)
      for (int i = 0; i < videoInputs.length; i++) {
        final sourcePosMs = videoInputs[i]['source_pos_ms'] as int;
        final sourcePath = videoInputs[i]['path'] as String;

        // Input file first
        ffmpegInputArgs.add('-i');
        ffmpegInputArgs.add(sourcePath);
        // Seek argument *after* the input file for accuracy
        ffmpegInputArgs.add('-ss');
        ffmpegInputArgs.add('${sourcePosMs / 1000.0}'); // FFmpeg uses seconds
      }

      // Build an improved filter graph with better scaling
      String filterComplex = '';

      if (videoInputs.length == 1) {
        // For a single video, scale it to the full size with smart scaler
        filterComplex =
            '[0:v]scale=${evenCanvasWidth}:${evenCanvasHeight}:flags=lanczos,setsar=1[out]';
      } else if (videoInputs.length >= 2) {
        // For two videos, create a side-by-side layout with proper aspect ratio handling
        // Calculate target dimensions for each video to maintain aspect ratio while fitting in half the canvas
        final targetWidth = evenCanvasWidth ~/ 2;
        final targetHeight = evenCanvasHeight;

        // Side-by-side compositing using overlay on a black base canvas
        filterComplex = "[0:v]scale=w=291:h=376:force_original_aspect_ratio=decrease:flags=lanczos[scaled0];[1:v]scale=w=291:h=376:force_original_aspect_ratio=decrease:flags=lanczos[scaled1];color=c=black:s=582x376[base];[base][scaled0]overlay=x=0:y=((H-h)/2)[tmp];[tmp][scaled1]overlay=x=W/2:y=((H-h)/2)[out]";
        
        logger.logInfo(
          'Using overlay filter for side-by-side compositing',
          _logTag,
        );
      }

      // Final command arguments with quality improvements
      final ffmpegArgs = [
        ...ffmpegInputArgs, // Seeked inputs first
        '-filter_complex',
        filterComplex,
        '-map', '[out]', // Map the final output
        '-frames:v', '1', // Output exactly one video frame
        '-c:v', 'libx264', // Use H.264 encoding
        '-preset', 'ultrafast', // Maximum speed
        '-crf', '23', // Balance quality and size (lower means better quality)
        '-pix_fmt', 'yuv420p', // Standard pixel format
        '-an', // Disable audio stream
        '-y', // Overwrite output file if it exists
        outputFile,
      ];

      final commandString = 'ffmpeg ${ffmpegArgs.join(" ")}';
      logger.logInfo('Running FFmpeg command: $commandString', _logTag);

      // --- Execute FFmpeg ---
      final result = await runExecutableArguments(
        'ffmpeg',
        ffmpegArgs,
        verbose: true, // Always verbose for debugging
        stdoutEncoding: SystemEncoding(), // Handle potential encoding issues
        stderrEncoding: SystemEncoding(),
        runInShell: false, // Pass args directly to avoid shell splitting filter graph
      );

      // Always log the FFmpeg result for debugging
      if (result.exitCode == 0) {
        logger.logInfo('FFmpeg completed successfully', _logTag);
      } else {
        logger.logError(
          'FFmpeg Result (Exit Code: ${result.exitCode}):\nSTDOUT: ${result.stdout}\nSTDERR: ${result.stderr}',
          _logTag,
        );
      }

      // --- Result Validation ---
      if (result.exitCode != 0) {
        logger.logError(
          'FFmpeg failed with exit code ${result.exitCode}.',
          _logTag,
        );
        return false;
      }

      final fileCreated = await outputFileObj.exists();
      if (!fileCreated) {
        logger.logError(
          'FFmpeg process completed successfully but output file was not created: $outputFile',
          _logTag,
        );
        return false;
      }

      final fileSize = await outputFileObj.length();
      // Allow slightly smaller size, as single frame H.264 can be small
      if (fileSize < 50) {
        logger.logError(
          'FFmpeg output file too small (${fileSize} bytes), might be corrupt or empty: $outputFile',
          _logTag,
        );
        return false;
      }

      logger.logInfo(
        'FFmpeg frame generation successful: $outputFile (${fileSize} bytes)',
        _logTag,
      );
      return true;
    } catch (e, stackTrace) {
      logger.logError(
        'Error during FFmpeg processing: $e\n$stackTrace',
        _logTag,
      );
      // Attempt to clean up output file on error
      try {
        final file = File(outputFile);
        if (await file.exists()) {
          await file.delete();
          logger.logInfo(
            'Cleaned up output file after error: $outputFile',
            _logTag,
          );
        }
      } catch (cleanupError) {
        logger.logError(
          'Error cleaning up output file $outputFile after primary error: $cleanupError',
          _logTag,
        );
      }
      return false;
    }
  }
}

// Define kDebugMode if not available (e.g., outside Flutter)
const bool kDebugMode = !bool.fromEnvironment('dart.vm.product');
