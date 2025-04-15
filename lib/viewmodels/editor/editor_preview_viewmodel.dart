import 'dart:async';
import 'package:flutter/widgets.dart'; // For ValueNotifier, WidgetsBinding
import 'package:watch_it/watch_it.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/utils/logger.dart'; // Add logger import

/// Handles synchronization between the timeline and the preview player.
class EditorPreviewViewModel { // Remove LoggerExtension
  // Dependencies (injected)
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  final VideoPlayerManager _videoPlayerManager = di<VideoPlayerManager>();

  // --- State Notifiers ---
  // Notifier for the video URL currently under the playhead
  final ValueNotifier<String?> currentPreviewVideoUrlNotifier = ValueNotifier<String?>(null);

  // --- Internal State ---
  // Subscription listeners for timeline changes
  VoidCallback? _timelineFrameListener;
  VoidCallback? _timelineClipsListener;
  VoidCallback? _timelinePlayStateListener; // Listener for play state

  // --- Getters ---
  String? get currentPreviewVideoUrl => currentPreviewVideoUrlNotifier.value;

  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  EditorPreviewViewModel() {
    _subscribeToTimelineChanges();
  }

  @override
  void onDispose() {
    currentPreviewVideoUrlNotifier.dispose();

    // Remove timeline listeners
    if (_timelineFrameListener != null) {
      _timelineViewModel.currentFrameNotifier.removeListener(_timelineFrameListener!);
    }
    if (_timelinePlayStateListener != null) {
      _timelineViewModel.isPlayingNotifier.removeListener(_timelinePlayStateListener!);
    }
  }


  // --- Timeline Integration ---
  void _subscribeToTimelineChanges() {
    // Listen to changes in the timeline ViewModel (clips and current frame)
    _timelineFrameListener = _updatePreviewVideo;
    _timelineViewModel.currentFrameNotifier.addListener(_timelineFrameListener!);

    // Also listen to clip changes, as adding/removing clips affects the preview
    _timelineClipsListener = _updatePreviewVideo;

    // Add listener for play state changes
    _timelinePlayStateListener = _updatePreviewPlaybackState;
    _timelineViewModel.isPlayingNotifier.addListener(_timelinePlayStateListener!);

    // Initial update
    _updatePreviewVideo();
    _updatePreviewPlaybackState(); // Initial check for playback state
  }

  // Calculate the target frame within the clip's local timeline
  int _calculateLocalFrame(ClipModel clip, int globalFrame) {
      // Ensure the frame is within the clip's duration
      return (globalFrame - clip.startFrame).clamp(0, clip.durationFrames - 1).toInt();
  }

  // Updated to accept isPlaying state
  Future<void> _seekController(VideoPlayerController controller, int frame, bool isPlaying) async {
    // TODO: Get frameRate from project settings or timeline
    const double frameRate = 30.0;
    final targetPosition = Duration(
      milliseconds: (frame * 1000 / frameRate).round(),
    );

    if (controller.value.isInitialized &&
        (controller.value.position - targetPosition).abs() > const Duration(milliseconds: 50)) { // Tolerance for seeking
       logDebug(_logTag, "[PreviewController._seekController] Seeking ${controller.dataSource} to frame $frame (pos: $targetPosition). Timeline playing: $isPlaying"); // Use top-level function with tag
       await controller.seekTo(targetPosition);

       // Only pause if the timeline is NOT playing
       if (!isPlaying && controller.value.isPlaying) {
          logDebug(_logTag, "[PreviewController._seekController] Pausing controller after seek because timeline is paused."); // Use top-level function with tag
          await controller.pause();
       }
       // If timeline IS playing, we assume the play command will come separately
       // or is already handled by _updatePreviewPlaybackState, so we don't explicitly play here.
    } else if (controller.value.isInitialized && !isPlaying && controller.value.isPlaying) {
        // Ensure controller is paused if timeline isn't playing, even if no seek happened
        logDebug(_logTag, "[PreviewController._seekController] Pausing controller as timeline is paused (no seek needed)."); // Use top-level function with tag
        await controller.pause();
    } else if (controller.value.isInitialized && isPlaying && !controller.value.isPlaying) {
        // Ensure controller is playing if timeline is playing, even if no seek happened
        logDebug(_logTag, "[PreviewController._seekController] Playing controller as timeline is playing (no seek needed)."); // Use top-level function with tag
        await controller.play();
    }
  }

  // New method to handle play/pause commands based on timeline state
  Future<void> _updatePreviewPlaybackState() async {
     final bool isPlaying = _timelineViewModel.isPlaying;
     final String? currentUrl = currentPreviewVideoUrlNotifier.value;
     logDebug(_logTag, "[PreviewController._updatePreviewPlaybackState] Called. Timeline playing: $isPlaying, Current URL: $currentUrl"); // Use top-level function with tag

     if (currentUrl == null) return; // No video to control

     try {
       // Get the controller
       final (controller, _) = await _videoPlayerManager.getOrCreatePlayerController(currentUrl);

       if (!controller.value.isInitialized) {
          logDebug(_logTag, "[PreviewController._updatePreviewPlaybackState] Controller for $currentUrl not initialized yet. Waiting for init."); // Use top-level function with tag
          // Add a listener to apply state once initialized
          void Function()? initListener;
          initListener = () {
              if (controller.value.isInitialized) {
                  logDebug(_logTag, "[PreviewController._updatePreviewPlaybackState] Controller initialized. Applying play state: $isPlaying"); // Use top-level function with tag
                  if (isPlaying && !controller.value.isPlaying) {
                      controller.play();
                  } else if (!isPlaying && controller.value.isPlaying) {
                      controller.pause();
                  }
                  controller.removeListener(initListener!);
              }
          };
          controller.addListener(initListener);
          // Check immediately in case it initialized between getOrCreate and addListener
          if (controller.value.isInitialized) initListener();

          return;
       }

       // Apply the correct state if already initialized
       if (isPlaying && !controller.value.isPlaying) {
          logDebug(_logTag, "[PreviewController._updatePreviewPlaybackState] Playing controller for $currentUrl"); // Use top-level function with tag
          await controller.play();
       } else if (!isPlaying && controller.value.isPlaying) {
          logDebug(_logTag, "[PreviewController._updatePreviewPlaybackState] Pausing controller for $currentUrl"); // Use top-level function with tag
          await controller.pause();
       }
     } catch (e) {
        logError(_logTag, "[PreviewController._updatePreviewPlaybackState] Error getting/controlling controller for $currentUrl: $e"); // Use top-level function with tag
     }
  }

  void _updatePreviewVideo() {
    final globalFrame = _timelineViewModel.currentFrame;
    // Access clips safely, assuming TimelineViewModel provides a getter `clips`
    final clips = _timelineViewModel.clips;
    final bool isPlaying = _timelineViewModel.isPlaying; // Get current play state
    String? videoUrlToShow;
    ClipModel? foundClip;

    // Iterate in reverse to find the topmost clip at the current frame
    for (var clip in clips.reversed) {
      final int endFrame = clip.startFrame + clip.durationFrames;
      // Check if clip is video or image and contains the global frame
      if ((clip.type == ClipType.video || clip.type == ClipType.image) &&
          globalFrame >= clip.startFrame &&
          globalFrame < endFrame) {
        foundClip = clip;
        // Assume sourcePath holds the URL/path for the video/image
        videoUrlToShow = clip.sourcePath;
        break; // Found the topmost clip
      }
    }

    // Check if the URL needs to change
    bool urlChanged = currentPreviewVideoUrlNotifier.value != videoUrlToShow;
    if (urlChanged) {
       // Pause the old video if it exists and was playing
       final oldUrl = currentPreviewVideoUrlNotifier.value;
       if (oldUrl != null) {
           WidgetsBinding.instance.addPostFrameCallback((_) async {
               try {
                   final (oldController, _) = await _videoPlayerManager.getOrCreatePlayerController(oldUrl);
                   if (oldController.value.isInitialized && oldController.value.isPlaying) {
                       logDebug(_logTag, "[PreviewController._updatePreviewVideo] Pausing previous controller for $oldUrl"); // Use top-level function with tag
                       await oldController.pause();
                   }
               } catch (e) {
                   logError(_logTag, "[PreviewController._updatePreviewVideo] Error pausing previous controller for $oldUrl: $e"); // Use top-level function with tag
               }
           });
       }
       // Update the notifier *after* handling the old one
       currentPreviewVideoUrlNotifier.value = videoUrlToShow;
    }

    // If a clip is found, update the corresponding player controller
    if (foundClip != null && videoUrlToShow != null) {
      // Use addPostFrameCallback to ensure widget tree is built/stable
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final (controller, isNew) = await _videoPlayerManager.getOrCreatePlayerController(videoUrlToShow!);
          final localFrame = _calculateLocalFrame(foundClip!, globalFrame);

          if (!controller.value.isInitialized) {
             logDebug(_logTag, "[PreviewController._updatePreviewVideo post-frame] Waiting for controller initialization for seek/state..."); // Use top-level function with tag
             void Function()? initListener;
             initListener = () {
                if (controller.value.isInitialized) {
                  logDebug(_logTag, "[PreviewController._updatePreviewVideo post-frame] Controller initialized, seeking now."); // Use top-level function with tag
                  // Seek and apply correct initial play state after init
                  _seekController(controller, localFrame, isPlaying);
                  // Don't need _updatePreviewPlaybackState here as _seekController handles it
                  controller.removeListener(initListener!);
                }
             };
             controller.addListener(initListener);
             // Check immediately in case it initialized between getOrCreate and addListener
             if(controller.value.isInitialized) initListener();

          } else {
             // Already initialized: Seek to correct frame and ensure correct play state
             await _seekController(controller, localFrame, isPlaying);
             // Don't need _updatePreviewPlaybackState here as _seekController handles it
          }
        } catch (e) {
            logError(_logTag, "[PreviewController._updatePreviewVideo post-frame] Error getting/seeking/controlling controller: $e"); // Use top-level function with tag
        }
      });
    } else if (urlChanged && videoUrlToShow == null) {
       // If the URL changed to null (no clip at this frame)
       // The logic above already paused the previous controller if it existed.
       logDebug(_logTag, "[PreviewController._updatePreviewVideo] No clip found at frame $globalFrame. Preview URL is now null."); // Use top-level function with tag
    }
  }
} 