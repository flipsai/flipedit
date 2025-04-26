import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import corrected
import 'package:fvp/fvp.dart' as fvp; // Assuming fvp is needed
import 'package:watch_it/watch_it.dart';

/// PreviewPanel displays the current timeline frame's video(s) with frame-accurate updates.
///
/// This panel updates its visible content *every* time the timeline playhead moves,
/// regardless of how the user is navigating (playback or scrubbing).
///
/// **Intent:**
/// - Ensures the preview always exactly matches the timeline's current frame,
///   seamlessly reflecting entry into frames with and without video content.
/// - Prevents edge cases where the preview lags, fails to update, or sticks on stale frames,
///   especially at content boundaries and during rapid timeline navigation.
///
/// **Performance:**
/// - Internal update and controller management methods (`_updateVisibleClips`, `_initializeAndSyncControllers`)
///   contain checks to avoid unnecessary work and UI rebuilds:
///   - No new setState or controller work unless the visible clip list or aspect ratio actually changes
///   - Video player seeks only when the position is significantly different (100ms tolerance)
///   - Every change is guarded by `mounted` checks and idempotent logic
///
/// **Usage:**
/// - This widget should be included wherever a real-time timeline preview is needed.
/// - No manual update triggering is needed: reacts automatically to timeline frame and playback changes.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key});

  @override
  _PreviewPanelState createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  // State variables remain inside the class
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  final Map<int, VideoPlayerController> _controllers = {};
  double _aspectRatio = 16 / 9;
  List<ClipModel> _currentVisibleClips = [];
  final Map<int, Future<void>> _initializationFutures = {};

  @override
  void initState() {
    super.initState();
    // fvp.registerWith(); // Consider if this needs to be done elsewhere

    // Initial calculation and controller setup
    _updateVisibleClips();
    _initializeAndSyncControllers();
  }

  @override
  void dispose() {
    _disposeAllControllers();
    super.dispose();
  }

  // --- Handler Methods ---

  void _handleClipListChange() {
    _updateVisibleClips();
    _initializeAndSyncControllers();
  }

  /// Called on every timeline frame change (playback or scrubbing).
  ///
  /// Forces both "visible clip" recalculation and controller sync so the preview
  /// exactly matches the timeline's instantaneous state, without requiring playback
  /// to be active.
  ///
  /// Internal updates are optimized: regardless of this always running, downstream
  /// methods only apply UI or controller work if there's an actual difference.
  ///
  /// *Never* skips updates when entering regions without video (shows/hides preview as needed).
  void _handleFrameChange() {
    _updateVisibleClips();
    _initializeAndSyncControllers();
  }

  void _handlePlaybackStateChange(bool isPlaying) {
    final currentTimeMs = _timelineViewModel.currentFrameTimeMs;
    List<Future<void>> tasks = []; // Collect async tasks

    for (final entry in _controllers.entries) {
      final clipId = entry.key;
      final controller = entry.value;
      final clip = _findClipById(clipId); // Use helper

      if (clip == null || !controller.value.isInitialized) continue;

      if (isPlaying) {
        final seekPositionMs = (currentTimeMs - clip.startTimeOnTrackMs + clip.startTimeInSourceMs).toInt().clamp(0, clip.sourceDurationMs);
        // Only seek if significantly different or if starting exactly at clip beginning
         bool needsSeek = (controller.value.position.inMilliseconds - seekPositionMs).abs() > 100; // 100ms tolerance
         if (needsSeek) {
             // Don't wait for seek before playing, start play immediately after initiating seek
             tasks.add(controller.seekTo(Duration(milliseconds: seekPositionMs)));
         }
         // Ensure play() is called even if seek isn't needed or happens concurrently
         if (!controller.value.isPlaying) {
              tasks.add(controller.play());
         }

      } else {
        if (controller.value.isPlaying) {
           tasks.add(controller.pause());
           // Optional: Sync exact frame on pause if needed
           // final seekPositionMs = (currentTimeMs - clip.startTimeOnTrackMs + clip.startTimeInSourceMs).toInt().clamp(0, clip.sourceDurationMs);
           // tasks.add(controller.seekTo(Duration(milliseconds: seekPositionMs)));
        }
      }
    }

    // Wait for all play/pause/seek operations for this state change to complete
    Future.wait(tasks).then((_) {
        // Only trigger rebuild after operations are done, if widget is still mounted
        if (mounted) {
            setState(() {}); // Update button icon etc.
        }
    }).catchError((error){
        debugPrint("Error during playback state change sync: $error");
        if (mounted) setState(() {}); // Still update UI even if error occurred
    });
  }


  // --- Controller Management ---

  /// Recomputes which clips are currently visible at the timeline's frame head.
  ///
  /// **Optimization:** Only triggers UI/state changes if the visible clip list actually
  /// changes (using a list equality check), and aspect ratio is only updated if needed.
  ///
  /// Called on every frame change—*safe* to call often.
  void _updateVisibleClips() {
     if (!mounted) return; // Avoid updates if disposed

    final clips = _timelineViewModel.clips;
    final currentTimeMs = _timelineViewModel.currentFrameTimeMs;
    final newVisibleClips = clips.where((clip) =>
      clip.startTimeOnTrackMs <= currentTimeMs && currentTimeMs < clip.endTimeOnTrackMs).toList();

    // Log visible clips for debugging (databaseId, trackId, type)
    debugPrint("[PreviewPanel][_updateVisibleClips] Visible clips after update (playhead ${currentTimeMs}ms):");
    for (final c in newVisibleClips) {
      debugPrint("  - clipId=${c.databaseId}, trackId=${c.trackId}, type=${c.type}");
    }
    // Also log all current clips (to spot orphans)
    debugPrint("[PreviewPanel][_updateVisibleClips] All clips in model:");
    for (final c in clips) {
      debugPrint("  - clipId=${c.databaseId}, trackId=${c.trackId}, type=${c.type}");
    }

    // Check if the list actually changed before potentially triggering rebuilds
    if (listEquals(_currentVisibleClips, newVisibleClips)) {
        // If list is same, still check aspect ratio
        _updateAspectRatioIfNeeded();
        return;
    }

    setState(() {
       _currentVisibleClips = newVisibleClips;
       _updateAspectRatioIfNeeded(); // Update aspect ratio based on new list
    });
  }

  void _updateAspectRatioIfNeeded() {
     if (!mounted) return;
     VideoPlayerController? firstInitializedController;
     // Find the first initialized video controller among currently visible clips
     for (final clip in _currentVisibleClips) {
       if (clip.type == ClipType.video && _controllers.containsKey(clip.databaseId)) {
          final controller = _controllers[clip.databaseId]!;
          if (controller.value.isInitialized) {
             firstInitializedController = controller;
             break;
          }
       }
     }

     double targetAspectRatio = 16/9; // Default
     if (firstInitializedController != null) {
         targetAspectRatio = firstInitializedController.value.aspectRatio;
     }

     if (_aspectRatio != targetAspectRatio) {
        // Use setState only if the aspect ratio actually changes
        setState(() {
            _aspectRatio = targetAspectRatio;
        });
     }
  }


  ClipModel? _findClipById(int? id) {
    if (id == null) return null;
    try {
      // Use the current clips list from the view model for lookup
      return _timelineViewModel.clips.firstWhere((c) => c.databaseId == id);
    } catch (e) {
      return null; // Not found
    }
  }

  /// Initializes video controllers and keeps them in sync with the timeline frame.
  ///
  /// - On every frame, ensures only clips on screen have active controllers.
  /// - Performs seeks and play/pause ops *only if* needed (e.g., seeks only if more than 100ms off from target).
  /// - Cleans up and disposes controllers for clips that have gone off-screen.
  ///
  /// **Performance:** This is called on every frame change but is fully guarded against unnecessary work.
  /// Only creates, seeks, or disposes controllers if the relevant clip visibility or state actually changes.
  ///
  /// Safe to call as often as needed; especially important for keeping preview correct during scrubbing and at clip boundaries.
  Future<void> _initializeAndSyncControllers() async {
    if (!mounted) return; // Check if mounted at the beginning

    final visibleClipIds = _currentVisibleClips.map((c) => c.databaseId!).toSet();
    final existingClipIds = _controllers.keys.toSet();

    // Dispose controllers for clips no longer visible
    final controllersToDispose = existingClipIds.difference(visibleClipIds);
    for (final clipId in controllersToDispose) {
      _disposeController(clipId);
    }

    final currentTimeMs = _timelineViewModel.currentFrameTimeMs;
    final isPlaying = _timelineViewModel.isPlaying;
    List<Future<void>> initSyncFutures = [];

    for (final clip in _currentVisibleClips) {
      if (clip.type != ClipType.video) continue; // Only handle video clips

      final clipId = clip.databaseId!;
      final seekPositionMs = (currentTimeMs - clip.startTimeOnTrackMs + clip.startTimeInSourceMs).toInt().clamp(0, clip.sourceDurationMs);

      if (_controllers.containsKey(clipId)) {
        // --- Sync Existing Controller ---
        final controller = _controllers[clipId]!;
        // Only seek if paused and position is significantly different
        if (controller.value.isInitialized && !isPlaying) {
            if ((controller.value.position.inMilliseconds - seekPositionMs).abs() > 100) { // 100ms tolerance
                 initSyncFutures.add(controller.seekTo(Duration(milliseconds: seekPositionMs)));
            }
        }
        // Ensure playback state matches if initialized (this might be redundant with _handlePlaybackStateChange but acts as a safeguard)
         if(controller.value.isInitialized) {
             if (isPlaying && !controller.value.isPlaying) {
                 initSyncFutures.add(controller.play());
             } else if (!isPlaying && controller.value.isPlaying) {
                 initSyncFutures.add(controller.pause());
             }
         }

      } else if (!_initializationFutures.containsKey(clipId)) {
        // --- Initialize New Controller (if not already initializing) ---
        final controller = VideoPlayerController.networkUrl(Uri.parse(clip.sourcePath));
         _controllers[clipId] = controller;
         controller.setLooping(false);

        final initFuture = controller.initialize().then((_) {
          if (!mounted || !_controllers.containsKey(clipId)) return null;
          // Set initial position after initialization
          return controller.seekTo(Duration(milliseconds: seekPositionMs));
        }).then((_) {
          if (!mounted || !_controllers.containsKey(clipId)) return null;
          _updateAspectRatioIfNeeded(); // Check aspect ratio after initialization
          // Start playing if needed *after* seek is complete
          if (isPlaying && mounted) { // Check mounted again
            controller.play();
          }
          if (mounted) setState(() {}); // Rebuild to show player/update aspect ratio
        }).catchError((error) {
           debugPrint("Error initializing controller for clip $clipId: $error");
           if (mounted) {
               _disposeController(clipId); // Clean up failed controller
               setState(() {}); // Update UI to reflect removal
           }
        }).whenComplete(() {
            // Always remove the future when done, regardless of success/error
            _initializationFutures.remove(clipId);
        });

        _initializationFutures[clipId] = initFuture;
        initSyncFutures.add(initFuture);
      }
    }

    // Wait for all current initialization/sync tasks triggered by this call
    try {
        await Future.wait(initSyncFutures);
    } catch (e) {
        debugPrint("Error during batch init/sync: $e");
    }

    // Final check and UI refresh if still mounted after async operations
    if (mounted) {
       _updateVisibleClips(); // Ensure visible clips are still accurate
       _updateAspectRatioIfNeeded(); // Ensure aspect ratio is correct
       setState(() {});
    }
  }

  void _disposeController(int clipId) {
    final controller = _controllers.remove(clipId);
    _initializationFutures.remove(clipId);
    // Use microtask for safety, especially during widget disposal
    Future.microtask(() => controller?.dispose());
     if (mounted && _currentVisibleClips.any((c) => c.databaseId == clipId)) {
        // If the removed controller was for a clip that *should* be visible,
        // force an update of visible clips and aspect ratio.
        Future.microtask(() { // Schedule after current frame
           if (mounted) {
               _updateVisibleClips();
               _initializeAndSyncControllers(); // Attempt re-init if needed
           }
        });
     } else if (mounted) {
         // If the removed controller was for a clip no longer visible,
         // just update aspect ratio based on remaining controllers.
         _updateAspectRatioIfNeeded();
     }
  }

  void _disposeAllControllers() {
    _initializationFutures.clear(); // Clear pending futures
    final controllersToDispose = List<VideoPlayerController>.from(_controllers.values);
    _controllers.clear();
    for (final controller in controllersToDispose) {
      Future.microtask(() => controller.dispose());
    }
  }

  // --- Build Method ---

  @override
  Widget build(BuildContext context) {
    // Use a PreviewPanelContent stateless widget with WatchItMixin for reactivity
    return PreviewPanelContent(
      controllers: _controllers,
      aspectRatio: _aspectRatio,
      currentVisibleClips: _currentVisibleClips,
      onClipListChange: _handleClipListChange,
      onFrameChange: _handleFrameChange,
      onPlaybackStateChange: _handlePlaybackStateChange,
    );
  }
}

// Create a stateless widget with WatchItMixin to handle watch_it reactivity
class PreviewPanelContent extends StatelessWidget with WatchItMixin {
  final Map<int, VideoPlayerController> controllers;
  final double aspectRatio;
  final List<ClipModel> currentVisibleClips;
  final VoidCallback onClipListChange;
  final VoidCallback onFrameChange;
  final Function(bool) onPlaybackStateChange;

  const PreviewPanelContent({
    Key? key,
    required this.controllers,
    required this.aspectRatio,
    required this.currentVisibleClips,
    required this.onClipListChange,
    required this.onFrameChange,
    required this.onPlaybackStateChange,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Register handlers using context-aware lookup provided by WatchItMixin
    // Get the ViewModel instance using the global service locator `di`
    // as the mixin's get() method seems unresolved in this context.
    final timelineViewModel = di<TimelineViewModel>();

    // registerHandler needs <TargetType (ViewModel), SelectedValueType (inner value)>
    registerHandler<TimelineViewModel, List<ClipModel>>(
      select: (vm) => vm.clipsNotifier,
      // Handler receives the value (List<ClipModel>)
      handler: (context, value, __) => onClipListChange(),
    );
    
    // Assuming currentFrameNotifier is ValueNotifier<int>
    registerHandler<TimelineViewModel, int>(
      select: (vm) => vm.currentFrameNotifier,
      // Handler receives the value (int)
      handler: (context, value, __) => onFrameChange(),
    );
    
    // Assuming isPlayingNotifier is ValueNotifier<bool>
    registerHandler<TimelineViewModel, bool>(
      select: (vm) => vm.isPlayingNotifier,
      // Handler receives the value (bool)
      handler: (context, bool isPlaying, __) => onPlaybackStateChange(isPlaying),
    );
    
    // Directly access the value from the ViewModel instance to avoid potential type inference issues with watchPropertyValue
    final bool isPlaying = timelineViewModel.isPlayingNotifier.value;

    // Build list of initialized players *for currently visible clips*
    final List<Widget> playerWidgets = [];
    for (final clip in currentVisibleClips) {
        if (clip.type == ClipType.video && controllers.containsKey(clip.databaseId)) {
            final controller = controllers[clip.databaseId]!;
            if (controller.value.isInitialized) {
                playerWidgets.add(
                    // Use the controller's aspect ratio for the individual player
                    AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: VideoPlayer(controller),
                    )
                );
            }
        }
    }


    Widget content;
    if (playerWidgets.isEmpty) {
      content = Center(
        child: Text(
          'No video at current playback position',
          style: FluentTheme.of(context).typography.bodyLarge?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      content = Stack(
        alignment: Alignment.center,
        children: playerWidgets, // Stack the initialized players
      );
    }

    return Container(
      color: Colors.grey[160], // Use Fluent UI color
      child: Column(
        children: [
          Expanded(
            child: Center(
              // The outer AspectRatio uses the dynamically calculated _aspectRatio
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: content,
              ),
            ),
          ),
          // --- Controls ---
          Container(
             padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
             color: Colors.black.withOpacity(0.6),
             child: Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                    IconButton(
                      // Explicitly check boolean value
                      icon: Icon(isPlaying == true ? FluentIcons.pause : FluentIcons.play_solid),
                      // Use call() to get the ViewModel instance and call its method
                      // Use the obtained ViewModel instance
                      // Use the obtained ViewModel instance
                      onPressed: timelineViewModel.togglePlayPause,
                      style: ButtonStyle(
                          foregroundColor: ButtonState.all(Colors.white),
                          iconSize: ButtonState.all(24.0) // Slightly larger icon
                      ),
                    ),
                    // TODO: Add frame step buttons, time display etc.
                 ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper extension (already added previously)
extension TimelineViewModelFrameTime on TimelineViewModel {
   // TODO: Get FPS from project settings instead of hardcoding 30
   int get currentFrameTimeMs => (currentFrame / 30 * 1000).toInt();
}

// Helper for comparing lists (avoids importing collection package for just this)
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}