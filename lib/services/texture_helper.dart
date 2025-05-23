// Fixed approach - don't try to get texture pointers for Python FFI
// Instead, use the texture plugin purely for Flutter rendering

import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';

class FixedTextureHelper {
  static const String _logTag = 'FixedTextureHelper';

  // Store active textures for cleanup
  static final Map<int, _ActiveTexture> _activeTextures = {};

  /// Create a texture and return only the textureId for Flutter Texture widget
  /// Don't try to get native pointers - that's not needed for Flutter rendering
  static Future<int> createTexture(
    TextureRgbaRenderer renderer,
    int width,
    int height,
  ) async {
    try {
      // Generate a unique key - timestamp is fine for this
      final textureKey = DateTime.now().millisecondsSinceEpoch;

      // Create the texture
      final textureId = await renderer.createTexture(textureKey);

      if (textureId == -1) {
        logError(_logTag, 'Failed to create texture with key: $textureKey');
        return -1;
      }

      logInfo(_logTag, 'Created texture with ID: $textureId');

      // Store the active texture info
      final activeTexture = _ActiveTexture(
        textureId: textureId,
        textureKey: textureKey,
        renderer: renderer,
        width: width,
        height: height,
      );

      _activeTextures[textureId] = activeTexture;

      // Initialize with solid color
      await _initializeTexture(activeTexture, width, height);

      return textureId; // Return only textureId, no pointer needed
    } catch (e) {
      logError(_logTag, 'Error in texture creation: $e');
      return -1;
    }
  }

  /// Initialize texture with black frame (waiting for actual data)
  static Future<void> _initializeTexture(
    _ActiveTexture texture,
    int width,
    int height,
  ) async {
    final bytesPerPixel = 4; // RGBA
    final totalBytes = width * height * bytesPerPixel;
    final pixels = Uint8List(totalBytes);

    // Create a black frame with loading text
    // Fill with black (all zeros is already black)

    // For better visual feedback, create a simple loading pattern
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final offset = (y * width + x) * bytesPerPixel;

        // Create a subtle dark gray background with a loading indicator
        final centerX = width ~/ 2;
        final centerY = height ~/ 2;
        final distanceFromCenter = sqrt(
          (x - centerX) * (x - centerX) + (y - centerY) * (y - centerY),
        );

        if (distanceFromCenter < 50) {
          // Small loading circle in the center
          pixels[offset] = 64; // R - dark gray
          pixels[offset + 1] = 64; // G
          pixels[offset + 2] = 64; // B
          pixels[offset + 3] = 255; // A
        } else {
          // Black background
          pixels[offset] = 0; // R
          pixels[offset + 1] = 0; // G
          pixels[offset + 2] = 0; // B
          pixels[offset + 3] = 255; // A
        }
      }
    }

    // Update the texture
    final result = await texture.renderer.onRgba(
      texture.textureKey,
      pixels,
      width,
      height,
      4,
    );

    if (!result) {
      logError(
        _logTag,
        'Failed to initialize texture data for ID: ${texture.textureId}',
      );
    } else {
      logInfo(
        _logTag,
        'Successfully initialized texture ${texture.textureId} with loading indicator',
      );
    }
  }

  /// Update texture with new image data
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
      final result = await texture.renderer.onRgba(
        texture.textureKey,
        data,
        width,
        height,
        4,
      );

      if (result) {
        logDebug(_logTag, 'Updated texture $textureId successfully');
      } else {
        logError(_logTag, 'Failed to update texture $textureId');
      }

      return result;
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
        await texture.renderer.closeTexture(texture.textureKey);
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
  final int textureKey;
  final TextureRgbaRenderer renderer;
  final int width;
  final int height;

  _ActiveTexture({
    required this.textureId,
    required this.textureKey,
    required this.renderer,
    required this.width,
    required this.height,
  });
}

// Keep the old TextureHelper for backward compatibility, but make it use the fixed approach
@deprecated
class TextureHelper {
  static const String _logTag = 'TextureHelper';

  @deprecated
  static Future<(int textureId, int texturePtr)> createAndGetTexturePointer(
    TextureRgbaRenderer renderer,
    int width,
    int height,
  ) async {
    logInfo(
      _logTag,
      'WARNING: Using deprecated createAndGetTexturePointer. Use FixedTextureHelper.createTexture instead.',
    );

    final textureId = await FixedTextureHelper.createTexture(
      renderer,
      width,
      height,
    );
    if (textureId == -1) {
      return (-1, 0);
    }

    // Return textureId but 0 for pointer (since we don't need pointers anymore)
    logInfo(
      _logTag,
      'Created texture $textureId (pointer approach deprecated)',
    );
    return (textureId, 0);
  }

  @deprecated
  static Future<void> updateTextureData(
    int textureId,
    Uint8List data,
    int width,
    int height,
  ) async {
    logInfo(
      _logTag,
      'WARNING: Using deprecated TextureHelper.updateTextureData. Use FixedTextureHelper.updateTextureData instead.',
    );
    await FixedTextureHelper.updateTextureData(textureId, data, width, height);
  }
}
