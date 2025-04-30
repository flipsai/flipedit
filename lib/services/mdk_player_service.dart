import 'dart:async';
import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter/foundation.dart';
import 'package:flipedit/utils/logger.dart' as logger;

part 'mdk_player_service/error_handler.dart';
part 'mdk_player_service/texture_manager.dart';
part 'mdk_player_service/media_status_monitor.dart';

/// Service responsible for managing the MDK Player instance.
class MdkPlayerService {
  final String _logTag = 'MdkPlayerService';

  mdk.Player? _player;
  mdk.Player? get player => _player;

  final ValueNotifier<int> textureIdNotifier = ValueNotifier<int>(-1);
  int get textureId => textureIdNotifier.value;

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isPlayerReadyNotifier = ValueNotifier(false);

  // Helper instances
  late final _errorHandler = MdkPlayerErrorHandler(this);
  late final _textureManager = MdkTextureManager(this);
  late final _mediaStatusMonitor = MdkMediaStatusMonitor(this);

  MdkPlayerService() {
    _initPlayer();
  }

  void _initPlayer() {
    try {
      logger.logInfo('Initializing MDK player...', _logTag);

      // Dispose previous player if it exists
      if (_player != null) {
        logger.logInfo('Disposing previous player instance', _logTag);
        try {
          _player?.dispose();
        } catch (e) {
          logger.logError('Error disposing previous player: $e', _logTag);
        }
        _player = null;
      }

      // Reset notifiers and cancel waits
      textureIdNotifier.value = -1;
      isPlayerReadyNotifier.value = false;
      isPlayingNotifier.value = false;
      _mediaStatusMonitor.cancelWaits();

      try {
        _player = mdk.Player();
        logger.logInfo('Player instance created', _logTag);
        _setupPlayerListeners();
        _errorHandler.resetErrorState();
      } catch (e, stack) {
        logger.logError('Failed to create MDK player: $e\n$stack', _logTag);
        _errorHandler.handlePlayerCreationError();
        _player = null;
        isPlayerReadyNotifier.value = false;
      }
    } catch (e, stackTrace) {
      logger.logError('Unexpected error during player initialization: $e\n$stackTrace', _logTag);
      _errorHandler.handlePlayerCreationError();
      _player = null;
      isPlayerReadyNotifier.value = false;
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) return;
    
    // State change listener
    _player!.onStateChanged((oldState, newState) {
      if (_player == null) return;
      isPlayingNotifier.value = newState == mdk.PlaybackState.playing;
      
      if (newState == mdk.PlaybackState.paused || newState == mdk.PlaybackState.playing) {
        // Readiness is now primarily determined by prepareFrameForDisplay success
      } else if (newState == mdk.PlaybackState.stopped || newState == mdk.PlaybackState.notRunning) {
        isPlayerReadyNotifier.value = false; // Mark as not ready if stopped/not running
      }
      logger.logInfo('Player state changed: $oldState -> $newState. Ready: ${isPlayerReadyNotifier.value}', _logTag);
    });

    // Media status listener - delegate to monitor
    _player!.onMediaStatus(_mediaStatusMonitor.onMediaStatusChanged);
    
    // Event listener for texture updates - delegate to manager
    _player!.onEvent(_textureManager.onPlayerEvent);

    logger.logInfo('MDK player listeners set up', _logTag);
  }

  /// Attempts to load and prepare media. Returns true if prepare() is called successfully.
  /// Readiness for display is handled by prepareFrameForDisplay.
  Future<bool> setAndPrepareMedia(String mediaPath, {mdk.MediaType type = mdk.MediaType.video}) async {
    if (_errorHandler.isRecovering) {
      logger.logWarning('Cannot set media while recovering from player errors.', _logTag);
      return false;
    }
    if (_player == null) {
      logger.logWarning('Player not initialized, attempting reinitialization before setting media.', _logTag);
      _initPlayer(); // Try to init if null
      // Consider a short delay or a completer pattern if init is async
      await Future.delayed(const Duration(milliseconds: 50)); 
      if (_player == null) {
        logger.logError('Player still null after reinitialization attempt. Cannot set media.', _logTag);
        return false;
      }
    }

    logger.logInfo('Setting media to: $mediaPath', _logTag);
    // Reset readiness flags immediately
    isPlayerReadyNotifier.value = false;
    textureIdNotifier.value = -1;
    _mediaStatusMonitor.cancelWaits(); // Cancel any pending waits for previous media

    try {
      _player!.setMedia(mediaPath, type);
      // Short delay might help ensure the player processes the setMedia call before prepare
      await Future.delayed(const Duration(milliseconds: 20)); 
      _player!.prepare(); // Asynchronous prepare call
      logger.logInfo('prepare() called for $mediaPath.', _logTag);
      // We don't wait for completion here. Success means the call didn't throw.
      // Actual readiness is determined after prepareFrameForDisplay.
      return true;
    } catch (e, stack) {
      _errorHandler.handleMediaError(mediaPath, e, stack);
      return false;
    }
  }


  /// Clears the current media from the player.
  Future<void> clearMedia() async {
      if (_player == null) return;

      try {
          final currentStatus = _player!.mediaStatus;

          // Only call setMedia if there might be valid media loaded
          if (!currentStatus.test(mdk.MediaStatus.noMedia) && !currentStatus.test(mdk.MediaStatus.invalid)) {
              _player!.setMedia('', mdk.MediaType.unknown); // Set empty path
              // Consider a small delay for the player to process
              await Future.delayed(const Duration(milliseconds: 20));
          }

          // Ensure player is stopped
          if (_player!.state != mdk.PlaybackState.stopped) {
             _player!.state = mdk.PlaybackState.stopped; // Explicitly stop
             await Future.delayed(const Duration(milliseconds: 20));
          }

          textureIdNotifier.value = -1; // Reset texture ID
          isPlayerReadyNotifier.value = false; // Mark as not ready
          _mediaStatusMonitor.cancelWaits(); // Cancel status waits
      } catch(e, stack) {
           logger.logError('Error during clearMedia operation: $e\n$stack', _logTag);
           // Attempt reinitialization on error during clear
           _initPlayer();
      }
  }

  /// Sets the video surface size. Returns true on success.
  bool setVideoSurfaceSize(int width, int height) {
    return _textureManager.setVideoSurfaceSize(width, height);
  }

  /// Updates the texture. Returns the new texture ID or -1 on failure.
  Future<int> updateTexture({required int width, required int height}) async {
    return _textureManager.updateTexture(width: width, height: height);
  }

  /// Finalizes player setup for displaying a specific frame.
  /// Assumes setAndPrepareMedia was called successfully before this.
  /// Returns true if the player is ready with a valid texture ID.
  Future<bool> prepareFrameForDisplay() async {
      if (_player == null) {
          logger.logError('Cannot prepare frame for display, player is null.', _logTag);
          isPlayerReadyNotifier.value = false;
          return false;
      }

      logger.logInfo('Preparing frame for display...', _logTag);
      isPlayerReadyNotifier.value = false; // Reset readiness until confirmed

      try {
           // 1. Wait for Prepared Status
           bool isPrepared = await _mediaStatusMonitor.waitForPreparedStatus(timeoutMs: 2000);
           if (!isPrepared) {
              logger.logError('Player did not reach prepared status.', _logTag);
              await clearMedia(); // Attempt cleanup
              return false;
           }
           logger.logInfo('Player status is Prepared.', _logTag);

           // 2. Get Dimensions
           final videoInfo = _player!.mediaInfo.video?.firstOrNull?.codec;
           final width = videoInfo?.width;
           final height = videoInfo?.height;
           if (width == null || height == null || width <= 0 || height <= 0) {
               logger.logError('Could not get valid dimensions from loaded media: ${width}x$height', _logTag);
               await clearMedia();
               return false;
           }
            logger.logInfo('Got video dimensions: ${width}x$height.', _logTag);

           // 3. Set Surface Size
           if (!_textureManager.setVideoSurfaceSize(width, height)) {
               logger.logError('Failed to set video surface size.', _logTag);
               await clearMedia();
               return false;
           }
            logger.logInfo('Video surface size set.', _logTag);

           // 4. Seek to Start and Pause
           bool seekOk = await seek(0, pauseAfterSeek: true);
           if (!seekOk) {
               logger.logError('Failed to seek to 0 or pause.', _logTag);
               await clearMedia();
               return false;
           }
           logger.logInfo('Seek to 0 and pause successful.', _logTag);

           // 5. Update Texture
           final newTextureId = await _textureManager.updateTexture(width: width, height: height);
           if (newTextureId <= 0) {
               logger.logError('Failed to get valid texture ID after preparation.', _logTag);
               await clearMedia();
               return false;
           }
            logger.logInfo('Texture ID updated successfully: $newTextureId.', _logTag);

           // 6. Mark as Ready
           logger.logInfo('Frame prepared successfully for display.', _logTag);
           isPlayerReadyNotifier.value = true;
           return true;

      } catch (e, stack) {
           logger.logError('Error during prepareFrameForDisplay: $e\n$stack', _logTag);
           isPlayerReadyNotifier.value = false;
           await clearMedia();
           return false;
      }
  }


  /// Check if player is in a state where it can render (ready notifier is true)
  bool isPlayerEffectivelyReady() {
     // Rely solely on the notifier set by prepareFrameForDisplay
     return _player != null && isPlayerReadyNotifier.value;
  }


  Future<void> play() async {
     // Playing a single frame doesn't make sense. Log a warning or make this a no-op.
     logger.logWarning('Attempted to play a single composite frame. Operation ignored.', _logTag);
     // Ensure player remains paused
     await pause();
  }

  Future<void> pause() async {
    if (_player == null) return;
    try {
        if (_player!.state != mdk.PlaybackState.paused) {
            logger.logInfo('Setting player state to paused.', _logTag);
            _player!.state = mdk.PlaybackState.paused;
            // Allow state change to propagate
            await Future.delayed(const Duration(milliseconds: 50)); 
        }
    } catch (e, stack) {
         logger.logError('Error pausing player: $e\n$stack', _logTag);
    }
  }

  /// Seeks within the media. Returns true on success (seek command issued).
  Future<bool> seek(int timeMs, {bool pauseAfterSeek = true}) async {
    if (_player == null || _player!.mediaStatus.test(mdk.MediaStatus.noMedia) || _player!.mediaStatus.test(mdk.MediaStatus.invalid)) {
      logger.logWarning('Cannot seek, player is null or media not valid/loaded. Status: ${_player?.mediaStatus}', _logTag);
      return false;
    }

    logger.logInfo('Seeking to ${timeMs}ms. Pause after seek: $pauseAfterSeek', _logTag);
    try {
      // Pause before seeking if requested for precision
      if (pauseAfterSeek && _player!.state != mdk.PlaybackState.paused) {
        await pause(); // Uses the service's pause method with its delay
      }

      final mdk.SeekFlag seekFlags = mdk.SeekFlag(mdk.SeekFlag.keyFrame);
      _player!.seek(position: timeMs, flags: seekFlags);
      logger.logDebug('Seek command issued to ${timeMs}ms.', _logTag);

      // The original code had a fixed delay here because seek completion wasn't detectable.
      // This remains a limitation of the underlying MDK library binding if it lacks callbacks/futures for seek.
      // We keep the delay, but acknowledge it's not ideal.
      await Future.delayed(const Duration(milliseconds: 200)); 
      logger.logDebug('Post-seek delay completed.', _logTag);

      // Ensure pause state if requested
      if (pauseAfterSeek) {
         // Small delay *before* checking/setting pause state again, allows player to settle after seek
         await Future.delayed(const Duration(milliseconds: 30));
         if (_player != null && _player!.state != mdk.PlaybackState.paused) {
            await pause(); // Use service pause again
         }
      }

      return true; // Assume success if no exception during seek call

    } catch (e, stack) {
      logger.logError('Error seeking to $timeMs: $e\n$stack', _logTag);
      return false;
    }
  }

  /// Updates the texture after a seek operation completes.
  /// Assumes the player is prepared and seek completed successfully.
  /// Returns true if the texture was updated successfully.
  Future<bool> updateTextureAfterSeek() async {
    if (_player == null) {
        logger.logError('Cannot update texture, player is null.', _logTag);
        isPlayerReadyNotifier.value = false;
        return false;
    }
    if (!(_player!.mediaStatus.test(mdk.MediaStatus.loaded) || _player!.mediaStatus.test(mdk.MediaStatus.prepared))) {
        logger.logWarning('Player not in loaded/prepared state, cannot reliably update texture after seek.', _logTag);
        // Don't necessarily fail here, but proceed with caution
    }

    logger.logInfo('Updating texture after seek...', _logTag);
    // isPlayerReadyNotifier.value = false; // Don't reset readiness here if seek was ok

    try {
        // 1. Get Dimensions
        final videoInfo = _player!.mediaInfo.video?.firstOrNull?.codec;
        final width = videoInfo?.width;
        final height = videoInfo?.height;
        if (width == null || height == null || width <= 0 || height <= 0) {
            logger.logError('Could not get valid dimensions from media after seek: ${width}x$height', _logTag);
            isPlayerReadyNotifier.value = false;
            // await clearMedia(); // Avoid potentially problematic clearMedia
            return false;
        }
        logger.logVerbose('Got video dimensions for texture update: ${width}x$height.', _logTag);

        // 2. Set Surface Size (might be redundant if unchanged, but safe to call)
        if (!_textureManager.setVideoSurfaceSize(width, height)) {
            logger.logError('Failed to set video surface size for texture update.', _logTag);
            isPlayerReadyNotifier.value = false;
            // await clearMedia();
            return false;
        }
        logger.logVerbose('Video surface size set for texture update.', _logTag);

        // 3. Update Texture
        final newTextureId = await _textureManager.updateTexture(width: width, height: height);
        if (newTextureId <= 0) {
            logger.logError('Failed to get valid texture ID after seek.', _logTag);
            isPlayerReadyNotifier.value = false;
            // await clearMedia();
            return false;
        }
        logger.logInfo('Texture updated successfully after seek. New ID: $newTextureId.', _logTag);

        // 4. Mark as Ready
        isPlayerReadyNotifier.value = true;
        return true;

    } catch (e, stack) {
        logger.logError('Error during updateTextureAfterSeek: $e\n$stack', _logTag);
        isPlayerReadyNotifier.value = false;
        // await clearMedia();
        return false;
    }
  }

  void dispose() {
    logger.logInfo('Disposing MdkPlayerService.', _logTag);
    _mediaStatusMonitor.cancelWaits(); // Cancel any pending waits
    try {
      _player?.dispose();
    } catch (e) {
       logger.logError('Error disposing player during service disposal: $e', _logTag);
    }
    _player = null;
    textureIdNotifier.dispose();
    isPlayingNotifier.dispose();
    isPlayerReadyNotifier.dispose();
  }
}