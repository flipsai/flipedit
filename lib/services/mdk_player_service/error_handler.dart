part of '../mdk_player_service.dart';

class MdkPlayerErrorHandler {
  final MdkPlayerService _service;
  final String _logTag;
  final int _maxConsecutiveErrors = 3;

  bool _isRecoveringFromError = false;
  int _consecutiveErrorCount = 0;
  DateTime? _lastErrorTime;

  bool get isRecovering => _isRecoveringFromError;

  MdkPlayerErrorHandler(this._service) : _logTag = '${_service._logTag}_ErrorHandler';

  void resetErrorState() {
    _consecutiveErrorCount = 0;
    _lastErrorTime = null;
    _isRecoveringFromError = false;
    logger.logInfo('Player error state reset.', _logTag);
  }

  void handlePlayerCreationError() {
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
      _service.isPlayerReadyNotifier.value = false; // Ensure not ready during backoff
      // Schedule recovery attempt
      Future.delayed(const Duration(seconds: 5), _attemptRecovery);
    } else {
      // Optionally schedule a retry sooner if not backing off
      Future.delayed(const Duration(milliseconds: 500), _retryInitialization);
    }
  }

  void _attemptRecovery() {
    logger.logInfo('Attempting to recover player after backoff...', _logTag);
    _isRecoveringFromError = false;
    _consecutiveErrorCount = 0; // Reset count before retrying
    _service._initPlayer(); // Try initializing again
  }

  void _retryInitialization() {
    // Only retry if player is still null and not already in recovery mode
    if (_service._player == null && !_isRecoveringFromError) {
      logger.logInfo('Retrying player initialization shortly...', _logTag);
      _service._initPlayer();
    }
  }

  void handleMediaError(String mediaPath, dynamic e, StackTrace stack) {
     logger.logError('Error setting or preparing media $mediaPath: $e\n$stack', _logTag);
     _service.isPlayerReadyNotifier.value = false;
     // Attempt recovery
     _service.clearMedia();
     _service._initPlayer(); // Re-initialize player on media error
  }
}