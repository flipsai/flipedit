import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:web_socket_channel/io.dart';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/services/texture_helper.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';

class OpenCvPythonPlayerViewModel extends ChangeNotifier implements Disposable {
  String get _logTag => runtimeType.toString();

  // Dependencies
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineStateViewModel _timelineStateViewModel;
  UvManager? _uvManager;

  // State notifiers
  final ValueNotifier<int> textureIdNotifier = ValueNotifier(-1);
  final ValueNotifier<bool> isReadyNotifier = ValueNotifier(false);
  final ValueNotifier<String> statusNotifier = ValueNotifier('Initializing...');
  final ValueNotifier<int> fpsNotifier = ValueNotifier(0);

  // Default dimensions (can be updated from canvas settings)
  int _width = 1920;
  int _height = 1080;

  // WebSocket connection for receiving frame data
  IOWebSocketChannel? _frameDataChannel;
  StreamSubscription? _frameDataSubscription;

  // Playback control
  VoidCallback? _playStateListener;
  VoidCallback? _frameListener;

  // Track disposal state
  bool _isDisposed = false;

  // Constructor - dependency injection, but handles UvManager as async
  OpenCvPythonPlayerViewModel({
    TimelineNavigationViewModel? timelineNavViewModel,
    TimelineStateViewModel? timelineStateViewModel,
    UvManager? uvManager,
  }) {
    _timelineNavViewModel =
        timelineNavViewModel ?? di<TimelineNavigationViewModel>();
    _timelineStateViewModel =
        timelineStateViewModel ?? di<TimelineStateViewModel>();

    // Try to get UvManager, but don't fail if it's not ready
    if (uvManager != null) {
      _uvManager = uvManager;
      _initialize();
    } else {
      statusNotifier.value = 'Waiting for Python integration...';
      _initializeAsync();
    }
  }

  Future<void> _initializeAsync() async {
    try {
      // Wait for UvManager to be ready
      logInfo(_logTag, 'Waiting for UvManager to be ready...');

      try {
        _uvManager = await di.getAsync<UvManager>();
        logInfo(_logTag, 'UvManager is ready, initializing player');
      } catch (e) {
        logError(
          _logTag,
          'Error getting UvManager from dependency injection: $e',
        );
        if (!_isDisposed && statusNotifier.hasListeners) {
          statusNotifier.value =
              'Error: Python integration service unavailable';
        }
        return;
      }

      // Now initialize
      await _initialize();
    } catch (e, stackTrace) {
      logError(_logTag, 'Error waiting for UvManager: $e', stackTrace);
      // Check if the notifier is still mounted before updating
      if (!_isDisposed && statusNotifier.hasListeners) {
        statusNotifier.value = 'Error: Could not initialize Python integration';
      }
    }
  }

  Future<void> _initialize() async {
    logInfo(_logTag, 'Initializing OpenCvPythonPlayerViewModel');
    if (!_isDisposed && statusNotifier.hasListeners) {
      statusNotifier.value = 'Initializing Python OpenCV renderer...';
    }

    try {
      if (_uvManager == null) {
        logError(_logTag, 'UvManager is not available');
        if (!_isDisposed && statusNotifier.hasListeners) {
          statusNotifier.value = 'Error: Python integration not available';
        }
        return;
      }

      // Run diagnostics to check server status
      try {
        logInfo(_logTag, 'Running Python integration diagnostics...');
        final status = await _uvManager!.checkPythonServerStatus();

        logInfo(_logTag, 'Diagnostics results: $status');

        if (!status['python_available']) {
          logError(
            _logTag,
            'Python is not available: ${status['errors'].join(', ')}',
          );
          if (!_isDisposed && statusNotifier.hasListeners) {
            statusNotifier.value = 'Error: Python not available';
          }
          return;
        }

        if (!status['texture_bridge_available']) {
          logError(
            _logTag,
            'Texture bridge is not available: ${status['errors'].join(', ')}',
          );
          if (!_isDisposed && statusNotifier.hasListeners) {
            statusNotifier.value = 'Error: Texture bridge not available';
          }
          return;
        }

        if (!status['websocket_responding']) {
          logError(
            _logTag,
            'WebSocket server not responding: ${status['errors'].join(', ')}',
          );

          // Try starting the server again if it's not responding
          logInfo(_logTag, 'Attempting to restart Python server...');
          await _uvManager!.runMainPythonScript();

          // Wait a moment for the server to start
          await Future.delayed(const Duration(seconds: 2));

          // Check if the server is now running
          final retryStatus = await _uvManager!.checkPythonServerStatus();
          if (!retryStatus['websocket_responding']) {
            logError(_logTag, 'Failed to start Python server after retry');
            if (!_isDisposed && statusNotifier.hasListeners) {
              statusNotifier.value = 'Error: Could not start Python server';
            }
            return;
          }

          logInfo(_logTag, 'Python server restarted successfully');
        }
      } catch (e) {
        logError(_logTag, 'Error during diagnostics: $e');
        if (!_isDisposed && statusNotifier.hasListeners) {
          statusNotifier.value = 'Error during diagnostics: $e';
        }
        return;
      }

      // Testing texture creation directly
      logInfo(_logTag, 'Testing texture creation directly');
      final testResult = await _uvManager!.testCreateTexture();

      if (testResult == -1) {
        logError(
          _logTag,
          'Texture creation test failed - likely a plugin issue',
        );
        if (!_isDisposed && statusNotifier.hasListeners) {
          statusNotifier.value = 'Failed to create texture - plugin error';
        }
        return;
      }

      logInfo(
        _logTag,
        'Texture creation test succeeded, continuing with initialization',
      );

      // Now try the normal flow through UvManager
      logInfo(
        _logTag,
        'UvManager is available, initializing texture sharing...',
      );

      // Initialize the texture sharing with our dimensions
      final textureId = await _uvManager!.initializeTextureSharing(
        width: _width,
        height: _height,
      );

      logInfo(
        _logTag,
        'initializeTextureSharing returned textureId: $textureId',
      );

      if (textureId == -1) {
        logError(
          _logTag,
          'Failed to initialize texture sharing, textureId is -1',
        );
        if (!_isDisposed && statusNotifier.hasListeners) {
          statusNotifier.value = 'Failed to create texture';
        }
        return;
      }

      logInfo(_logTag, 'Setting texture ID to: $textureId');
      if (!_isDisposed && textureIdNotifier.hasListeners) {
        textureIdNotifier.value = textureId;
      }

      // Setup WebSocket listener for frame data from Python
      await _setupFrameDataListener();

      // Setup listeners for frame changes and playback state
      logInfo(_logTag, 'Setting up playback state listeners');
      _playStateListener = _onPlayStateChanged;
      _timelineNavViewModel.isPlayingNotifier.addListener(_playStateListener!);

      _frameListener = _onFrameChanged;
      _timelineNavViewModel.currentFrameNotifier.addListener(_frameListener!);

      if (!_isDisposed) {
        isReadyNotifier.value = true;
        if (statusNotifier.hasListeners) {
          statusNotifier.value = 'Ready';
        }
      }

      logInfo(
        _logTag,
        'OpenCvPythonPlayerViewModel initialized with textureId: $textureId',
      );
    } catch (e, stackTrace) {
      logError(
        _logTag,
        'Error initializing OpenCV Python player: $e',
        stackTrace,
      );
      if (!_isDisposed && statusNotifier.hasListeners) {
        statusNotifier.value = 'Error: $e';
      }
    }
  }

  Future<void> _setupFrameDataListener() async {
    try {
      logInfo(_logTag, 'Setting up WebSocket listener for frame data...');

      // Connect to Python WebSocket server for receiving frame data
      _frameDataChannel = IOWebSocketChannel.connect(
        Uri.parse('ws://localhost:8080'),
        pingInterval: const Duration(seconds: 5),
      );

      await _frameDataChannel!.ready;
      logInfo(_logTag, 'Frame data WebSocket connection established');

      // Listen for incoming frame data
      _frameDataSubscription = _frameDataChannel!.stream.listen(
        (data) => _handleFrameData(data),
        onError: (error) {
          logError(_logTag, 'WebSocket error: $error');
          _reconnectFrameDataListener();
        },
        onDone: () {
          logWarning(
            _logTag,
            'WebSocket connection closed, attempting to reconnect...',
          );
          _reconnectFrameDataListener();
        },
      );

      logInfo(_logTag, 'Frame data listener setup complete');
    } catch (e, stackTrace) {
      logError(_logTag, 'Error setting up frame data listener: $e', stackTrace);
      // Try to reconnect after a delay
      Timer(const Duration(seconds: 2), () => _reconnectFrameDataListener());
    }
  }

  void _reconnectFrameDataListener() {
    if (_isDisposed) return;

    logInfo(_logTag, 'Attempting to reconnect frame data listener...');

    // Close existing connection
    _frameDataSubscription?.cancel();
    _frameDataChannel?.sink.close();

    // Try to reconnect after a delay
    Timer(const Duration(seconds: 1), () {
      if (!_isDisposed) {
        _setupFrameDataListener();
      }
    });
  }

  void _handleFrameData(dynamic data) {
    try {
      if (_isDisposed) return;

      final message = json.decode(data as String);
      final command = message['command'] as String?;

      if (command == 'frame_data') {
        // Extract frame data
        final frameDataB64 = message['frame_data'] as String;
        final width = message['width'] as int;
        final height = message['height'] as int;
        final frameNumber = message['frame_number'] as int;

        // Decode base64 frame data
        final frameBytes = base64Decode(frameDataB64);
        final frameData = Uint8List.fromList(frameBytes);

        // Update texture with new frame data
        _updateTexture(frameData, width, height);

        // Update FPS counter (simple calculation)
        _updateFpsCounter();

        logDebug(
          _logTag,
          'Updated texture with frame $frameNumber (${width}x$height)',
        );
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error handling frame data: $e', stackTrace);
    }
  }

  Future<void> _updateTexture(
    Uint8List frameData,
    int width,
    int height,
  ) async {
    try {
      final textureId = textureIdNotifier.value;
      if (textureId == -1) {
        logWarning(_logTag, 'Cannot update texture - no valid texture ID');
        return;
      }

      // Update texture using FixedTextureHelper
      final success = await FixedTextureHelper.updateTextureData(
        textureId,
        frameData,
        width,
        height,
      );

      if (!success) {
        logError(_logTag, 'Failed to update texture data');
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error updating texture: $e', stackTrace);
    }
  }

  // Simple FPS counter
  int _frameCount = 0;
  int _lastFpsUpdate = 0;

  void _updateFpsCounter() {
    _frameCount++;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastFpsUpdate >= 1000) {
      // Update every second
      if (!_isDisposed && fpsNotifier.hasListeners) {
        fpsNotifier.value = _frameCount;
      }
      _frameCount = 0;
      _lastFpsUpdate = now;
    }
  }

  void _onPlayStateChanged() {
    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;

    try {
      // Create a new control message
      final controlMsg = {
        'command': isPlaying ? 'start_playback' : 'stop_playback',
        'frame_rate': 30,
        'current_frame': _timelineNavViewModel.currentFrameNotifier.value,
      };

      // Send the message via websocket
      _sendControlMessage(controlMsg);
    } catch (e, stackTrace) {
      logError(_logTag, 'Error controlling playback: $e', stackTrace);
    }
  }

  void _onFrameChanged() {
    if (!_timelineNavViewModel.isPlayingNotifier.value) {
      // Only request frame update when not playing
      try {
        // Create frame update message
        final frameMsg = {
          'command': 'render_frame',
          'frame': _timelineNavViewModel.currentFrameNotifier.value,
        };

        // Send the message
        _sendControlMessage(frameMsg);
      } catch (e, stackTrace) {
        logError(_logTag, 'Error requesting frame update: $e', stackTrace);
      }
    }
  }

  Future<void> _sendControlMessage(Map<String, dynamic> message) async {
    try {
      // Create a WebSocket connection
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://localhost:8080'),
      );

      // Wait for connection
      await channel.ready;

      // Send the message
      channel.sink.add(jsonEncode(message));
      logInfo(_logTag, 'Sent control message: ${jsonEncode(message)}');

      // Close the connection
      await channel.sink.close();
    } catch (e, stackTrace) {
      logError(_logTag, 'Error sending control message: $e', stackTrace);
    }
  }

  void updateDimensions(int width, int height) {
    if (width != _width || height != _height) {
      _width = width;
      _height = height;

      // Re-initialize texture with new dimensions
      _initialize();
    }
  }

  @override
  void dispose() {
    try {
      _isDisposed = true;
      logInfo(_logTag, 'Disposing OpenCvPythonPlayerViewModel');

      // Close WebSocket connections
      _frameDataSubscription?.cancel();
      _frameDataChannel?.sink.close();

      // Remove listeners
      if (_playStateListener != null) {
        _timelineNavViewModel.isPlayingNotifier.removeListener(
          _playStateListener!,
        );
      }

      if (_frameListener != null) {
        _timelineNavViewModel.currentFrameNotifier.removeListener(
          _frameListener!,
        );
      }

      // Dispose texture
      _uvManager?.disposeTexture();

      // Dispose notifiers
      textureIdNotifier.dispose();
      isReadyNotifier.dispose();
      statusNotifier.dispose();
      fpsNotifier.dispose();

      logInfo(_logTag, 'OpenCvPythonPlayerViewModel disposed successfully');
    } catch (e, stackTrace) {
      logError(_logTag, 'Error during dispose: $e', stackTrace);
    } finally {
      super.dispose();
    }
  }

  @override
  FutureOr onDispose() {
    // Already handled in dispose()
  }

  // Simple function to check if Python server is running by trying to connect to it
  Future<bool> _checkPythonServerRunning() async {
    try {
      // Try to connect to the WebSocket server
      final socket = IOWebSocketChannel.connect(
        Uri.parse('ws://localhost:8080'),
        pingInterval: const Duration(seconds: 1),
      );

      // Wait up to 3 seconds for connection
      try {
        await socket.ready.timeout(const Duration(seconds: 3));
        // Successfully connected - close and return true
        await socket.sink.close();
        logInfo(_logTag, 'Python WebSocket server is running');
        return true;
      } catch (e) {
        logError(_logTag, 'Error waiting for WebSocket connection: $e');
        try {
          await socket.sink.close();
        } catch (_) {}
        return false;
      }
    } catch (e) {
      logError(_logTag, 'Error connecting to Python WebSocket server: $e');
      return false;
    }
  }
}
