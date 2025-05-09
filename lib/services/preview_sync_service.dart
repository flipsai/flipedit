import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:watch_it/watch_it.dart';

import '../persistence/database/project_database.dart' show Track;
import '../models/clip.dart' as model_clip;
import '../services/project_database_service.dart';
import '../utils/logger.dart';

class PreviewSyncService {
  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false; // Add flag to track connection attempts
  final String _serverUrl = 'ws://localhost:8080';
  final String _logTag = 'PreviewSyncService';

  PreviewSyncService() {
    _connect();
  }

  void _connect() async {
    // Prevent concurrent connection attempts
    if ((_isConnected && _channel != null) || _isConnecting) return;

    _isConnecting = true; // Set flag before attempting connection
    try {
      logInfo('Attempting to connect to preview server: $_serverUrl', _logTag);
      final socket = await WebSocket.connect(_serverUrl);
      _channel = IOWebSocketChannel(socket);
      _isConnected = true;
      logInfo('Connected to preview server.', _logTag);

      _channel!.stream.listen(
        (message) {
          logVerbose('Received from preview server: $message', _logTag);
          // Handle incoming messages if needed
        },
        onDone: () {
          logWarning('Disconnected from preview server.', _logTag);
          _isConnected = false;
          _channel = null;
          _isConnecting = false; // Reset flag on disconnect
        },
        onError: (error) {
          logError('Preview server connection error', error, null, _logTag);
          _isConnected = false;
          _channel = null;
          _isConnecting = false; // Reset flag on error
        },
      );
    } catch (e, s) {
      logError('Failed to connect to preview server', e, s, _logTag);
      _isConnected = false;
      _channel = null;
    } finally {
      _isConnecting = false; // Ensure flag is reset even if connect throws early
    }
  }

  /// Send an arbitrary message to the preview server
  void sendMessage(String message) {
    if (!_isConnected || _channel == null) {
      logWarning(
        'Cannot send message to preview server: Not connected.',
        _logTag,
      );
      _connect(); // Attempt to reconnect
      return;
    }

    try {
      _channel!.sink.add(message);
      logVerbose('Sent message to preview server: $message', _logTag);
    } catch (e, s) {
      logError('Error sending message to preview server', e, s, _logTag);
    }
  }

  /// Send a JSON message to the preview server
  void sendJsonMessage(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      logWarning(
        'Cannot send JSON message to preview server: Not connected.',
        _logTag,
      );
      _connect(); // Attempt to reconnect
      return;
    }

    try {
      final message = jsonEncode(data);
      _channel!.sink.add(message);
      logVerbose('Sent JSON message to preview server: $message', _logTag);
    } catch (e, s) {
      logError('Error sending JSON message to preview server', e, s, _logTag);
    }
  }

  Future<void> sendClipsToPreviewServer() async {
    if (!_isConnected || _channel == null) {
      logWarning(
        'Cannot send clips to preview server: Not connected.',
        _logTag,
      );
      _connect(); // Attempt to reconnect
      return;
    }

    final clipDao = _projectDatabaseService.clipDao;
    if (clipDao == null) {
      logError(
        'Cannot send clips: ClipDAO is not available.',
        null,
        null,
        _logTag,
      );
      return;
    }

    try {
      final List<Track> tracks = _projectDatabaseService.tracksNotifier.value;
      final List<model_clip.ClipModel> allClipModels = [];

      for (final track in tracks) {
        final dbTrackClips = await clipDao.getClipsForTrack(track.id);
        for (final dbClip in dbTrackClips) {
          // Convert Drift Clip entity to ClipModel
          allClipModels.add(model_clip.ClipModel.fromDbData(dbClip));
        }
      }

      // Now call toJson() on ClipModel instances
      final List<Map<String, dynamic>> clipData =
          allClipModels.map((clipModel) => clipModel.toJson()).toList();

      final message = jsonEncode({'type': 'sync_clips', 'payload': clipData});

      _channel!.sink.add(message);
      logInfo('Sent ${allClipModels.length} clips to preview server.', _logTag);
    } catch (e, s) {
      logError('Error sending clips to preview server', e, s, _logTag);
    }
  }

  void dispose() {
    _channel?.sink.close();
    _isConnected = false;
    logInfo('PreviewSyncService disposed.', _logTag);
  }
}
