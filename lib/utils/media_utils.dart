import 'package:fvp/mdk.dart' as mdk;

import 'dart:io';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
/// Simple class to represent dimensions
class MediaDimensions {
  final int width;
  final int height;
  
  MediaDimensions(this.width, this.height);
}

/// Utility class for handling media files
class MediaUtils {
  static const String _logTag = 'MediaUtils';
  
  /// Get the duration of a media file (video or audio)
  /// Returns null if duration cannot be determined
  static Duration? getMediaDuration(String filePath) {
    try {
      final player = mdk.Player();
      
      // Use setMedia to open the file
      if (_isVideoFile(filePath)) {
        player.setMedia(filePath, mdk.MediaType.video);
      } else if (_isAudioFile(filePath)) {
        player.setMedia(filePath, mdk.MediaType.audio);
      } else {
        // Unsupported file type
        player.dispose();
        return null;
      }
      
      // Prepare the player to get media info
      player.prepare();
      
      // Wait for the player to be initialized so mediaInfo is available
      // Timeout after 5 seconds in case of issues
      final initialized = player.waitFor(mdk.PlaybackState.paused, timeout: 5000);
      
      if (!initialized) {
        logWarning(_logTag, "Failed to initialize player for duration extraction: $filePath");
        player.dispose();
        return null;
      }
      
      // Get the duration in milliseconds
      final durationMs = player.mediaInfo.duration;
      
      // Dispose the player
      player.dispose();
      
      // Return the duration as a Duration object
      return Duration(milliseconds: durationMs);
    } catch (e) {
      logError(_logTag, "Error getting media duration for $filePath: $e");
      return null;
    }
  }
  
  /// Get dimensions of a video file
  /// Returns null if dimensions cannot be determined
  static Future<MediaDimensions?> getVideoDimensions(String filePath) async {
    try {
      // This is a placeholder implementation
      // TODO: Implement proper video dimension extraction
      logWarning(_logTag, "Video dimension extraction not fully implemented, using placeholder");
      return MediaDimensions(1920, 1080);
    } catch (e) {
      logError(_logTag, "Error getting video dimensions: $e");
      return null;
    }
  }
  
  /// Get dimensions of an image file
  /// Returns null if dimensions cannot be determined
  static Future<MediaDimensions?> getImageDimensions(String filePath) async {
    try {
      // This is a placeholder implementation
      // TODO: Implement proper image dimension extraction
      logWarning(_logTag, "Image dimension extraction not fully implemented, using placeholder");
      return MediaDimensions(1280, 720);
    } catch (e) {
      logError(_logTag, "Error getting image dimensions: $e");
      return null;
    }
  }
  
  /// Generate a thumbnail for a media file
  /// Returns the path to the generated thumbnail, or null if generation failed
  static Future<String?> generateThumbnail(String filePath, ClipType type) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = p.basenameWithoutExtension(filePath);
      final thumbnailPath = p.join(tempDir.path, 'thumbnails', '$fileName.jpg');
      
      // Create thumbnails directory if it doesn't exist
      final thumbnailDir = Directory(p.dirname(thumbnailPath));
      if (!await thumbnailDir.exists()) {
        await thumbnailDir.create(recursive: true);
      }
      
      // This is a simplified implementation that doesn't actually
      // generate thumbnails yet, but returns a placeholder path
      // TODO: Implement proper thumbnail generation
      logWarning(_logTag, "Thumbnail generation not fully implemented");
      
      if (type == ClipType.video || type == ClipType.image) {
        // For videos and images, we would create thumbnails
        // Return a placeholder path for now
        return thumbnailPath;
      }
      
      // For audio, we could use a generic audio icon
      // Or return null to indicate no thumbnail
      return null;
    } catch (e) {
      logError(_logTag, "Error generating thumbnail: $e");
      return null;
    }
  }
  
  /// Check if a file is a video based on its extension
  static bool _isVideoFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(extension);
  }
  
  /// Check if a file is an audio based on its extension
  static bool _isAudioFile(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    return ['.mp3', '.wav', '.aac', '.ogg', '.flac'].contains(extension);
  }
} 