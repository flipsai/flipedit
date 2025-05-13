import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class PreviewHttpService {
  final String _logTag = 'PreviewHttpService';

  // Assuming the Python server runs on localhost and the port defined in preview_server.py
  // TODO: Make this configurable if necessary
  final String _baseUrl = 'http://localhost:8085'; // Updated to match the new port in assets/main.py
  
  // Create a dedicated HTTP client with a more conservative connection limit
  // Default persistence client in http package creates too many simultaneous connections
  final http.Client _httpClient = http.Client();
  
  // Track consecutive failures to detect server issues
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;
  
  // Rate limiting, queueing, and _previewService for frame updates are removed as individual frame fetching is obsolete.

  PreviewHttpService() { // Removed previewService parameter
    // No queue processor needed now
  }
  
  void dispose() {
    _httpClient.close();
  }

  /// Returns the URL for the video stream, optionally starting from a specific frame.
  String getStreamUrl({int? startFrame, int duration = 10}) { // Added duration parameter
    var url = '$_baseUrl/video_stream'; // Changed to video_stream endpoint
    if (startFrame != null) {
      url += '?start_frame=$startFrame&duration=$duration'; // Added duration to query params
    } else {
      url += '?duration=$duration'; // Added duration if startFrame is null
    }
    logInfo('Generated stream URL: $url', _logTag);
    return url;
  }

  /// Sends timeline updates to the Python server.
  Future<bool> updateTimeline(List<Map<String, dynamic>> videos) async {
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      logWarning('Skipping timeline update due to multiple failures', _logTag);
      return false;
    }

    try {
      final url = Uri.parse('$_baseUrl/api/timeline/update');
      final body = jsonEncode({'videos': videos});
      logInfo('Sending timeline update to $url with body: ${body.substring(0, body.length > 200 ? 200 : body.length)}...', _logTag); // Log truncated body

      final response = await _httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        logInfo('Timeline update successful: ${response.body}', _logTag);
        _consecutiveFailures = 0;
        return true;
      } else {
        logWarning('Timeline update failed with status ${response.statusCode}: ${response.body}', _logTag);
        _consecutiveFailures++;
        return false;
      }
    } catch (e, stackTrace) {
      logError('Error sending timeline update', e, stackTrace, _logTag);
      _consecutiveFailures++;
      return false;
    }
  }

  /// Sends canvas dimension updates to the Python server.
  Future<bool> updateCanvasDimensions(int width, int height) async {
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      logWarning('Skipping canvas dimensions update due to multiple failures', _logTag);
      return false;
    }

    try {
      final url = Uri.parse('$_baseUrl/api/canvas/dimensions');
      final body = jsonEncode({'width': width, 'height': height});
      logInfo('Sending canvas dimensions update to $url with body: $body', _logTag);

      final response = await _httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        logInfo('Canvas dimensions update successful: ${response.body}', _logTag);
        _consecutiveFailures = 0;
        return true;
      } else {
        logWarning('Canvas dimensions update failed with status ${response.statusCode}: ${response.body}', _logTag);
        _consecutiveFailures++;
        return false;
      }
    } catch (e, stackTrace) {
      logError('Error sending canvas dimensions update', e, stackTrace, _logTag);
      _consecutiveFailures++;
      return false;
    }
  }

  /// Checks health and connectivity to the preview server
  Future<bool> checkHealth() async {
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      // If we've had multiple consecutive failures, wait longer before retry
      logWarning('Multiple consecutive failures detected, waiting before health check', _logTag);
      await Future.delayed(const Duration(seconds: 2));
    }
    
    try {
      final url = Uri.parse('$_baseUrl/health');
      logInfo('Checking preview server health at $url', _logTag);
      final response = await _httpClient.get(url).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        logInfo('Preview server is healthy: ${response.body}', _logTag);
        _consecutiveFailures = 0; // Reset failure counter on success
        return true;
      } else {
        logWarning('Preview server health check failed with status ${response.statusCode}', _logTag);
        _consecutiveFailures++;
        return false;
      }
    } catch (e, stackTrace) {
      logError('Preview server health check error', e, stackTrace, _logTag);
      _consecutiveFailures++;
      return false;
    }
  }

  /// Fetches the current timeline state from the debug endpoint
  Future<Map<String, dynamic>?> getTimelineDebugInfo() async {
    // Don't attempt if there are too many consecutive failures
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      logWarning('Skipping timeline debug info due to multiple failures', _logTag);
      return null;
    }
    
    try {
      final url = Uri.parse('$_baseUrl/debug/timeline');
      logInfo('Fetching timeline debug info from $url', _logTag);
      final response = await _httpClient.get(url).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        logInfo('Received timeline debug info: ${data.length} entries', _logTag);
        
        // Log clip dimensions for comparison
        final clips = data['clips'] as List<dynamic>;
        logInfo('Debug endpoint reports ${clips.length} clips', _logTag);
        for (int i = 0; i < clips.length; i++) {
          final clip = clips[i] as Map<String, dynamic>;
          final trackTime = clip['track_time_ms'] as Map<String, dynamic>;
          final sourceTime = clip['source_time_ms'] as Map<String, dynamic>;
          logInfo(
            'Debug Clip[$i] track time: ${trackTime["start"]}-${trackTime["end"]}ms, ' +
            'source time: ${sourceTime["start"]}-${sourceTime["end"]}ms',
            _logTag,
          );
        }
        
        _consecutiveFailures = 0; // Reset failure counter
        return data;
      } else {
        logWarning(
          'Failed to fetch timeline debug info. Status: ${response.statusCode}',
          _logTag,
        );
        _consecutiveFailures++;
        return null;
      }
    } catch (e, stackTrace) {
      logError('Error fetching timeline debug info', e, stackTrace, _logTag);
      _consecutiveFailures++;
      return null;
    }
  }

}