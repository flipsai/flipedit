part of '../mdk_player_service.dart';

class MdkTextureManager {
  final MdkPlayerService _service;
  final String _logTag;

  MdkTextureManager(this._service) : _logTag = '${_service._logTag}_TextureManager';

  /// Sets the video surface size. Returns true on success.
  bool setVideoSurfaceSize(int width, int height) {
    if (_service._player == null || width <= 0 || height <= 0) return false;
    logger.logInfo('Setting video surface size to ${width}x$height', _logTag);
    try {
       _service._player!.setVideoSurfaceSize(width, height);
       return true;
    } catch (e, stack) {
       logger.logError('Error setting video surface size: $e\n$stack', _logTag);
       return false;
    }
  }

  /// Updates the texture. Returns the new texture ID or -1 on failure.
  /// Assumes the player is already in the correct state (e.g., paused at the desired frame).
  Future<int> updateTexture({required int width, required int height}) async {
    if (_service._player == null || width <= 0 || height <= 0) {
      logger.logWarning('Cannot update texture, player is null or dimensions invalid ($width x $height).', _logTag);
      if (_service.textureIdNotifier.value != -1) _service.textureIdNotifier.value = -1;
      return -1;
    }

    try {
      final newTextureId = await _service._player!.updateTexture(width: width, height: height);
      logger.logInfo('updateTexture called. Result: $newTextureId', _logTag);

      if (newTextureId > 0) {
        if (_service.textureIdNotifier.value != newTextureId) {
          _service.textureIdNotifier.value = newTextureId;
          logger.logInfo('Texture ID updated via updateTexture: $newTextureId', _logTag);
        }
      } else if (newTextureId <= 0 && _service.textureIdNotifier.value != -1) {
        logger.logWarning('updateTexture returned invalid ID ($newTextureId), resetting.', _logTag);
        _service.textureIdNotifier.value = -1;
      }
      return newTextureId;
    } catch (e, stack) {
      logger.logError('Error updating texture: $e\n$stack', _logTag);
      _service.textureIdNotifier.value = -1; // Reset on error
      return -1;
    }
  }

  /// Handles player events, specifically looking for texture updates.
  void onPlayerEvent(event) { // Reverted to type inference
    logger.logDebug('Player event received: ${event.category} - ${event.detail}', _logTag);

    if (event.category == "video.renderer" || event.category == "render.video") {
      final textureIdObject = _service._player?.textureId;
      try {
        if (textureIdObject is int) {
          final int textureIdValue = textureIdObject as int; // Added explicit cast
          if (textureIdValue > 0 && textureIdValue != _service.textureIdNotifier.value) {
            _service.textureIdNotifier.value = textureIdValue;
            logger.logInfo('Texture ID updated via event: $textureIdValue', _logTag);
          } else if (textureIdValue <= 0 && _service.textureIdNotifier.value != -1) {
            logger.logWarning('Received invalid texture ID ($textureIdValue) via event, resetting.', _logTag);
            _service.textureIdNotifier.value = -1;
          }
        } else if (textureIdObject != null) {
          logger.logWarning('Received non-integer texture ID via event: $textureIdObject (${textureIdObject.runtimeType})', _logTag);
        } else if (_service.textureIdNotifier.value != -1) {
          logger.logWarning('Received null texture ID via event, resetting.', _logTag);
          _service.textureIdNotifier.value = -1;
        }
      } catch (e, stack) {
        logger.logError('Error processing texture ID event ($textureIdObject): $e\n$stack', _logTag);
        logger.logWarning('Received null texture ID via event, resetting.', _logTag);
        _service.textureIdNotifier.value = -1;
      }
    }
  }
}