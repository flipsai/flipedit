import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flipedit/models/clip.dart' show ClipModel; // Import ClipModel specifically
import 'package:flipedit/utils/logger.dart'; // Import logger functions

class PreviewService {
  final String _wsUrl = 'ws://localhost:8080'; // Default URL

  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  Timer? _reconnectTimer;
  Timer? _fpsTimer;

  int _reconnectAttempt = 0;
  final int _maxReconnectAttempts = 10;
  final Duration _initialReconnectDelay = const Duration(seconds: 1);

  int _framesReceived = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // --- Public Notifiers ---
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
    logDebug('PreviewService initialized'); // Use logDebug
  }

  Future<void> connect() async {
    if (isConnectedNotifier.value) {
      logDebug('PreviewService: Already connected.'); // Use logDebug
      return;
    }
    logDebug('PreviewService: Attempting to connect...'); // Use logDebug
    _disconnectWebSocket(isReconnecting: true); // Ensure clean state before connecting
    statusNotifier.value = 'Connecting...';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      isConnectedNotifier.value = true; // Assume connected until proven otherwise by stream events
      statusNotifier.value = 'Connected';
      logDebug('PreviewService: WebSocket connected to $_wsUrl'); // Use logDebug
      _reconnectAttempt = 0; // Reset reconnect counter

      _streamSubscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (error) {
          logWarning('PreviewService: WebSocket error: $error'); // Use logWarning
          isConnectedNotifier.value = false;
          statusNotifier.value = 'Error: $error';
          _streamSubscription = null;
          _scheduleReconnect();
        },
        onDone: () {
          logDebug('PreviewService: WebSocket connection closed'); // Use logDebug
          isConnectedNotifier.value = false;
          statusNotifier.value = 'Disconnected';
          _streamSubscription = null;
          _scheduleReconnect(); // Attempt to reconnect if connection is lost
        },
        cancelOnError: true,
      );
    } catch (e, s) { // Catch stack trace for logError
      logError('PreviewService: WebSocket connection error: $e', e, s); // Use logError
      isConnectedNotifier.value = false;
      statusNotifier.value = 'Connection Error';
      _streamSubscription = null; // Ensure null on connection error
      _scheduleReconnect();
    }
  }

  void disconnect() {
    logDebug('PreviewService: Disconnecting...'); // Use logDebug
    _disconnectWebSocket();
  }

  void _disconnectWebSocket({bool isReconnecting = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;

    if (_channel != null) {
      _channel!.sink.close().catchError((e) {
        logWarning('PreviewService: Error closing WebSocket sink: $e'); // Use logWarning
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
    logDebug('PreviewService: WebSocket disconnected.'); // Use logDebug
  }

  void _scheduleReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      logWarning('PreviewService: Maximum reconnection attempts reached.'); // Use logWarning
      statusNotifier.value = 'Disconnected (Max Retries)';
      return;
    }

    _reconnectTimer?.cancel(); // Cancel existing timer

    // Exponential backoff with jitter
    final baseDelay = _initialReconnectDelay.inMilliseconds * pow(2, _reconnectAttempt);
    final jitter = (baseDelay * 0.2 * (Random().nextDouble() - 0.5)).toInt();
    final delay = Duration(milliseconds: (baseDelay + jitter).toInt().clamp(0, 60000)); // Clamp max delay

    logDebug('PreviewService: Scheduling reconnect attempt ${_reconnectAttempt + 1} in ${delay.inMilliseconds}ms'); // Use logDebug
    statusNotifier.value = 'Reconnecting in ${delay.inSeconds}s...';

    _reconnectTimer = Timer(delay, () {
      if (!isConnectedNotifier.value) {
        _reconnectAttempt++;
        logDebug('PreviewService: Attempting reconnection #$_reconnectAttempt'); // Use logDebug
        connect(); // Attempt to reconnect
      }
    });
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is String) {
      try {
        // Check for JSON state message first (less common)
        if (message.startsWith('{')) {
          _handleStateMessage(message);
        } else {
          // Assume base64 image data
          final Uint8List bytes = base64Decode(message);
          _processImageBytes(bytes);
        }
      } catch (e) {
        logWarning('PreviewService: Error decoding string message: $e'); // Use logWarning
      }
    } else if (message is List<int>) {
      // Handle binary frame data
      final Uint8List bytes = Uint8List.fromList(message);
      _processImageBytes(bytes);
    } else {
      logWarning('PreviewService: Received unexpected message type: ${message.runtimeType}'); // Use logWarning
    }
  }

   void _handleStateMessage(String jsonMessage) {
    try {
      logVerbose('PreviewService: Received JSON state: $jsonMessage'); // Use logVerbose
      // Currently, we don't need to react to server state updates here.
      // The ViewModel drives the state based on user actions.
      // This could be used for synchronization checks in the future if needed.
      // final Map<String, dynamic> state = json.decode(jsonMessage);
      // if (state.containsKey('type') && state['type'] == 'state') {
      //   final bool isPlaying = state['playing'] as bool;
      //   final int frame = state['frame'] as int;
      //   logVerbose('PreviewService: Server state: playing=$isPlaying, frame=$frame'); // Use logVerbose
      // }
    } catch (e) {
      logWarning('PreviewService: Error parsing state message: $e'); // Use logWarning
    }
  }

  void _processImageBytes(Uint8List bytes) {
    try {
      ui.decodeImageFromList(bytes, (ui.Image result) {
        // Dispose previous frame before assigning new one
        currentFrameNotifier.value?.dispose();
        currentFrameNotifier.value = result;
        _framesReceived++;
      });
    } catch (e) {
       logWarning('PreviewService: Error decoding image bytes: $e'); // Use logWarning
       // Optionally clear the frame or show an error indicator
       currentFrameNotifier.value?.dispose();
       currentFrameNotifier.value = null;
    }
  }

  void _sendCommand(String command) {
    if (_channel != null && isConnectedNotifier.value) {
      logVerbose('PreviewService: Sending command: $command'); // Use logVerbose
      try {
        _channel!.sink.add(command);
      } catch (e) {
        logWarning('PreviewService: Error sending command "$command": $e'); // Use logWarning
        // Consider attempting to reconnect or notifying ViewModel of send failure
        isConnectedNotifier.value = false;
        statusNotifier.value = 'Send Error';
         _scheduleReconnect();
      }
    } else {
      logWarning('PreviewService: Cannot send command "$command", not connected.'); // Use logWarning
    }
  }

  void sendPlaybackCommand(bool isPlaying) {
    final command = isPlaying ? 'play' : 'pause';
    _sendCommand(command);
  }

  void sendSeekCommand(int frame) {
    final command = 'seek:$frame';
    _sendCommand(command);
  }

  // Use ClipModel instead of Clip
  void sendClipsData(List<ClipModel?> clips) { // Allow nullable ClipModels
     if (_channel != null && isConnectedNotifier.value) {
        try {
            // Filter out null clips, cast to ClipModel, and then map to JSON
            final nonNullClips = clips.whereType<ClipModel>().toList(); // Filters non-null and casts to ClipModel
            final clipsJson = nonNullClips.map((clip) => clip.toJson()).toList(); // Call toJson on ClipModel
            final message = json.encode({'type': 'clips', 'data': clipsJson});
            logVerbose('PreviewService: Sending clips data (${clipsJson.length} non-null clips)'); // Use logVerbose
            _channel!.sink.add(message);
        } catch (e, s) { // Catch stack trace
            logError('PreviewService: Error encoding or sending clips data: $e', e, s); // Use logError
             isConnectedNotifier.value = false;
             statusNotifier.value = 'Send Error (Clips)';
             _scheduleReconnect();
        }
     } else {
       logWarning('PreviewService: Cannot send clips data, not connected.'); // Use logWarning
     }
  }

  void dispose() {
    logDebug('PreviewService: Disposing...'); // Use logDebug
    _disconnectWebSocket();
    _fpsTimer?.cancel();
    currentFrameNotifier.dispose();
    isConnectedNotifier.dispose();
    statusNotifier.dispose();
    fpsNotifier.dispose();
    logDebug('PreviewService: Disposed.'); // Use logDebug
  }
}