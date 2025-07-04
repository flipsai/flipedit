// Simplified texture helper - no longer using texture_rgba_renderer
// This provides a basic interface for texture management without external dependencies

import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flipedit/utils/logger.dart';

class FixedTextureHelper {
  static const String _logTag = 'FixedTextureHelper';

  // Store active textures for cleanup
  static final Map<int, _ActiveTexture> _activeTextures = {};

  /// Create a simple texture ID (placeholder implementation)
  /// Returns a texture ID that can be used with Flutter's Texture widget
  static Future<int> createTexture(
    int width,
    int height,
  ) async {
    try {
      // Generate a simple texture ID
      final textureId = DateTime.now().millisecondsSinceEpoch % 1000000;

      logInfo(_logTag, 'Created texture with ID: $textureId');

      // Store the active texture info
      final activeTexture = _ActiveTexture(
        textureId: textureId,
        width: width,
        height: height,
      );

      _activeTextures[textureId] = activeTexture;

      return textureId;
    } catch (e) {
      logError(_logTag, 'Error in texture creation: $e');
      return -1;
    }
  }

  /// Update texture with new image data (placeholder implementation)
  /// In a real implementation, this would update the actual texture
  static Future<bool> updateTextureData(
    int textureId,
    Uint8List data,
    int width,
    int height,
  ) async {
    final texture = _activeTextures[textureId];

    if (texture == null) {
      logError(_logTag, 'Texture not found: $textureId');
      return false;
    }

    try {
      // Placeholder - in a real implementation, this would update the texture
      logDebug(_logTag, 'Would update texture $textureId with ${data.length} bytes');
      return true;
    } catch (e) {
      logError(_logTag, 'Error updating texture $textureId: $e');
      return false;
    }
  }

  /// Close texture and cleanup
  static Future<void> closeTexture(int textureId) async {
    final texture = _activeTextures[textureId];
    if (texture != null) {
      try {
        logInfo(_logTag, 'Closed texture $textureId');
      } catch (e) {
        logError(_logTag, 'Error closing texture $textureId: $e');
      } finally {
        _activeTextures.remove(textureId);
      }
    }
  }

  /// Get all active texture IDs (for debugging)
  static List<int> getActiveTextureIds() {
    return _activeTextures.keys.toList();
  }
}

/// Helper class to store active texture information
class _ActiveTexture {
  final int textureId;
  final int width;
  final int height;

  _ActiveTexture({
    required this.textureId,
    required this.width,
    required this.height,
  });
}

// Keep the old TextureHelper for backward compatibility, but make it use the simplified approach
@deprecated
class TextureHelper {
  static const String _logTag = 'TextureHelper';

  @deprecated
  static Future<(int textureId, int texturePtr)> createAndGetTexturePointer(
    int width,
    int height,
  ) async {
    logWarning(
      _logTag,
      'createAndGetTexturePointer is deprecated - use FixedTextureHelper.createTexture instead',
    );
    
    final textureId = await FixedTextureHelper.createTexture(width, height);
    return (textureId, 0); // Return 0 for texture pointer since we're not using it
  }

  @deprecated
  static Future<bool> updateTextureData(
    int textureId,
    Uint8List data,
    int width,
    int height,
  ) async {
    logWarning(
      _logTag,
      'TextureHelper.updateTextureData is deprecated - use FixedTextureHelper.updateTextureData instead',
    );
    
    return FixedTextureHelper.updateTextureData(textureId, data, width, height);
  }

  @deprecated
  static Future<void> closeTexture(int textureId) async {
    logWarning(
      _logTag,
      'TextureHelper.closeTexture is deprecated - use FixedTextureHelper.closeTexture instead',
    );
    
    await FixedTextureHelper.closeTexture(textureId);
  }

  @deprecated
  static List<int> getActiveTextureIds() {
    logWarning(
      _logTag,
      'TextureHelper.getActiveTextureIds is deprecated - use FixedTextureHelper.getActiveTextureIds instead',
    );
    
    return FixedTextureHelper.getActiveTextureIds();
  }
}
