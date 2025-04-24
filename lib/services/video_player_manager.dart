import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:fvp/src/video_player_mdk.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flipedit/utils/logger.dart';
import 'dart:io' show File;
import 'package:flutter/services.dart' show PlatformException;

class VideoPlayerManager {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  // Store VideoPlayerControllers instead of mdk.Players
  final Map<String, VideoPlayerController> _controllers = {};

  // Returns the controller and a boolean indicating if it was newly created.
  Future<(VideoPlayerController, bool)> getOrCreatePlayerController(String videoUrl) async {
    if (_controllers.containsKey(videoUrl)) {
      return (_controllers[videoUrl]!, false); // Return existing controller
    } else {
      // Create and initialize a new VideoPlayerController
      // Use file constructor for local files, network for URLs
      final controller = _createController(videoUrl);
      logDebug("Creating controller for $videoUrl", _logTag);
      
      try {
        // Initialize the controller. This handles loading and getting the first frame.
        // The video_player package handles timeouts internally, but we can add one here
        // for the overall operation if desired, though it's often better to rely on the widget's loading state.
        const initTimeout = Duration(seconds: 30); // Increase timeout for MKV files
        await controller.initialize().timeout(initTimeout, onTimeout: () {
          logWarning("Initialization timeout for $videoUrl after $initTimeout", _logTag);
          throw TimeoutException(
            'VideoPlayerController initialization timed out after $initTimeout for $videoUrl',
            initTimeout,
          );
        });
        logDebug("Controller initialized for $videoUrl", _logTag);

        // Optionally set looping or add listeners
        controller.setLooping(true);

        // --- MKV Fix: Explicitly select the first audio track ---
        try {
          if (VideoPlayerPlatform.instance is MdkVideoPlayerPlatform) {
            final mdkPlatform = VideoPlayerPlatform.instance as MdkVideoPlayerPlatform;
            final textureId = controller.textureId;
            if (textureId >= 0) {
              final mediaInfo = mdkPlatform.getMediaInfo(textureId);
              if (mediaInfo != null && (mediaInfo.audio?.length ?? 0) > 1) {
                logInfo("Multiple audio tracks detected for $videoUrl (${mediaInfo.audio?.length ?? 0}). Selecting track 0.", _logTag);
                mdkPlatform.setAudioTracks(textureId, [0]);
              } else if (mediaInfo != null && (mediaInfo.audio?.isNotEmpty ?? false)) {
                logDebug("Single audio track detected for $videoUrl. No action needed.", _logTag);
              } else {
                logDebug("No audio tracks detected or MediaInfo not available for $videoUrl.", _logTag);
              }
            } else {
              logWarning("Invalid textureId ($textureId) for $videoUrl, cannot set audio track.", _logTag);
            }
          } else {
            logDebug("Not using FVP/MDK platform, skipping audio track selection for $videoUrl.", _logTag);
          }
        } catch (audioError) {
          logError("Error selecting audio track for $videoUrl: $audioError", null, null, _logTag);
        }
        // --- End MKV Fix ---

        // No need to set paused, it starts paused by default

        _controllers[videoUrl] = controller;
        return (controller, true); // Return new controller
      } catch (e) {
        if (kDebugMode) {
          logError("Error initializing VideoPlayerController for $videoUrl: $e", null, null, _logTag);
          if (e is PlatformException) {
            logError("PlatformException details - code: ${e.code}, message: ${e.message}, details: ${e.details}", null, null, _logTag);
          }
        }
        controller.dispose(); // Clean up failed controller
        // If it's a local file, try alternative URI format before giving up
        if (videoUrl.startsWith('file://') || videoUrl.startsWith('/')) {
          String altPath = videoUrl.startsWith('file://') ? videoUrl : 'file://$videoUrl';
          logDebug("Retrying with alternative URI format: $altPath", _logTag);
          try {
            final altController = VideoPlayerController.networkUrl(Uri.parse(altPath));
            await altController.initialize().timeout(const Duration(seconds: 30), onTimeout: () {
              logWarning("Initialization timeout for alternative URI $altPath after 30s", _logTag);
              throw TimeoutException('VideoPlayerController initialization timed out for alternative URI $altPath', const Duration(seconds: 30));
            });
            logDebug("Controller initialized with alternative URI for $altPath", _logTag);
            altController.setLooping(true);
            _controllers[videoUrl] = altController;
            return (altController, true);
          } catch (altError) {
            logError("Alternative URI format also failed for $altPath: $altError", null, null, _logTag);
            controller.dispose();
            rethrow;
          }
        } else {
          rethrow;
        }
      }
    }
  }

  // Helper method to create the appropriate controller based on input
  VideoPlayerController _createController(String videoUrl) {
    if (videoUrl.startsWith('file://') || videoUrl.startsWith('/')) {
      String filePath = videoUrl.startsWith('file://') ? videoUrl.replaceFirst('file://', '') : videoUrl;
      logDebug("Attempting to load file from path: $filePath", _logTag);
      final file = File(filePath);
      if (!file.existsSync()) {
        logError("File does not exist at path: $filePath", null, null, _logTag);
      } else {
        logDebug("File exists at path: $filePath", _logTag);
      }
      // Try using the file directly
      logDebug("Creating controller with direct file path: $filePath", _logTag);
      return VideoPlayerController.file(file);
    } else {
      logDebug("Attempting to load network URL: $videoUrl", _logTag);
      return VideoPlayerController.networkUrl(Uri.parse(videoUrl));
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
             logError("Error setting state for controller with URL ${controller.dataSource}", e, null, _logTag);
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