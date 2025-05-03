import 'dart:convert';
import 'package:flipedit/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

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
  String toString() => 'MediaInfo(durationMs: $durationMs, width: $width, height: $height)';
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
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logError(_logTag, 'Request timed out for: $filePath');
          throw Exception('Request timed out');
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
        return 0;
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media duration: $e', stackTrace);
      return 0;
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
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logError(_logTag, 'Request timed out for: $filePath');
          throw Exception('Request timed out');
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
        return MediaInfo(durationMs: 0, width: 0, height: 0);
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media info: $e', stackTrace);
      return MediaInfo(durationMs: 0, width: 0, height: 0);
    }
  }
} 