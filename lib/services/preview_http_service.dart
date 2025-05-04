import 'dart:convert';
import 'package:http/http.dart' as http;
import '../viewmodels/timeline_navigation_viewmodel.dart';
import '../services/preview_service.dart';
import '../utils/logger.dart';

class PreviewHttpService {
  final TimelineNavigationViewModel _timelineNavViewModel;
  final PreviewService _previewService;
  final String _logTag = 'PreviewHttpService';

  // Assuming the Python server runs on localhost and the port defined in preview_server.py
  // TODO: Make this configurable if necessary
  final String _baseUrl = 'http://localhost:8081';

  PreviewHttpService({
    required TimelineNavigationViewModel timelineNavViewModel,
    required PreviewService previewService,
  })  : _timelineNavViewModel = timelineNavViewModel,
        _previewService = previewService;

  /// Checks health and connectivity to the preview server
  Future<bool> checkHealth() async {
    try {
      final url = Uri.parse('$_baseUrl/health');
      logInfo('Checking preview server health at $url', _logTag);
      final response = await http.get(url).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        logInfo('Preview server is healthy: ${response.body}', _logTag);
        return true;
      } else {
        logWarning('Preview server health check failed with status ${response.statusCode}', _logTag);
        return false;
      }
    } catch (e, stackTrace) {
      logError('Preview server health check error', e, stackTrace, _logTag);
      return false;
    }
  }

  /// Fetches the current timeline state from the debug endpoint
  Future<Map<String, dynamic>?> getTimelineDebugInfo() async {
    try {
      final url = Uri.parse('$_baseUrl/debug/timeline');
      logInfo('Fetching timeline debug info from $url', _logTag);
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      
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
        
        return data;
      } else {
        logWarning(
          'Failed to fetch timeline debug info. Status: ${response.statusCode}',
          _logTag,
        );
        return null;
      }
    } catch (e, stackTrace) {
      logError('Error fetching timeline debug info', e, stackTrace, _logTag);
      return null;
    }
  }

  /// Fetches the current frame from the Python HTTP server and updates the PreviewService.
  Future<void> fetchAndUpdateFrame() async {
    // First check server health
    final bool serverHealthy = await checkHealth();
    if (!serverHealthy) {
      logWarning('Skipping frame fetch - server health check failed', _logTag);
      // Try alternate ports if health check fails
      await _tryAlternatePort();
      return;
    }
    
    // Get the current frame from the correct ViewModel
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    logInfo('Attempting frame refresh for timeline position $currentFrame', _logTag);
    
    // Get debug info to compare with actual frame fetch
    await getTimelineDebugInfo();
    
    // Try with current frame first
    if (await _tryFetchFrame(currentFrame)) {
      return; // Successfully fetched
    }
    
    // If that failed, try with frame 0 as fallback
    if (currentFrame != 0) {
      logInfo('Retrying with frame 0 as fallback', _logTag);
      if (await _tryFetchFrame(0)) {
        return; // Fallback successful
      }
    }
    
    // If all attempts failed, clear the preview
    logWarning('All frame fetch attempts failed, clearing preview', _logTag);
    _previewService.clearPreviewFrame();
  }
  
  Future<void> _tryAlternatePort() async {
    // Try alternative ports that might be running the preview server
    final alternatePorts = [8080, 5000, 5001, 8000];
    
    for (final port in alternatePorts) {
      if (port.toString() == _baseUrl.split(':').last) continue; // Skip current port
      
      try {
        final alternateUrl = 'http://localhost:$port/health';
        logInfo('Trying alternate port: $alternateUrl', _logTag);
        final response = await http.get(Uri.parse(alternateUrl))
            .timeout(const Duration(seconds: 1));
            
        if (response.statusCode == 200) {
          logInfo('Found responsive server on port $port!', _logTag);
          return;
        }
      } catch (e) {
        // Ignore connection errors for alternate ports
      }
    }
    
    logWarning('No alternate preview servers found on common ports', _logTag);
  }
  
  /// Attempts to fetch a specific frame and returns success status
  Future<bool> _tryFetchFrame(int frameIndex) async {
    final url = Uri.parse('$_baseUrl/get_frame/$frameIndex');
    logInfo('Fetching frame $frameIndex from $url', _logTag);

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        logInfo('Received frame $frameIndex successfully (${response.bodyBytes.length} bytes)', _logTag);
        _previewService.updatePreviewFrameFromBytes(response.bodyBytes);
        return true;
      } else {
        logWarning(
          'Failed to fetch frame $frameIndex. Status: ${response.statusCode}, Body: ${response.body.substring(0, response.body.length.clamp(0, 100))}...', 
          _logTag
        );
        return false;
      }
    } catch (e, stackTrace) {
      logError('Error fetching frame $frameIndex', e, stackTrace, _logTag);
      return false;
    }
  }
}