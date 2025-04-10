import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class VideoPlayerManager {
  // Store VideoPlayerControllers instead of mdk.Players
  final Map<String, VideoPlayerController> _controllers = {};

  // Returns the controller and a boolean indicating if it was newly created.
  Future<(VideoPlayerController, bool)> getOrCreatePlayerController(String videoUrl) async {
    if (_controllers.containsKey(videoUrl)) {
      return (_controllers[videoUrl]!, false); // Return existing controller
    } else {
      // Create and initialize a new VideoPlayerController
      // Use network constructor for URLs
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      
      try {
        // Initialize the controller. This handles loading and getting the first frame.
        // The video_player package handles timeouts internally, but we can add one here
        // for the overall operation if desired, though it's often better to rely on the widget's loading state.
        const initTimeout = Duration(seconds: 20); // Increase timeout slightly for network init
        await controller.initialize().timeout(initTimeout, onTimeout: () {
           throw TimeoutException(
            'VideoPlayerController initialization timed out after $initTimeout for $videoUrl',
            initTimeout,
          );
        });

        // Optionally set looping or add listeners
        controller.setLooping(true);
        // No need to set paused, it starts paused by default

        _controllers[videoUrl] = controller;
        return (controller, true); // Return new controller
      } catch (e) {
        if (kDebugMode) {
            print("Error initializing VideoPlayerController for $videoUrl: $e");
        }
        controller.dispose(); // Clean up failed controller
        rethrow; // Re-throw the error to be handled by the caller (e.g., FutureBuilder)
      }
    }
  }

  // Get an existing controller, returns null if not found.
  VideoPlayerController? getController(String videoUrl) {
    return _controllers[videoUrl];
  }

  // --- Playback Control Methods ---
  
  // Set the playback state for all managed controllers
  void setAllPlayersState(bool play) {
    for (final controller in _controllers.values) {
      try {
          if (play) {
            controller.play();
          } else {
            controller.pause();
          }
      } catch (e) {
           if (kDebugMode) {
             print("Error setting state for controller with URL ${controller.dataSource}: $e");
           }
      }
    }
  }

  void playAll() {
    setAllPlayersState(true);
  }

  void pauseAll() {
    setAllPlayersState(false);
  }

  // --- Disposal Methods ---

  // Dispose a specific controller
  void disposeController(String videoUrl) {
    final controller = _controllers.remove(videoUrl);
    controller?.dispose(); // Call dispose on the controller
  }

  // Dispose all managed controllers
  void disposeAll() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
} 