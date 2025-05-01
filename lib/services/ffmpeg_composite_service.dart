import 'dart:io';
import 'dart:math'; // Added for ceil and sqrt
import 'package:process_run/process_run.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// Service responsible for generating composite video frames using FFmpeg.
class FfmpegCompositeService {
  final String _logTag = 'FfmpegCompositeService';

  /// Uses FFmpeg to generate a single composite video frame, arranging multiple
  /// videos into an automatic grid layout.
  ///
  /// Parameters:
  /// - `videoInputs`: A list of maps, each containing 'path' (String) and 'source_pos_ms' (int).
  /// - `outputFile`: The path where the output frame will be saved.
  /// - `canvasWidth`: The width of the output canvas.
  /// - `canvasHeight`: The height of the output canvas.
  ///
  /// Returns `true` if the frame generation was successful, `false` otherwise.
  Future<bool> generateCompositeFrame({
    required List<Map<String, dynamic>> videoInputs,
    // required List<Map<String, dynamic>> layoutInputs, // Removed - Layout is automatic grid
    required String outputFile,
    required int canvasWidth,
    required int canvasHeight,
  }) async {
    // Updated validation check
    if (videoInputs.isEmpty) {
      logger.logError(
        'Invalid input: Video inputs list cannot be empty.',
        _logTag,
      );
      return false;
    }

    try {
      // --- Input Validation ---
      // Simplified validation: Only check required fields from videoInputs
      for (int i = 0; i < videoInputs.length; i++) {
        final sourcePath = videoInputs[i]['path'] as String?;
        final sourcePosMs = videoInputs[i]['source_pos_ms'] as int?;
        // final layout = layoutInputs[i]; // Removed

        if (sourcePath == null || sourcePosMs == null) {
          logger.logError(
            'Invalid input data for item $i: Missing required fields (path, source_pos_ms).',
            _logTag,
          );
          return false;
        }
        // Removed validation for layout['x'], ['y'], ['width'], ['height'], ['flip_h'], ['flip_v']
        // as layoutInputs is removed and flip flags are not currently used in the grid filter.

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

      // --- Build Dynamic Filter Graph for Grid Layout ---
      String filterComplex = '';
      final int n = videoInputs.length;

      if (n == 1) {
        // Single video: Scale to fit canvas, maintain aspect ratio
        filterComplex =
            '[0:v]scale=$evenCanvasWidth:$evenCanvasHeight:force_original_aspect_ratio=decrease:flags=lanczos,pad=$evenCanvasWidth:$evenCanvasHeight:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1[out]';
        logger.logInfo('Using single video scaling filter', _logTag);
      } else {
        // Multiple videos: Create a grid layout
        final int cols = (sqrt(n)).ceil();
        final int rows = (n / cols).ceil();
        final int cellWidth = evenCanvasWidth ~/ cols;
        final int cellHeight = evenCanvasHeight ~/ rows;

        // Ensure cell dimensions are even (important for some codecs, good practice)
        final int evenCellWidth = cellWidth.isOdd ? cellWidth - 1 : cellWidth;
        final int evenCellHeight = cellHeight.isOdd ? cellHeight - 1 : cellHeight;
        if (evenCellWidth <= 0 || evenCellHeight <= 0) {
           logger.logError('Calculated cell dimensions are invalid: ${evenCellWidth}x${evenCellHeight}. Canvas: ${evenCanvasWidth}x${evenCanvasHeight}, Grid: ${cols}x$rows', _logTag);
           return false;
        }
        if (evenCellWidth != cellWidth || evenCellHeight != cellHeight) {
            logger.logWarning('Adjusted cell dimensions to be even: ${cellWidth}x${cellHeight} -> ${evenCellWidth}x${evenCellHeight}', _logTag);
        }

        logger.logInfo(
          'Creating grid layout: $cols columns, $rows rows. Cell size: ${evenCellWidth}x$evenCellHeight',
          _logTag,
        );

        final List<String> scaleFilters = [];
        for (int i = 0; i < n; i++) {
          // Scale each video to fit within the cell, then pad to the exact cell size
          // Use 'min(iw,ih)' checks in scale to avoid upscaling tiny videos excessively if needed? Not for now.
          // Changed pad condition to iw:ih for input w/h instead of ow/oh
          scaleFilters.add(
              '[$i:v]scale=w=$evenCellWidth:h=$evenCellHeight:force_original_aspect_ratio=decrease:flags=lanczos'
              ',pad=w=$evenCellWidth:h=$evenCellHeight:x=(ow-iw)/2:y=(oh-ih)/2:color=black' // Pad to exact cell size
              '[scaled$i]');
        }

        final List<String> overlayFilters = [];
        String lastOverlayOutput = 'base'; // Start with the base canvas

        // Create the base canvas
        overlayFilters.add(
            'color=c=black:s=${evenCanvasWidth}x${evenCanvasHeight}[base]');

        // Chain overlays
        for (int i = 0; i < n; i++) {
          final int colIndex = i % cols;
          final int rowIndex = i ~/ cols;
          final int xPos = colIndex * cellWidth;
          final int yPos = rowIndex * cellHeight;
          final String currentOutput = (i == n - 1) ? 'out' : 'ov$i'; // Final output is 'out'

          overlayFilters.add(
              '[$lastOverlayOutput][scaled$i]overlay=x=$xPos:y=$yPos${(i == n - 1) ? "" : ":eof_action=pass"}[$currentOutput]');
          lastOverlayOutput = currentOutput;
        }

        filterComplex = '${scaleFilters.join(';')};${overlayFilters.join(';')}';
      }

      // Final command arguments with quality improvements
      final ffmpegArgs = [
        ...ffmpegInputArgs, // Seeked inputs first
        '-filter_complex',
        filterComplex,
        '-map', '[out]', // Map the final output
        '-frames:v', '1', // Output exactly one video frame
        '-c:v', 'png', // Use PNG encoding for single frames
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
      if (fileSize < 50) { // Reduced minimum size check for PNG
        logger.logWarning( // Changed to Warning as small PNG might be valid (e.g., black frame)
          'FFmpeg output file is small (${fileSize} bytes), might be empty or simple: $outputFile',
          _logTag,
        );
        // return false; // Don't automatically fail for small size, let the image loader decide
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

  /// Generates a video segment with multiple frames for playback.
  /// 
  /// Parameters:
  /// - `videoInputs`: List of maps with video source info (path, source_pos_ms)
  /// - `layoutInputs`: List of maps with layout info (x, y, width, height, flip_h, flip_v)
  /// - `outputFile`: Path where to save the output video
  /// - `canvasWidth`: Width of the output video
  /// - `canvasHeight`: Height of the output video
  /// - `durationMs`: Duration of the segment in milliseconds
  /// - `fps`: Frames per second (default: 30)
  /// 
  /// Returns `true` if generation was successful, `false` otherwise
  Future<bool> generateVideoSegment({
    required List<Map<String, dynamic>> videoInputs,
    required List<Map<String, dynamic>> layoutInputs,
    required String outputFile,
    required int canvasWidth,
    required int canvasHeight,
    required int durationMs,
    int fps = 30,
  }) async {
    if (videoInputs.isEmpty) {
      logger.logError(
        'Invalid input: Video inputs list cannot be empty.',
        _logTag,
      );
      return false;
    }

    if (videoInputs.length != layoutInputs.length) {
      logger.logError(
        'Mismatch between videoInputs (${videoInputs.length}) and layoutInputs (${layoutInputs.length}).',
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

        if (sourcePath == null || sourcePosMs == null) {
          logger.logError(
            'Invalid input data for item $i: Missing required fields (path, source_pos_ms).',
            _logTag,
          );
          return false;
        }

        // Validate layout parameters
        final x = layout['x'] as int?;
        final y = layout['y'] as int?;
        final width = layout['width'] as int?;
        final height = layout['height'] as int?;
        final flipH = layout['flip_h'] as bool?;
        final flipV = layout['flip_v'] as bool?;

        if (x == null || y == null || width == null || height == null || 
            flipH == null || flipV == null) {
          logger.logError(
            'Invalid layout data for item $i: Missing required fields.',
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

      // --- Ensure canvas dimensions are even for video codec compatibility ---
      final int evenCanvasWidth = canvasWidth.isOdd ? canvasWidth - 1 : canvasWidth;
      final int evenCanvasHeight = canvasHeight.isOdd ? canvasHeight - 1 : canvasHeight;

      if (evenCanvasWidth != canvasWidth || evenCanvasHeight != canvasHeight) {
        logger.logWarning(
          'Canvas dimensions adjusted to be even: ${canvasWidth}x${canvasHeight} -> ${evenCanvasWidth}x${evenCanvasHeight}.',
          _logTag,
        );
      }

      // --- Build FFmpeg Command ---
      final List<String> ffmpegInputArgs = [];

      // Prepare input args for each video source
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

      // --- Build Filter Graph for Layout ---
      final List<String> filterParts = [];
      
      // 1. Scale and position each input
      for (int i = 0; i < videoInputs.length; i++) {
        final layout = layoutInputs[i];
        final int x = layout['x'] as int;
        final int y = layout['y'] as int;
        final int width = layout['width'] as int;
        final int height = layout['height'] as int;
        final bool flipH = layout['flip_h'] as bool;
        final bool flipV = layout['flip_v'] as bool;
        
        // Apply scale, flip, and position - Use evenCanvasWidth/Height for scaling
        String scaleFilter = '[${i}:v]scale=${evenCanvasWidth}:${evenCanvasHeight}:force_original_aspect_ratio=decrease:flags=lanczos';
        
        // Add flipping if needed
        if (flipH || flipV) {
          final List<String> flips = [];
          if (flipH) flips.add('horizontal');
          if (flipV) flips.add('vertical');
          scaleFilter += ',hflip=${flipH ? 1 : 0},vflip=${flipV ? 1 : 0}';
        }
        
        // Add padding if needed to ensure exact dimensions - use evenCanvasWidth/Height
        scaleFilter += ',pad=${evenCanvasWidth}:${evenCanvasHeight}:(ow-iw)/2:(oh-ih)/2:color=black';
        
        // Named output for this stream
        scaleFilter += '[v${i}]';
        
        filterParts.add(scaleFilter);
      }
      
      // 2. Create base canvas
      filterParts.add('color=c=black:s=${evenCanvasWidth}x${evenCanvasHeight}[base]');
      
      // 3. Overlay all videos onto base canvas
      String lastOutput = 'base';
      for (int i = 0; i < videoInputs.length; i++) {
        final layout = layoutInputs[i];
        final int x = layout['x'] as int;
        final int y = layout['y'] as int;
        
        final String currentOutput = (i == videoInputs.length - 1) ? 'out' : 'overlay${i}';
        filterParts.add('[${lastOutput}][v${i}]overlay=x=${x}:y=${y}[${currentOutput}]');
        lastOutput = currentOutput;
      }
      
      final String filterComplex = filterParts.join(';');
      
      // Calculate duration in seconds
      final durationSec = durationMs / 1000.0;
      
      // Final command arguments for video segment
      final ffmpegArgs = [
        ...ffmpegInputArgs,
        '-filter_complex', filterComplex,
        '-map', '[out]',
        '-t', durationSec.toString(), // Set duration
        '-c:v', 'libx264', // H.264 codec
        '-preset', 'ultrafast', // Fast encoding for preview
        '-crf', '23', // Reasonable quality
        '-pix_fmt', 'yuv420p', // Compatible pixel format
        '-r', fps.toString(), // Set frame rate
        '-an', // No audio
        '-y', // Overwrite output
        outputFile,
      ];

      final commandString = 'ffmpeg ${ffmpegArgs.join(" ")}';
      logger.logInfo('Running FFmpeg command for video segment: $commandString', _logTag);

      // --- Execute FFmpeg ---
      final result = await runExecutableArguments(
        'ffmpeg',
        ffmpegArgs,
        verbose: true,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
        runInShell: false,
      );

      if (result.exitCode == 0) {
        logger.logInfo('Video segment generation completed successfully', _logTag);
        
        // Verify the output file exists and has data
        final outputFilePath = outputFile; // Store the path
        final outputFileObj = File(outputFilePath);
        final fileExists = await outputFileObj.exists();
        final fileSize = fileExists ? await outputFileObj.length() : 0;
        
        if (fileExists && fileSize > 0) {
          logger.logInfo('Generated video segment: $outputFilePath (${fileSize} bytes)', _logTag);
          return true;
        } else {
          logger.logError('FFmpeg completed but output file is missing or empty', _logTag);
          return false;
        }
      } else {
        logger.logError('FFmpeg process failed with exit code ${result.exitCode}', _logTag);
        logger.logError('Error output: ${result.stderr}', _logTag);
        return false;
      }
    } catch (e, stackTrace) {
      logger.logError('Error generating video segment: $e', _logTag, stackTrace);
      return false;
    }
  }
}

// Define kDebugMode if not available (e.g., outside Flutter)
const bool kDebugMode = !bool.fromEnvironment('dart.vm.product');
