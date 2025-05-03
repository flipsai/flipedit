import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:watch_it/watch_it.dart';

import '../persistence/database/project_database.dart' show Clip, Track;
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
      final List<Clip> allDbClips = [];

      for (final track in tracks) {
        final trackClips = await clipDao.getClipsForTrack(track.id);
        allDbClips.addAll(trackClips);
            }

      final List<Map<String, dynamic>> clipData =
          allDbClips.map((clip) => clip.toJson()).toList();

      final message = jsonEncode({'type': 'sync_clips', 'payload': clipData});

      _channel!.sink.add(message);
      logInfo('Sent ${allDbClips.length} clips to preview server.', _logTag);
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
