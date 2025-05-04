import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:watch_it/watch_it.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flipedit/models/clip.dart' show ClipModel;
import 'package:flipedit/utils/logger.dart';

class PreviewService implements Disposable {
  final String _wsUrl = 'ws://localhost:8080';
  final String _logTag = 'PreviewService';

  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  Timer? _reconnectTimer;
  Timer? _fpsTimer;

  int _reconnectAttempt = 0;
  final int _maxReconnectAttempts = 10;
  final Duration _initialReconnectDelay = const Duration(seconds: 1);

  int _framesReceived = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  final ValueNotifier<ui.Image?> currentFrameNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier(false);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Disconnected');
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);

  PreviewService() {
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      fpsNotifier.value = _framesReceived;
      _framesReceived = 0;
      _lastFpsUpdate = DateTime.now();
    });
    logDebug('PreviewService initialized', _logTag);
  }

  Future<void> connect() async {
    if (isConnectedNotifier.value) {
      logDebug('Already connected.', _logTag);
      return;
    }
    logDebug('Attempting to connect...', _logTag);
    _disconnectWebSocket(isReconnecting: true); // Ensure clean state
    statusNotifier.value = 'Connecting...';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      isConnectedNotifier.value = true; // Assume connected initially
      statusNotifier.value = 'Connected';
      logDebug('WebSocket connected to $_wsUrl', _logTag);
      _reconnectAttempt = 0; // Reset reconnect counter

      _streamSubscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (error) {
          logWarning('WebSocket error: $error', _logTag);
          isConnectedNotifier.value = false;
          statusNotifier.value = 'Error: $error';
          _streamSubscription = null;
          _scheduleReconnect();
        },
        onDone: () {
          logDebug('WebSocket connection closed', _logTag);
          isConnectedNotifier.value = false;
          statusNotifier.value = 'Disconnected';
          _streamSubscription = null;
          _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e, s) {
      logError('WebSocket connection error', e, s, _logTag);
      isConnectedNotifier.value = false;
      statusNotifier.value = 'Connection Error';
      _streamSubscription = null;
      _scheduleReconnect();
    }
  }

  void disconnect() {
    logDebug('Disconnecting...', _logTag);
    _disconnectWebSocket();
  }

  void _disconnectWebSocket({bool isReconnecting = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;

    if (_channel != null) {
      _channel!.sink.close().catchError((e) {
        logWarning('Error closing WebSocket sink: $e', _logTag);
      });
      _channel = null;
    }

    isConnectedNotifier.value = false;
    if (!isReconnecting) {
      statusNotifier.value = 'Disconnected';
      currentFrameNotifier.value?.dispose();
      currentFrameNotifier.value = null;
      _reconnectAttempt = 0; // Reset attempts if manually disconnected
    }
    logDebug('WebSocket disconnected.', _logTag);
  }

  void _scheduleReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      logWarning('Maximum reconnection attempts reached.', _logTag);
      statusNotifier.value = 'Disconnected (Max Retries)';
      return;
    }

    _reconnectTimer?.cancel(); // Cancel existing timer

    // Exponential backoff with jitter
    final baseDelay =
        _initialReconnectDelay.inMilliseconds * pow(2, _reconnectAttempt);
    final jitter = (baseDelay * 0.2 * (Random().nextDouble() - 0.5)).toInt();
    final delay = Duration(
      milliseconds: (baseDelay + jitter).toInt().clamp(0, 60000),
    ); // Clamp max delay

    logDebug(
      'Scheduling reconnect attempt ${_reconnectAttempt + 1} in ${delay.inMilliseconds}ms',
      _logTag,
    );
    statusNotifier.value = 'Reconnecting in ${delay.inSeconds}s...';

    _reconnectTimer = Timer(delay, () {
      if (!isConnectedNotifier.value) {
        _reconnectAttempt++;
        logDebug('Attempting reconnection #$_reconnectAttempt', _logTag);
        connect(); // Attempt to reconnect
      }
    });
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is String) {
      try {
        // Check for JSON state message first
        if (message.startsWith('{')) {
          _handleStateMessage(message);
        } else {
          // Assume base64 image data
          final Uint8List bytes = base64Decode(message);
          _processImageBytes(bytes);
        }
      } catch (e) {
        logWarning('Error decoding string message: $e', _logTag);
      }
    } else if (message is List<int>) {
      // Handle binary frame data
      final Uint8List bytes = Uint8List.fromList(message);
      _processImageBytes(bytes);
    } else {
      logWarning(
        'Received unexpected message type: ${message.runtimeType}',
        _logTag,
      );
    }
  }

  void _handleStateMessage(String jsonMessage) {
    try {
      // Example: Parse state if needed in the future
      // final state = jsonDecode(jsonMessage);
      logVerbose('Received JSON state: $jsonMessage', _logTag);
    } catch (e) {
      logWarning('Error parsing state message: $e', _logTag);
    }
  }

  /// Processes raw image bytes received from WebSocket and updates the frame notifier.
  void _processImageBytes(Uint8List bytes) {
    updatePreviewFrameFromBytes(bytes); // Delegate to the public method
  }

  /// Processes raw image bytes (e.g., from HTTP) and updates the frame notifier.
  void updatePreviewFrameFromBytes(Uint8List bytes) {
    try {
      ui.decodeImageFromList(bytes, (ui.Image result) {
        // Dispose previous frame before assigning new one
        currentFrameNotifier.value?.dispose();
        currentFrameNotifier.value = result;
        // Note: _framesReceived might not be accurate for HTTP updates,
        // but we'll leave it for now as it primarily affects WebSocket FPS display.
        _framesReceived++;
      });
    } catch (e, s) {
      logError('Error decoding image bytes', e, s, _logTag);
    }
  }

  /// Clears the current preview frame.
  void clearPreviewFrame() {
    logDebug('Clearing preview frame.', _logTag);
    currentFrameNotifier.value?.dispose();
    currentFrameNotifier.value = null;
  }

  // --- Methods for Sending Commands ---

  void _sendCommand(Map<String, dynamic> commandData) {
    if (_channel != null && isConnectedNotifier.value) {
      try {
        final command = jsonEncode(commandData);
        logVerbose('Sending command: $command', _logTag);
        _channel!.sink.add(command);
      } catch (e, s) {
        logError('Error sending command', e, s, _logTag);
        isConnectedNotifier.value = false;
        statusNotifier.value = 'Send Error';
        _scheduleReconnect(); // Attempt reconnect on send error
      }
    } else {
      logWarning('Cannot send command: Not connected.', _logTag);
      connect(); // Attempt to connect if not connected
    }
  }

  void sendPlaybackCommand(bool isPlaying) {
    _sendCommand({
      'type': 'playback',
      'payload': {'playing': isPlaying},
    });
  }

  void sendSeekCommand(int frame) {
    _sendCommand({
      'type': 'seek',
      'payload': {'frame': frame},
    });
  }

  void sendClipsData(List<ClipModel> clips) {
    if (_channel != null && isConnectedNotifier.value) {
      try {
        final List<Map<String, dynamic>> clipData =
            clips.map((clip) => clip.toJson()).toList(); // Use toJson() method
        final message = jsonEncode({'type': 'sync_clips', 'payload': clipData});
        logInfo('Sending ${clipData.length} clips to preview server.', _logTag);
        _channel!.sink.add(message);
      } catch (e, s) {
        logError('Error sending clips data', e, s, _logTag);
        isConnectedNotifier.value = false;
        statusNotifier.value = 'Send Error (Clips)';
        _scheduleReconnect();
      }
    } else {
      logWarning('Cannot send clips: Not connected.', _logTag);
      connect(); // Attempt to connect if not connected
    }
  }

  void sendCanvasDimensions(int width, int height) {
    _sendCommand({
      'type': 'canvas_dimensions',
      'payload': {'width': width, 'height': height},
    });
  }

  // --- Cleanup ---

  void dispose() {
    logDebug('Disposing PreviewService', _logTag);
    _streamSubscription?.cancel();
    _reconnectTimer?.cancel();
    _fpsTimer?.cancel();
    
    // Close active connections
    _disconnectWebSocket();
    
    // Remove all listeners
    isConnectedNotifier.value = false;
    statusNotifier.value = 'Disposed';
    
    // Dispose image resources
    if (currentFrameNotifier.value != null) {
      currentFrameNotifier.value!.dispose();
      currentFrameNotifier.value = null;
    }
    
    // Update notifiers
    fpsNotifier.value = 0;
    
    logDebug('PreviewService disposed', _logTag);
  }

  @override
  FutureOr onDispose() {
    dispose();
  }
}
