import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

/// ViewModel for the WebSocket frame player with client-side caching
class WebSocketFramePlayerViewModel extends ChangeNotifier {
  /// The WebSocket channel
  WebSocketChannel? _channel;
  
  /// Whether the player is connected to the WebSocket
  bool _isConnected = false;
  
  /// Whether the player is playing
  bool _isPlaying = false;
  
  /// The current frame index
  int _currentFrameIndex = 0;
  
  /// The current frame as a Uint8List
  Uint8List? _currentFrameBytes;
  
  /// The total number of frames in the video
  int _totalFrames = 0;
  
  /// Custom cache manager for frames
  late final CacheManager _cacheManager; // Changed from DefaultCacheManager
  
  /// Video ID for cache key generation
  final String _videoId = const Uuid().v4();
  
  /// Maximum number of frames to cache (used for CacheManager config)
  static const int _maxCacheObjects = 240; // Cache about 8 seconds at 30fps, or 4s at 60fps
  static const String _customCacheKey = 'customFrameCache'; // Key for custom CacheManager
  
  /// Completer for requested frames, to avoid requesting the same frame multiple times
  final Map<int, Completer<Uint8List>> _frameRequests = {};
  
  /// Server URL
  String? _serverUrl;
  
  /// Constructor
  WebSocketFramePlayerViewModel() {
    _cacheManager = CacheManager(
      Config(
        _customCacheKey,
        stalePeriod: const Duration(minutes: 30), // How long to keep files in cache
        maxNrOfCacheObjects: _maxCacheObjects,    // Max number of objects in cache
      ),
    );
  }
  
  /// Getters
  bool get isConnected => _isConnected;
  bool get isPlaying => _isPlaying;
  int get currentFrameIndex => _currentFrameIndex;
  Uint8List? get currentFrameBytes => _currentFrameBytes;
  int get totalFrames => _totalFrames;
  String? get serverUrl => _serverUrl;
  
  /// Connect to the WebSocket server
  Future<void> connect(String url) async {
    if (_isConnected) {
      disconnect();
    }
    
    try {
      _serverUrl = url;
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      
      // Listen for incoming frames
      _channel!.stream.listen(
        _handleServerMessage,
        onError: _handleConnectionError,
        onDone: _handleConnectionClosed,
      );
      
      // Send initial state request
      _requestStateUpdate();
      
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _channel = null;
      rethrow;
    }
  }
  
  /// Disconnect from the WebSocket server
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
    }
    _isConnected = false;
    _isPlaying = false;
    notifyListeners();
  }
  
  /// Play the video
  void play() {
    if (!_isConnected) return;
    
    _sendCommand('play');
    _isPlaying = true;
    notifyListeners();
  }
  
  /// Pause the video
  void pause() {
    if (!_isConnected) return;
    
    _sendCommand('pause');
    _isPlaying = false;
    notifyListeners();
  }
  
  /// Seek to a specific frame
  Future<void> seekToFrame(int frameIndex) async {
    if (!_isConnected) return;
    
    // Clamp frame index to valid range
    frameIndex = frameIndex.clamp(0, _totalFrames - 1);
    
    // Generate cache key for this frame
    final cacheKey = _generateCacheKey(frameIndex);
    
    try {
      // Try to get frame from cache
      final fileInfo = await _cacheManager.getFileFromCache(cacheKey);
      
      if (fileInfo != null) {
        // Frame is in cache, read it
        final file = fileInfo.file;
        final bytes = await file.readAsBytes();
        _updateCurrentFrame(frameIndex, bytes);
        return;
      }
      
      // If not in cache, request it from server
      // Stop playback during seeking
      if (_isPlaying) {
        pause();
      }
      
      // Send seek command
      _sendCommand('seek:$frameIndex');
      
      // Wait for the frame to be received (with timeout)
      try {
        Uint8List frameBytes = await _requestFrame(frameIndex).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Timeout waiting for frame $frameIndex');
          }
        );
        
        _updateCurrentFrame(frameIndex, frameBytes);
      } catch (e) {
        debugPrint('Error seeking to frame $frameIndex: $e');
      }
    } catch (e) {
      debugPrint('Error accessing cache for frame $frameIndex: $e');
      // Fall back to requesting from server
      _sendCommand('seek:$frameIndex');
    }
  }
  
  /// Generate a cache key for a frame
  String _generateCacheKey(int frameIndex) {
    return 'frame_${_videoId}_$frameIndex';
  }
  
  /// Request frame from server and return a Future that completes when the frame is received
  Future<Uint8List> _requestFrame(int frameIndex) {
    // Check if we already have a pending request for this frame
    if (_frameRequests.containsKey(frameIndex)) {
      return _frameRequests[frameIndex]!.future;
    }
    
    // Create a new request
    final completer = Completer<Uint8List>();
    _frameRequests[frameIndex] = completer;
    
    return completer.future;
  }
  
  /// Send a command to the server
  void _sendCommand(String command) {
    if (_channel != null) {
      _channel!.sink.add(command);
    }
  }
  
  /// Handle an incoming message from the server
  void _handleServerMessage(dynamic message) {
    if (message is String) {
      // Check if it's a JSON message
      if (message.startsWith('{')) {
        try {
          final jsonData = json.decode(message);
          _handleJsonMessage(jsonData);
          return;
        } catch (e) {
          // Not valid JSON, continue with other checks
        }
      }
      
      // If it's base64 encoded frame data
      try {
        final frameBytes = base64Decode(message);
        _handleFrameData(frameBytes);
      } catch (e) {
        debugPrint('Error decoding frame data: $e');
      }
    }
  }
  
  /// Handle JSON messages from the server
  void _handleJsonMessage(Map<String, dynamic> jsonData) {
    // Handle state updates
    if (jsonData['type'] == 'state') {
      _isPlaying = jsonData['playing'] == true;
      int newFrameIndex = jsonData['frame'] ?? 0;
      
      // Update total frames if provided
      if (jsonData.containsKey('totalFrames')) {
        _totalFrames = jsonData['totalFrames'];
      }
      
      // If the frame index has changed, seek to it
      if (newFrameIndex != _currentFrameIndex) {
        seekToFrame(newFrameIndex);
      }
      
      notifyListeners();
    }
  }
  
  /// Handle frame data from the server
  Future<void> _handleFrameData(Uint8List frameBytes) async {
    // Assume this is the frame for the current frame index
    // Cache the frame
    await _addToCache(_currentFrameIndex, frameBytes);
    
    // Update current frame
    _updateCurrentFrame(_currentFrameIndex, frameBytes);
    
    // Complete any pending request for this frame
    if (_frameRequests.containsKey(_currentFrameIndex)) {
      _frameRequests[_currentFrameIndex]!.complete(frameBytes);
      _frameRequests.remove(_currentFrameIndex);
    }
    
    // If playing, the next frame will come automatically
    // If not playing, we stay on this frame
  }
  
  /// Update the current frame
  void _updateCurrentFrame(int frameIndex, Uint8List frameBytes) {
    _currentFrameIndex = frameIndex;
    _currentFrameBytes = frameBytes;
    notifyListeners();
  }
  
  /// Add a frame to the cache
  Future<void> _addToCache(int frameIndex, Uint8List frameBytes) async {
    String cacheKey = _generateCacheKey(frameIndex); // Declare here
    try {
      // Add frame to cache. flutter_cache_manager will handle LRU eviction
      // based on maxNrOfCacheObjects configured in the custom CacheManager.
      await _cacheManager.putFile(
        cacheKey,
        frameBytes,
        key: cacheKey, // Using the URL as the key for the cache manager
        // maxAge is now controlled by stalePeriod in CacheManager Config
      );
      // Removed manual eviction logic.
    } catch (e) {
      debugPrint('Error adding frame to cache for key $cacheKey: $e');
    }
  }
  
  /// Handle WebSocket connection errors
  void _handleConnectionError(error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
    _isPlaying = false;
    notifyListeners();
  }
  
  /// Handle WebSocket connection closure
  void _handleConnectionClosed() {
    _isConnected = false;
    _isPlaying = false;
    notifyListeners();
  }
  
  /// Request a state update from the server
  void _requestStateUpdate() {
    if (_channel != null) {
      // Most servers understand a "state" command to return current playback state
      _sendCommand('state');
    }
  }
  
  /// Clear the frame cache
  Future<void> clearCache() async {
    try {
      await _cacheManager.emptyCache();
      _frameRequests.clear();
      notifyListeners(); // Notify listeners after clearing cache
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
  
  /// Refresh timeline data from the database
  void refreshFromDatabase() {
    if (_isConnected) {
      _sendCommand('refresh_from_db');
    }
  }
  
  @override
  void dispose() {
    disconnect();
    clearCache();
    super.dispose();
  }
}