import 'dart:async';
import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter/foundation.dart';
import 'package:flipedit/utils/logger.dart' as logger;

/// Service responsible for managing the MDK Player instance.
class MdkPlayerService {
  final String _logTag = 'MdkPlayerService';

  mdk.Player? _player;
  mdk.Player? get player => _player;

  final ValueNotifier<int> textureIdNotifier = ValueNotifier<int>(-1);
  int get textureId => textureIdNotifier.value;

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isPlayerReadyNotifier = ValueNotifier(false); // Indicates if player is ready after prepare

  // Error handling and recovery for player initialization
  bool _isRecoveringFromError = false;
  int _consecutiveErrorCount = 0;
  final int _maxConsecutiveErrors = 3;
  DateTime? _lastErrorTime;

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

      // Reset notifiers
      textureIdNotifier.value = -1;
      isPlayerReadyNotifier.value = false;
      isPlayingNotifier.value = false;

      try {
        _player = mdk.Player();
        logger.logInfo('Player instance created', _logTag);
        _setupPlayerListeners();
        _resetErrorState(); // Reset error state on successful creation
      } catch (e, stack) {
        logger.logError('Failed to create MDK player: $e\n$stack', _logTag);
        _handlePlayerCreationError();
        _player = null; // Ensure player is null on failure
        isPlayerReadyNotifier.value = false; // Ensure not ready on failure
      }
    } catch (e, stackTrace) {
      logger.logError('Unexpected error during player initialization: $e\n$stackTrace', _logTag);
      _handlePlayerCreationError(); // Handle generic init errors too
      _player = null;
      isPlayerReadyNotifier.value = false;
    }
  }

  void _setupPlayerListeners() {
     if (_player == null) return;
    // Use callback for state changes
    _player!.onStateChanged((oldState, newState) {
       if (_player == null) return; // Check again inside callback
      isPlayingNotifier.value = newState == mdk.PlaybackState.playing;
      // Update ready state based on transitions (e.g., paused after prepare)
      if (newState == mdk.PlaybackState.paused || newState == mdk.PlaybackState.playing) {
          if (!isPlayerReadyNotifier.value) {
             isPlayerReadyNotifier.value = true;
             logger.logInfo('Player is now ready (state: $newState)', _logTag);
          }
      } else if (newState == mdk.PlaybackState.stopped || newState == mdk.PlaybackState.notRunning) {
          isPlayerReadyNotifier.value = false; // Mark as not ready if stopped
      }
      logger.logInfo('Player state changed: $oldState -> $newState. Ready: ${isPlayerReadyNotifier.value}', _logTag);
    });

    // Subscribe to media status events
    _player!.onMediaStatus((oldStatus, newStatus) {
      logger.logInfo('Media status changed: $oldStatus -> $newStatus', _logTag);
      // Potentially update readiness based on status like buffering, prepared etc.
      if (newStatus.test(mdk.MediaStatus.loaded) || newStatus.test(mdk.MediaStatus.prepared)) {
          if (!isPlayerReadyNotifier.value && _player?.state == mdk.PlaybackState.paused) {
             isPlayerReadyNotifier.value = true;
             logger.logInfo('Player is now ready (status: $newStatus, state: ${_player?.state})', _logTag);
          }
      } else if (newStatus.test(mdk.MediaStatus.invalid) || newStatus.test(mdk.MediaStatus.noMedia)) {
           isPlayerReadyNotifier.value = false;
           logger.logWarning('Player media became invalid or no media. Ready: false', _logTag);
      }
      return true;
    });

    // Monitor texture ID changes through events
    _player!.onEvent((event) {
      logger.logDebug('Player event received: ${event.category} - ${event.detail}', _logTag);

      if (event.category == "video.renderer" || event.category == "render.video") { // Check both possible categories
          // Use textureId getter which might be more reliable than updateTexture result
          final textureIdObject = _player?.textureId; // This is Object?
          try { // Add try-catch for safety with 'as int'
            if (textureIdObject is int) {
                final int textureIdValue = textureIdObject as int; // Try direct cast
                if (textureIdValue > 0 && textureIdValue != textureIdNotifier.value) {
                  textureIdNotifier.value = textureIdValue;
                  logger.logInfo('Texture ID updated via event: $textureIdValue', _logTag);
                } else if (textureIdValue <= 0 && textureIdNotifier.value != -1) {
                  // Potentially reset if texture becomes invalid
                  logger.logWarning('Received invalid texture ID ($textureIdValue) via event, resetting.', _logTag);
                  textureIdNotifier.value = -1;
                }
            } else if (textureIdObject != null) { // Use textureIdObject here
                logger.logWarning('Received non-integer texture ID via event: $textureIdObject (${textureIdObject.runtimeType})', _logTag);
            } else if (textureIdNotifier.value != -1) {
                // Handle null case if texture was previously valid
                logger.logWarning('Received null texture ID via event, resetting.', _logTag);
                textureIdNotifier.value = -1;
            }
          } catch (e, stack) {
             logger.logError('Error processing texture ID event ($textureIdObject): $e\n$stack', _logTag);
               logger.logWarning('Received null texture ID via event, resetting.', _logTag);
               textureIdNotifier.value = -1;
          }
      }
    });

    logger.logInfo('MDK player listeners set up', _logTag);
  }

  void _resetErrorState() {
    _consecutiveErrorCount = 0;
    _lastErrorTime = null;
    _isRecoveringFromError = false;
     logger.logInfo('Player error state reset.', _logTag);
  }

  void _handlePlayerCreationError() {
    final now = DateTime.now();
    if (_lastErrorTime != null) {
      final timeSinceLastError = now.difference(_lastErrorTime!);
      if (timeSinceLastError.inSeconds < 10) {
        _consecutiveErrorCount++;
      } else {
        _consecutiveErrorCount = 1;
      }
    } else {
      _consecutiveErrorCount = 1;
    }
    _lastErrorTime = now;
    logger.logWarning('Player creation error count: $_consecutiveErrorCount', _logTag);

    if (_consecutiveErrorCount >= _maxConsecutiveErrors) {
      logger.logError('Too many consecutive player initialization errors, backing off', _logTag);
      _isRecoveringFromError = true;
      isPlayerReadyNotifier.value = false; // Ensure not ready during backoff
      // Schedule recovery attempt
      Future.delayed(const Duration(seconds: 5), () {
        logger.logInfo('Attempting to recover player after backoff...', _logTag);
        _isRecoveringFromError = false;
        _consecutiveErrorCount = 0; // Reset count before retrying
        _initPlayer(); // Try initializing again
      });
    } else {
        // Optionally schedule a retry sooner if not backing off
        Future.delayed(const Duration(milliseconds: 500), () {
             if (_player == null && !_isRecoveringFromError) { // Only retry if still null and not backing off
                logger.logInfo('Retrying player initialization shortly...', _logTag);
                _initPlayer();
             }
        });
    }
  }

  /// Attempts to load and prepare media. Returns true if successful.
  Future<bool> setAndPrepareMedia(String mediaPath, {mdk.MediaType type = mdk.MediaType.video}) async {
     if (_isRecoveringFromError) {
       logger.logWarning('Cannot set media while recovering from player errors.', _logTag);
       return false;
     }
     if (_player == null) {
      logger.logWarning('Player not initialized, attempting reinitialization before setting media.', _logTag);
      _initPlayer(); // Try to init if null
      await Future.delayed(const Duration(milliseconds: 100)); // Short delay for init attempt
      if (_player == null) {
          logger.logError('Player still null after reinitialization attempt. Cannot set media.', _logTag);
          return false;
      }
    }

    logger.logInfo('Setting media to: $mediaPath', _logTag);
    isPlayerReadyNotifier.value = false; // Mark as not ready until prepared
    try {
      _player!.setMedia(mediaPath, type);
      _player!.prepare(); // Asynchronous prepare

      // Wait for prepared state (or paused/playing which imply prepared)
      bool prepared = await _waitForStates([mdk.PlaybackState.paused, mdk.PlaybackState.playing], timeoutMs: 2000);

      if (prepared) {
         logger.logInfo('Player prepared successfully for $mediaPath. State: ${_player?.state}', _logTag);
         // isPlayerReadyNotifier should be set by state/status listeners now
         return isPlayerReadyNotifier.value;
      } else {
         logger.logError('Player failed to reach prepared state (paused/playing) within timeout for $mediaPath. Current state: ${_player?.state}', _logTag);
         isPlayerReadyNotifier.value = false;
         // Attempt to clear media or reinitialize on failure
         clearMedia();
         _initPlayer();
         return false;
      }
    } catch (e, stack) {
      logger.logError('Error setting or preparing media $mediaPath: $e\n$stack', _logTag);
      isPlayerReadyNotifier.value = false;
      // Attempt recovery
       clearMedia();
      _initPlayer();
      return false;
    }
  }

  /// Waits for the player to reach one of the target states.
  Future<bool> _waitForStates(List<mdk.PlaybackState> targetStates, {int timeoutMs = 1000}) async {
    if (_player == null) return false;
    final completer = Completer<bool>();
    Timer? timer;
    Function? stateCallback; // Store callback to remove it later

    // Define the callback function
    stateCallback = (mdk.PlaybackState oldState, mdk.PlaybackState newState) {
      if (_player == null) return; // Guard against player disposal during callback
      logger.logDebug('waitForStates received state change: $oldState -> $newState', _logTag);
      if (targetStates.contains(newState)) {
        if (!completer.isCompleted) {
          logger.logDebug('waitForStates target state $newState reached.', _logTag);
          timer?.cancel();
          // We need a way to remove the listener. Assume MDK provides one or handle differently.
          // For now, we can't easily remove it without a reference or specific API.
          // _player!.offStateChanged(stateCallback); // Hypothetical removal
          completer.complete(true);
        }
      }
    };

    // Register the callback
    _player!.onStateChanged(stateCallback as void Function(mdk.PlaybackState, mdk.PlaybackState));

    // Check initial state immediately after registration
    final currentState = _player!.state;
     logger.logDebug('waitForStates initial check. Current: $currentState, Target: $targetStates', _logTag);
    if (targetStates.contains(currentState)) {
        logger.logDebug('waitForStates already in target state $currentState.', _logTag);
        // Can't easily remove listener here either without API.
        // _player!.offStateChanged(stateCallback); // Hypothetical removal
        return true; // Already in a target state
    }

    // Start the timeout timer
    timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        // Can't easily remove listener on timeout either.
        // _player!.offStateChanged(stateCallback); // Hypothetical removal
        completer.complete(false); // Timeout
        logger.logWarning('Timeout waiting for player states: $targetStates. Current: ${_player?.state}', _logTag);
      }
    });

    return completer.future;
  }

  /// Clears the current media from the player.
  Future<void> clearMedia() async {
      // logger.logInfo('>>> Entered clearMedia method.', _logTag); // Removed log
      if (_player == null) {
         // logger.logInfo('Player is null in clearMedia, returning.', _logTag); // Removed log
         return;
      }
      logger.logInfo('Clearing media from player.', _logTag); // Restored original log
      // logger.logInfo('Player is not null, proceeding with clearMedia.', _logTag); // Removed log
      try {
          // logger.logInfo('Entering try block in clearMedia...', _logTag); // Removed log
          final currentStatus = _player!.mediaStatus;
          // logger.logInfo('Current media status in clearMedia: $currentStatus', _logTag); // Removed log

          // Check if media is already invalid or not present before calling setMedia('')
          if (currentStatus.test(mdk.MediaStatus.noMedia) || currentStatus.test(mdk.MediaStatus.invalid)) {
              // logger.logInfo('Skipping setMedia("", unknown) as media status is $currentStatus.', _logTag); // Removed log
          } else {
              // Only call setMedia if there might be valid media loaded
              // logger.logInfo('Calling _player.setMedia("", unknown) in clearMedia...', _logTag); // Removed log
              _player!.setMedia('', mdk.MediaType.unknown); // Set empty path
              // logger.logInfo('Completed _player.setMedia("", unknown) in clearMedia.', _logTag); // Removed log
          }

          // Only attempt to check/set state if media wasn't already invalid/noMedia
          if (!(currentStatus.test(mdk.MediaStatus.noMedia) || currentStatus.test(mdk.MediaStatus.invalid))) {
              if (_player!.state != mdk.PlaybackState.stopped) {
                 // logger.logInfo('Setting _player.state = stopped in clearMedia...', _logTag); // Removed log
                 _player!.state = mdk.PlaybackState.stopped; // Explicitly stop
                 // logger.logInfo('Completed setting _player.state = stopped in clearMedia.', _logTag); // Removed log
              } else {
                 // logger.logInfo('Player state already stopped (or was invalid/noMedia).', _logTag); // Removed log
              }
          } else {
               // logger.logInfo('Skipping state check/set as media status was $currentStatus.', _logTag); // Removed log
          }


          textureIdNotifier.value = -1; // Reset texture ID
          isPlayerReadyNotifier.value = false; // Mark as not ready
      } catch(e, stack) { // Add stack trace to log
           logger.logError('Error during clearMedia operation: $e\n$stack', _logTag); // Log stack trace
           // Attempt reinitialization on error
           _initPlayer();
      }
  }

  /// Sets the video surface size. Returns true on success.
  bool setVideoSurfaceSize(int width, int height) {
    if (_player == null || width <= 0 || height <= 0) return false;
     logger.logInfo('Setting video surface size to ${width}x$height', _logTag);
    try {
       _player!.setVideoSurfaceSize(width, height);
       return true;
    } catch (e, stack) {
       logger.logError('Error setting video surface size: $e\n$stack', _logTag);
       return false;
    }
  }

  /// Updates the texture. Returns the new texture ID or -1 on failure.
  Future<int> updateTexture({required int width, required int height}) async {
    if (_player == null || !_isPlayerEffectivelyReady()) {
        logger.logWarning('Cannot update texture, player is null or not ready. Ready: ${isPlayerReadyNotifier.value}, State: ${_player?.state}', _logTag);
        return -1;
    }
    try {
        // Ensure we are paused or stopped before updating texture for a still frame
        if (_player!.state == mdk.PlaybackState.playing) {
             logger.logInfo('Pausing player before updating texture for still frame.', _logTag);
             await pause();
        }

       final newTextureId = await _player!.updateTexture(width: width, height: height);
       logger.logInfo('updateTexture called. Result: $newTextureId', _logTag);
       if (newTextureId > 0) {
           if (textureIdNotifier.value != newTextureId) {
                textureIdNotifier.value = newTextureId;
                logger.logInfo('Texture ID updated via updateTexture: $newTextureId', _logTag);
           }
       } else if (newTextureId <= 0 && textureIdNotifier.value != -1) {
            logger.logWarning('updateTexture returned invalid ID ($newTextureId), resetting.', _logTag);
            textureIdNotifier.value = -1;
       }
       return newTextureId;
    } catch (e, stack) {
        logger.logError('Error updating texture: $e\n$stack', _logTag);
        textureIdNotifier.value = -1; // Reset on error
        return -1;
    }
  }

  /// Check if player is in a state where it can render (paused or playing and ready)
  bool _isPlayerEffectivelyReady() {
     return _player != null &&
            isPlayerReadyNotifier.value &&
            (_player!.state == mdk.PlaybackState.paused || _player!.state == mdk.PlaybackState.playing);
  }


  Future<void> play() async {
    if (_player == null || !_isPlayerEffectivelyReady()) {
         logger.logWarning('Cannot play, player is null or not ready.', _logTag);
         return;
    }
    if (_player!.state != mdk.PlaybackState.playing) {
        logger.logInfo('Setting player state to playing.', _logTag);
        _player!.state = mdk.PlaybackState.playing;
    }
  }

  Future<void> pause() async {
    if (_player == null) return; // Don't check readiness, allow pausing even if not fully ready
    if (_player!.state != mdk.PlaybackState.paused) {
        logger.logInfo('Setting player state to paused.', _logTag);
        _player!.state = mdk.PlaybackState.paused;
        // Wait briefly for state change to potentially reflect
        await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> seek(int timeMs, {bool pauseAfterSeek = true}) async {
      if (_player == null || !_isPlayerEffectivelyReady()) {
         logger.logWarning('Cannot seek, player is null or not ready.', _logTag);
         return;
    }
    logger.logInfo('Seeking to ${timeMs}ms. Pause after seek: $pauseAfterSeek', _logTag);
    try {
        // Pause before seeking if requested, improves seeking precision for still frames
        if (pauseAfterSeek && _player!.state != mdk.PlaybackState.paused) {
            await pause();
        }
        _player!.seek(position: timeMs);
        // Ensure state is paused after seek if requested
        if (pauseAfterSeek) {
             // Small delay helps ensure the seek completes and frame updates
             await Future.delayed(const Duration(milliseconds: 50));
             if (_player!.state != mdk.PlaybackState.paused) {
                 await pause();
             }
        }
    } catch (e, stack) {
         logger.logError('Error seeking to $timeMs: $e\n$stack', _logTag);
    }
  }

  void dispose() {
    logger.logInfo('Disposing MdkPlayerService.', _logTag);
    _player?.dispose();
    _player = null;
    textureIdNotifier.dispose();
    isPlayingNotifier.dispose();
    isPlayerReadyNotifier.dispose();
  }
}