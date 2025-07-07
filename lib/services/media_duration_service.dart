import 'dart:async';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/src/rust/api/simple.dart';

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

/// Service for retrieving media durations using GStreamer via Rust
class MediaDurationService {
  static const _logTag = 'MediaDurationService';

  MediaDurationService();

  /// Get the duration of a media file in milliseconds using GStreamer
  /// This replaces the old Python server + fallback estimation approach
  Future<int> getMediaDurationMs(String filePath) async {
    try {
      logInfo(_logTag, 'Getting duration for: $filePath using GStreamer');
      
      // Call the Rust GStreamer-based duration function
      final durationMs = await getVideoDurationMs(filePath: filePath);
      
      logInfo(_logTag, 'Duration for $filePath: $durationMs ms (GStreamer)');
      return durationMs.toInt();
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media duration with GStreamer: $e', stackTrace);
      return 0; // Return 0 if duration cannot be determined
    }
  }

  /// Get both duration and dimensions of a media file
  /// Returns MediaInfo with zeros if the info cannot be determined
  Future<MediaInfo> getMediaInfo(String filePath) async {
    try {
      logInfo(_logTag, 'Getting media info for: $filePath using GStreamer');
      
      // Get duration using GStreamer
      final durationMs = await getMediaDurationMs(filePath);
      
      // For now, use default dimensions (could be extended to get actual dimensions via GStreamer)
      const defaultWidth = 1280;
      const defaultHeight = 720;
      
      final mediaInfo = MediaInfo(
        durationMs: durationMs,
        width: defaultWidth,
        height: defaultHeight,
      );
      
      logInfo(_logTag, 'Media info for $filePath: $mediaInfo');
      return mediaInfo;
    } catch (e, stackTrace) {
      logError(_logTag, 'Failed to get media info: $e', stackTrace);
      // Return default values if everything fails
      return MediaInfo(
        durationMs: 0,
        width: 1280,
        height: 720,
      );
    }
  }

}
