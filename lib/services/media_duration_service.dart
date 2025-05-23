import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flipedit/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Media info with duration and dimensions
class MediaInfo {
  final int durationMs;
  final int width;
  final int height;

  MediaInfo({
    required this.durationMs,
    required this.width,
    required this.height,
  });

  @override
  String toString() =>
      'MediaInfo(durationMs: $durationMs, width: $width, height: $height)';
}

/// Service for retrieving media durations from the Python server
class MediaDurationService {
  static const _logTag = 'MediaDurationService';
  static const _defaultServerUrl = 'http://localhost:8081';
  final String serverUrl;

  MediaDurationService({this.serverUrl = _defaultServerUrl});

  /// Get the duration of a media file in milliseconds
  /// Returns 0 if the duration cannot be determined
  Future<int> getMediaDurationMs(String filePath) async {
    try {
      // Encode the file path for URL
      final encodedPath = Uri.encodeQueryComponent(filePath);
      final url = '$serverUrl/api/duration?path=$encodedPath';

      logInfo(_logTag, 'Getting duration for: $filePath');

      // Make HTTP request to the Python server
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                logError(_logTag, 'Request timed out for: $filePath');
                throw TimeoutException('Request timed out');
              },
            );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final durationMs = data['duration_ms'] as int;
          logInfo(_logTag, 'Duration for $filePath: $durationMs ms');
          return durationMs;
        } else {
          logError(
            _logTag,
            'Error getting duration: ${response.statusCode} - ${response.body}',
          );
          // Server returned an error, use fallback
          return _getFallbackDuration(filePath);
        }
      } catch (e) {
        // Handle timeout or other connection errors
        logError(_logTag, 'HTTP error: $e');
        return _getFallbackDuration(filePath);
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media duration: $e', stackTrace);
      // Use fallback method if server fails
      return _getFallbackDuration(filePath);
    }
  }

  /// Get both duration and dimensions of a media file
  /// Returns MediaInfo with zeros if the info cannot be determined
  Future<MediaInfo> getMediaInfo(String filePath) async {
    try {
      // Encode the file path for URL
      final encodedPath = Uri.encodeQueryComponent(filePath);
      final url = '$serverUrl/api/mediainfo?path=$encodedPath';

      logInfo(_logTag, 'Getting media info for: $filePath');

      // Make HTTP request to the Python server
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                logError(_logTag, 'Request timed out for: $filePath');
                throw TimeoutException('Request timed out');
              },
            );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final mediaInfo = MediaInfo(
            durationMs: data['duration_ms'] as int,
            width: data['width'] as int,
            height: data['height'] as int,
          );
          logInfo(_logTag, 'Media info for $filePath: $mediaInfo');
          return mediaInfo;
        } else {
          logError(
            _logTag,
            'Error getting media info: ${response.statusCode} - ${response.body}',
          );
          // Server returned an error, use fallback
          return _getFallbackMediaInfo(filePath);
        }
      } catch (e) {
        // Handle timeout or other connection errors
        logError(_logTag, 'HTTP error: $e');
        return _getFallbackMediaInfo(filePath);
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media info: $e', stackTrace);
      // Use fallback method if server fails
      return _getFallbackMediaInfo(filePath);
    }
  }

  /// Provides a fallback duration estimation based on file size and type
  /// This is used when the Python server is unavailable
  Future<int> _getFallbackDuration(String filePath) async {
    logInfo(_logTag, 'Using fallback duration estimation for: $filePath');
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        logError(_logTag, 'File does not exist: $filePath');
        return 0;
      }

      final fileSize = await file.length();
      final extension = p.extension(filePath).toLowerCase();

      // Estimate duration based on file type and size
      // These are rough estimates for common formats
      int estimatedDurationMs = 0;

      switch (extension) {
        case '.mp4':
        case '.mov':
        case '.avi':
        case '.mkv':
        case '.webm':
          // Rough estimate for video: ~1MB per 10 seconds at medium quality
          estimatedDurationMs = (fileSize / 1024 / 1024 * 10000).round();
          break;
        case '.mp3':
        case '.wav':
        case '.aac':
        case '.ogg':
        case '.flac':
          // Rough estimate for audio: ~1MB per minute at medium quality
          estimatedDurationMs = (fileSize / 1024 / 1024 * 60000).round();
          break;
        case '.jpg':
        case '.jpeg':
        case '.png':
        case '.gif':
        case '.bmp':
        case '.webp':
          // Default duration for images
          estimatedDurationMs = 5000;
          break;
        default:
          // Generic fallback
          estimatedDurationMs = 30000;
      }

      // Ensure we return at least 1 second for any media
      estimatedDurationMs =
          estimatedDurationMs < 1000 ? 1000 : estimatedDurationMs;

      logInfo(
        _logTag,
        'Estimated duration for $filePath: $estimatedDurationMs ms (fallback)',
      );
      return estimatedDurationMs;
    } catch (e) {
      logError(_logTag, 'Error in fallback duration estimation: $e');
      return 30000; // Default 30 seconds if all else fails
    }
  }

  /// Provides fallback media info with estimated duration and default dimensions
  Future<MediaInfo> _getFallbackMediaInfo(String filePath) async {
    logInfo(_logTag, 'Using fallback media info for: $filePath');
    final durationMs = await _getFallbackDuration(filePath);

    // Default dimensions for common video formats (720p)
    const defaultWidth = 1280;
    const defaultHeight = 720;

    final extension = p.extension(filePath).toLowerCase();

    // For images, try to get dimensions directly
    if ([
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
    ].contains(extension)) {
      try {
        // Direct file handling for images could be added here if needed
        // For now, return default dimensions
        return MediaInfo(
          durationMs: durationMs,
          width: defaultWidth,
          height: defaultHeight,
        );
      } catch (e) {
        logError(_logTag, 'Error getting image dimensions: $e');
      }
    }

    // Return default media info
    final mediaInfo = MediaInfo(
      durationMs: durationMs,
      width: defaultWidth,
      height: defaultHeight,
    );

    logInfo(_logTag, 'Fallback media info for $filePath: $mediaInfo');
    return mediaInfo;
  }
}
