import 'dart:convert';
import 'dart:async';
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
  
  // Create a dedicated HTTP client with a more conservative connection limit
  // Default persistence client in http package creates too many simultaneous connections
  final http.Client _httpClient = http.Client();
  
  // Add a flag to track if we're currently processing a request
  bool _isProcessingRequest = false;
  
  // Track consecutive failures to detect server issues
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;
  
  // Rate limiting - track last successful request time
  DateTime _lastSuccessfulRequestTime = DateTime.now().subtract(const Duration(seconds: 5));
  static const Duration _minRequestInterval = Duration(milliseconds: 300);
  
  // Create a queue for pending requests to avoid overwhelming the server
  final _requestQueue = <_PendingRequest>[];
  bool _isProcessingQueue = false;

  PreviewHttpService({
    required TimelineNavigationViewModel timelineNavViewModel,
    required PreviewService previewService,
  })  : _timelineNavViewModel = timelineNavViewModel,
        _previewService = previewService {
    // Start the queue processor
    _startQueueProcessor();
  }
  
  void _startQueueProcessor() {
    // Process the queue periodically
    Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processNextQueuedRequest();
    });
  }
  
  void _processNextQueuedRequest() {
    if (_isProcessingQueue || _requestQueue.isEmpty) return;
    
    _isProcessingQueue = true;
    
    try {
      // Rate limiting check
      final now = DateTime.now();
      final timeSinceLastRequest = now.difference(_lastSuccessfulRequestTime);
      
      if (timeSinceLastRequest < _minRequestInterval) {
        // If we need to wait, schedule another check after the remaining time
        final remainingWaitTime = _minRequestInterval - timeSinceLastRequest;
        logInfo('Rate limiting: waiting ${remainingWaitTime.inMilliseconds}ms before next request', _logTag);
        // We'll let the next timer tick handle it
        _isProcessingQueue = false;
        return;
      }
      
      // Take the oldest request from the queue
      final request = _requestQueue.removeAt(0);
      
      // Execute the request function
      request.execute().then((_) {
        // Update the last successful request time
        _lastSuccessfulRequestTime = DateTime.now();
        // Complete the completer to notify caller
        request.completer.complete();
      }).catchError((error) {
        // Complete with error
        request.completer.completeError(error);
      }).whenComplete(() {
        // Mark as no longer processing
        _isProcessingQueue = false;
      });
    } catch (e) {
      logError('Error processing request queue', e, null, _logTag);
      _isProcessingQueue = false;
    }
  }
  
  // Helper method to queue a request
  Future<void> _queueRequest(Future<void> Function() requestFn) {
    final completer = Completer<void>();
    _requestQueue.add(_PendingRequest(requestFn, completer));
    
    // If queue is getting too large, remove older requests
    if (_requestQueue.length > 5) {
      logWarning('Request queue too large (${_requestQueue.length}), removing oldest request', _logTag);
      _requestQueue.removeAt(0);
    }
    
    return completer.future;
  }
  
  void dispose() {
    _httpClient.close();
    // Clear the queue
    _requestQueue.clear();
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

  /// Fetches the current frame from the Python HTTP server and updates the PreviewService.
  Future<void> fetchAndUpdateFrame() async {
    // Avoid multiple concurrent requests which can overload the server
    if (_isProcessingRequest) {
      logWarning('Skipping frame fetch - another request is in progress', _logTag);
      return;
    }
    
    _isProcessingRequest = true;
    
    try {
      // Queue this request to enforce rate limiting
      return await _queueRequest(() async {
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
        
        // Only get debug info if failures are low to reduce load
        if (_consecutiveFailures < 2) {
          await getTimelineDebugInfo();
        }
        
        // Try with current frame first
        if (await _tryFetchFrame(currentFrame)) {
          _consecutiveFailures = 0; // Reset on success
          return; // Successfully fetched
        }
        
        // If that failed, try with frame 0 as fallback
        if (currentFrame != 0) {
          logInfo('Retrying with frame 0 as fallback', _logTag);
          if (await _tryFetchFrame(0)) {
            _consecutiveFailures = 0; // Reset on success
            return; // Fallback successful
          }
        }
        
        // If all attempts failed, clear the preview
        logWarning('All frame fetch attempts failed, clearing preview', _logTag);
        _previewService.clearPreviewFrame();
        _consecutiveFailures++;
      });
    } finally {
      _isProcessingRequest = false;
    }
  }
  
  Future<void> _tryAlternatePort() async {
    // Try alternative ports that might be running the preview server
    final alternatePorts = [8080, 5000, 5001, 8000];
    
    for (final port in alternatePorts) {
      if (port.toString() == _baseUrl.split(':').last) continue; // Skip current port
      
      try {
        final alternateUrl = 'http://localhost:$port/health';
        logInfo('Trying alternate port: $alternateUrl', _logTag);
        final response = await _httpClient.get(Uri.parse(alternateUrl))
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
      final response = await _httpClient.get(url).timeout(const Duration(seconds: 3));

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

/// Helper class to represent a queued request
class _PendingRequest {
  final Future<void> Function() execute;
  final Completer<void> completer;
  
  _PendingRequest(this.execute, this.completer);
}