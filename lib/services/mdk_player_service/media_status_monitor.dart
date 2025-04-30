part of '../mdk_player_service.dart';

class MdkMediaStatusMonitor {
  final MdkPlayerService _service;
  final String _logTag;
  Completer<bool>? _preparedCompleter;
  Timer? _preparedTimer;

  MdkMediaStatusMonitor(this._service) : _logTag = '${_service._logTag}_MediaStatus';

  /// Handles media status changes from the player.
  bool onMediaStatusChanged(mdk.MediaStatus oldStatus, mdk.MediaStatus newStatus) {
    if (_service._player == null) return false; // Guard against player disposal

    logger.logInfo('Media status changed: $oldStatus -> $newStatus', _logTag);

    // Update readiness based on status
    if (newStatus.test(mdk.MediaStatus.loaded) || newStatus.test(mdk.MediaStatus.prepared)) {
      if (!_service.isPlayerReadyNotifier.value && _service._player?.state == mdk.PlaybackState.paused) {
        _service.isPlayerReadyNotifier.value = true;
        logger.logInfo('Player is now ready (status: $newStatus, state: ${_service._player?.state})', _logTag);
      }
    } else if (newStatus.test(mdk.MediaStatus.invalid) || newStatus.test(mdk.MediaStatus.noMedia)) {
      _service.isPlayerReadyNotifier.value = false;
      logger.logWarning('Player media became invalid or no media. Ready: false', _logTag);
    }

    // Handle waiting for prepared status
    if (_preparedCompleter != null && !_preparedCompleter!.isCompleted) {
      if (newStatus.test(mdk.MediaStatus.prepared)) {
        logger.logDebug('waitForPreparedStatus: Prepared status reached.', _logTag);
        _preparedTimer?.cancel();
        _preparedCompleter!.complete(true);
        _resetPreparedWaiter();
      } else if (newStatus.test(mdk.MediaStatus.invalid)) {
        logger.logWarning('waitForPreparedStatus: Invalid status reached.', _logTag);
        _preparedTimer?.cancel();
        _preparedCompleter!.complete(false); // Treat invalid as failure
         _resetPreparedWaiter();
      }
    }

    return true; // Required return type for the callback
  }

  /// Waits for the player to reach the Prepared media status flag.
  Future<bool> waitForPreparedStatus({int timeoutMs = 2000}) async {
    if (_service._player == null) return false;

    // Check initial status immediately
    final currentStatus = _service._player!.mediaStatus;
    logger.logDebug('waitForPreparedStatus initial check. Current: $currentStatus', _logTag);
    if (currentStatus.test(mdk.MediaStatus.prepared)) {
      logger.logDebug('waitForPreparedStatus: Already prepared.', _logTag);
      return true;
    }
    if (currentStatus.test(mdk.MediaStatus.invalid)) {
      logger.logWarning('waitForPreparedStatus: Already invalid.', _logTag);
      return false;
    }

    // If already waiting, return the existing future
    if (_preparedCompleter != null && !_preparedCompleter!.isCompleted) {
       logger.logDebug('waitForPreparedStatus: Already waiting, returning existing future.', _logTag);
       return _preparedCompleter!.future;
    }

    _preparedCompleter = Completer<bool>();

    // Start the timeout timer
    _preparedTimer = Timer(Duration(milliseconds: timeoutMs), () {
      if (_preparedCompleter != null && !_preparedCompleter!.isCompleted) {
        logger.logWarning('Timeout waiting for prepared status. Current: ${_service._player?.mediaStatus}', _logTag);
        _preparedCompleter!.complete(false); // Timeout
        _resetPreparedWaiter();
      }
    });

    // The onMediaStatusChanged handler will complete the completer
    return _preparedCompleter!.future;
  }

  void _resetPreparedWaiter() {
     _preparedTimer?.cancel();
     _preparedTimer = null;
     _preparedCompleter = null;
  }

  // Cancel any pending waits on dispose or when player is reset
  void cancelWaits() {
     _resetPreparedWaiter();
  }
}