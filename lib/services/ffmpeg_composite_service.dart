import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:process_run/process_run.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Assuming Flip enum might be needed, adjust if not.
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flutter_box_transform/flutter_box_transform.dart'; // Needed for Flip enum

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
        logger.logError('Invalid input: Video inputs list is empty or does not match layout inputs length.', _logTag);
        return false;
    }

    try {
      // --- Input Validation ---
      for (int i = 0; i < videoInputs.length; i++) {
         final sourcePath = videoInputs[i]['path'] as String?;
         final sourcePosMs = videoInputs[i]['source_pos_ms'] as int?;
         final layout = layoutInputs[i];

         if (sourcePath == null || sourcePosMs == null || layout['x'] == null || layout['y'] == null || layout['width'] == null || layout['height'] == null || layout['flip_h'] == null || layout['flip_v'] == null) {
            logger.logError('Invalid input data for item $i: Missing required fields.', _logTag);
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
      String filterComplex = '';
      final List<String> ffmpegInputArgs = [];

      // Ensure canvas dimensions are even for libx264 compatibility
      final int evenCanvasWidth = canvasWidth.isOdd ? canvasWidth - 1 : canvasWidth;
      final int evenCanvasHeight = canvasHeight.isOdd ? canvasHeight - 1 : canvasHeight;

      // If dimensions changed, log a warning as it might slightly affect layout
      if (evenCanvasWidth != canvasWidth || evenCanvasHeight != canvasHeight) {
        logger.logWarning(
            'Canvas dimensions adjusted to be even: ${canvasWidth}x${canvasHeight} -> ${evenCanvasWidth}x${evenCanvasHeight}. This might cause minor layout shifts.',
            _logTag);
      }

      // Input processing: Seek to the specific frame time for each input
      for (int i = 0; i < videoInputs.length; i++) {
        final sourcePosMs = videoInputs[i]['source_pos_ms'] as int;
        final sourcePath = videoInputs[i]['path'] as String;
        final layout = layoutInputs[i];

        // Add seek argument *before* the input file for speed
        ffmpegInputArgs.add('-ss');
        ffmpegInputArgs.add('${sourcePosMs / 1000.0}'); // FFmpeg uses seconds

        // Add hardware acceleration option *before* the input file
        ffmpegInputArgs.add('-hwaccel');
        ffmpegInputArgs.add('auto'); // Let FFmpeg detect best hwaccel

        ffmpegInputArgs.add('-i');
        ffmpegInputArgs.add(sourcePath);

        // Start building the filter chain for this input
        filterComplex += '[$i:v]';

        // Apply flipping if needed
        List<String> flipFilters = [];
        if (layout['flip_h'] == true) flipFilters.add('hflip');
        if (layout['flip_v'] == true) flipFilters.add('vflip');
        if (flipFilters.isNotEmpty) {
          filterComplex += flipFilters.join(',') + ',';
        }

        // Add scaling
        final targetWidth = (layout['width'] as num).round(); // Ensure integer width/height
        final targetHeight = (layout['height'] as num).round();
        filterComplex += 'scale=$targetWidth:$targetHeight[v$i];';
      }

      // Create the base canvas
      filterComplex +=
          'color=c=black:s=${evenCanvasWidth}x$evenCanvasHeight:d=0.04[base];'; // Use even dimensions

      // Overlay videos onto the base canvas
      String lastOverlayOutput = '[base]';
      for (int i = 0; i < videoInputs.length; i++) {
        final layout = layoutInputs[i];
        final targetWidth = (layout['width'] as num).round();
        final targetHeight = (layout['height'] as num).round();

        // Calculate centered coordinates instead of using layout x/y
        final centerX = ((evenCanvasWidth - targetWidth) / 2).round();
        final centerY = ((evenCanvasHeight - targetHeight) / 2).round();

        final overlayOutput =
            (i == videoInputs.length - 1)
                ? '[out]'
                : '[ovr$i]'; // Final output is [out]

        filterComplex +=
            '$lastOverlayOutput[v$i]overlay=x=$centerX:y=$centerY:shortest=1$overlayOutput;'; // Use centered coordinates
        if (i < videoInputs.length - 1) {
          lastOverlayOutput = overlayOutput;
        }
      }

      // Final command arguments
      final ffmpegArgs = [
        ...ffmpegInputArgs, // Seeked inputs first
        '-filter_complex',
        filterComplex.trim().endsWith(';')
            ? filterComplex.trim().substring(0, filterComplex.length - 1)
            : filterComplex,
        '-map', '[out]', // Map the final overlay output
        '-frames:v', '1', // Output exactly one video frame
        '-c:v', 'libx264', // Use H.264 encoding
        '-preset', 'superfast', // Prioritize speed
        '-pix_fmt', 'yuv420p', // Standard pixel format
        '-flags', '+low_delay', // Optimize for low delay
        '-threads', '0', // Use all available CPU threads
        '-an', // Disable audio stream
        '-sn', // Disable subtitle stream
        '-y', // Overwrite output file if it exists
        outputFile,
      ];

      final commandString = 'ffmpeg ${ffmpegArgs.join(" ")}';
      logger.logInfo('Running FFmpeg command: $commandString', _logTag);

      // --- Execute FFmpeg ---
      final result = await runExecutableArguments(
        'ffmpeg',
        ffmpegArgs,
        verbose: kDebugMode, // Only verbose in debug mode
        stdoutEncoding: SystemEncoding(), // Handle potential encoding issues
        stderrEncoding: SystemEncoding(),
      );

      // Log FFmpeg result regardless of exit code for debugging
       if (result.exitCode != 0 || kDebugMode) { // Log errors or always in debug
            logger.logInfo(
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
        // Optionally delete the potentially corrupt file
        // await outputFileObj.delete();
        return false;
      }

      logger.logInfo('FFmpeg frame generation successful: $outputFile', _logTag);
      return true;
    } catch (e, stackTrace) {
      logger.logError('Error during FFmpeg processing: $e\n$stackTrace', _logTag);
      // Attempt to clean up output file on error
      try {
          final file = File(outputFile);
          if (await file.exists()) {
             await file.delete();
             logger.logInfo('Cleaned up output file after error: $outputFile', _logTag);
          }
      } catch (cleanupError) {
           logger.logError('Error cleaning up output file $outputFile after primary error: $cleanupError', _logTag);
      }
      return false;
    }
  }
}

// Define kDebugMode if not available (e.g., outside Flutter)
const bool kDebugMode = !bool.fromEnvironment('dart.vm.product');