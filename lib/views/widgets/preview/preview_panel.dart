import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart'; // Import corrected
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:fvp/fvp.dart' as fvp; // Assuming fvp is needed
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/project_database_service.dart'; // Import ProjectDatabaseService

/// PreviewPanel displays the current timeline frame's video(s) with frame-accurate updates.
///
/// This panel updates its visible content *every* time the timeline playhead moves,
/// regardless of how the user is navigating (playback or scrubbing).
/// It now uses TransformableBoxController to allow resizing and moving videos.
///
/// **Intent:**
/// - Ensures the preview always exactly matches the timeline's current frame.
/// - Allows interactive resizing/moving of video elements using flutter_box_transform.
///
/// **Performance:**
/// - Internal update and controller management methods are optimized to avoid unnecessary work.
/// - Video player seeks only when necessary.
/// - Box controllers are managed alongside video controllers.
///
/// **Usage:**
/// - Include wherever a real-time, interactive timeline preview is needed.
class PreviewPanel extends StatefulWidget {
  const PreviewPanel({super.key});

  @override
  _PreviewPanelState createState() => _PreviewPanelState();
}

class _PreviewPanelState extends State<PreviewPanel> {
  // State variables remain inside the class
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  final ProjectDatabaseService _projectDatabaseService = di<ProjectDatabaseService>(); // Inject ProjectDatabaseService
  // Video Player controllers map (clipId -> controller)
  final Map<int, VideoPlayerController> _controllers = {};
  // Aspect ratio for the overall container (might need adjustment if multiple videos differ)
  double _aspectRatio = 16 / 9;
  // Currently visible clips based on playhead position
  List<ClipModel> _currentVisibleClips = [];
  // Futures for ongoing video player initializations
  final Map<int, Future<void>> _initializationFutures = {};

  // State for resizable boxes using controllers
  // Map to store original video size for constraints
  final Map<int, Size> _clipBaseSizes = {};
  // Map to store Rect state for each visible video clip (clipId -> Rect)
  final Map<int, Rect> _clipRects = {};
  // Map to store Flip state for each visible video clip (clipId -> Flip)
  final Map<int, Flip> _clipFlips = {};
  // State for aspect ratio lock
  bool _aspectRatioLocked = true;

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

  // --- Handler Methods (Reacting to ViewModel changes) ---

  void _handleClipListChange() {
    _updateVisibleClips();
    _initializeAndSyncControllers();
  }

  void _handleFrameChange() {
    _updateVisibleClips();
    _initializeAndSyncControllers();
  }

  void _handlePlaybackStateChange(bool isPlaying) {
    final currentTimeMs = _timelineViewModel.currentFrameTimeMs;
    List<Future<void>> tasks = [];

    for (final entry in _controllers.entries) {
      final clipId = entry.key;
      final controller = entry.value;
      final clip = _findClipById(clipId);

      if (clip == null || !controller.value.isInitialized) continue;

      if (isPlaying) {
        final seekPositionMs = (currentTimeMs -
                clip.startTimeOnTrackMs +
                clip.startTimeInSourceMs)
            .toInt()
            .clamp(0, clip.sourceDurationMs);
        bool needsSeek =
            (controller.value.position.inMilliseconds - seekPositionMs).abs() >
            100;
        if (needsSeek) {
          tasks.add(controller.seekTo(Duration(milliseconds: seekPositionMs)));
        }
        if (!controller.value.isPlaying) {
          tasks.add(controller.play());
        }
      } else {
        if (controller.value.isPlaying) {
          tasks.add(controller.pause());
        }
      }
    }

    Future.wait(tasks)
        .then((_) {
          if (mounted) setState(() {}); // Update button icon etc.
        })
        .catchError((error) {
          debugPrint("Error during playback state change sync: $error");
          if (mounted) setState(() {});
        });
  }

  // --- Controller Management ---

  /// Recomputes which clips are currently visible at the timeline's frame head.
  void _updateVisibleClips() {
    if (!mounted) return;

    final clips = _timelineViewModel.clips;
    final currentTimeMs = _timelineViewModel.currentFrameTimeMs;
    final newVisibleClips =
        clips
            .where(
              (clip) =>
                  clip.startTimeOnTrackMs <= currentTimeMs &&
                  currentTimeMs < clip.endTimeOnTrackMs,
            )
            .toList();

    debugPrint(
      "[PreviewPanel][_updateVisibleClips] Visible clips after update (playhead ${currentTimeMs}ms): ${newVisibleClips.map((c) => c.databaseId).toList()}",
    );

    if (listEquals(_currentVisibleClips, newVisibleClips)) {
      _updateAspectRatioIfNeeded();
      return;
    }

    setState(() {
      _currentVisibleClips = newVisibleClips;
      _updateAspectRatioIfNeeded();
    });
  }

  /// Updates the container's aspect ratio based on the first visible, initialized video.
  void _updateAspectRatioIfNeeded() {
    if (!mounted) return;
    VideoPlayerController? firstInitializedController;
    for (final clip in _currentVisibleClips) {
      if (clip.type == ClipType.video &&
          _controllers.containsKey(clip.databaseId)) {
        final controller = _controllers[clip.databaseId]!;
        if (controller.value.isInitialized) {
          firstInitializedController = controller;
          break;
        }
      }
    }

    double targetAspectRatio = 16 / 9; // Default
    if (firstInitializedController != null) {
      targetAspectRatio = firstInitializedController.value.aspectRatio;
    }

    if (_aspectRatio != targetAspectRatio) {
      setState(() {
        _aspectRatio = targetAspectRatio;
      });
    }
  }

  /// Finds a clip by its ID from the ViewModel's current list.
  ClipModel? _findClipById(int? id) {
    if (id == null) return null;
    try {
      return _timelineViewModel.clips.firstWhere((c) => c.databaseId == id);
    } catch (e) {
      return null; // Not found
    }
  }

  /// Initializes/syncs video players and TransformableBox controllers.
  Future<void> _initializeAndSyncControllers() async {
    if (!mounted) return;

    final visibleClipIds =
        _currentVisibleClips.map((c) => c.databaseId!).toSet();
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
      if (clip.type != ClipType.video) continue;

      final clipId = clip.databaseId!;
      final seekPositionMs = (currentTimeMs -
              clip.startTimeOnTrackMs +
              clip.startTimeInSourceMs)
          .toInt()
          .clamp(0, clip.sourceDurationMs);

      if (_controllers.containsKey(clipId)) {
        // --- Sync Existing Video Controller ---
        final controller = _controllers[clipId]!;
        if (controller.value.isInitialized && !isPlaying) {
          if ((controller.value.position.inMilliseconds - seekPositionMs)
                  .abs() >
              100) {
            initSyncFutures.add(
              controller.seekTo(Duration(milliseconds: seekPositionMs)),
            );
          }
        }
        if (controller.value.isInitialized) {
          if (isPlaying && !controller.value.isPlaying) {
            initSyncFutures.add(controller.play());
          } else if (!isPlaying && controller.value.isPlaying) {
            initSyncFutures.add(controller.pause());
          }
        }
        // Note: We don't typically need to sync the BoxController state here unless
        // the timeline state dictates resetting position/size (e.g., loading a project).
        // User interactions are handled via the controller's listener.
      } else if (!_initializationFutures.containsKey(clipId)) {
        // --- Initialize New Video Controller (if not already initializing) ---
        final controller = VideoPlayerController.networkUrl(
          Uri.parse(clip.sourcePath),
        );
        _controllers[clipId] = controller;
        controller.setLooping(false);

        final initFuture = controller
            .initialize()
            .then((_) {
              if (!mounted || !_controllers.containsKey(clipId)) return null;
              return controller.seekTo(Duration(milliseconds: seekPositionMs));
            })
            .then((_) {
              if (!mounted || !_controllers.containsKey(clipId)) return null;
              // Store base size and initialize the TransformableBoxController *after* video init
              final videoSize = controller.value.size;
              _clipBaseSizes[clipId] = videoSize;
              // Initialize the Rect state for the new clip
              if (!_clipRects.containsKey(clipId)) {
                // Check if a preview rect is stored in the clip's metadata
                final savedRect = clip.previewRect;
                if (savedRect != null) {
                  _clipRects[clipId] = savedRect;
                  // If a saved rect exists, assume default flip for now.
                  // If flip is also stored, load it here.
                  _clipFlips[clipId] = Flip.none;
                } else {
                  // Default to centered Rect based on video size if no saved rect
                  _clipRects[clipId] = Rect.fromCenter(
                    center: Offset.zero, // Centered in its Stack slot initially
                    width:
                        videoSize.width > 0
                            ? videoSize.width
                            : 320, // Fallback width
                    height:
                        videoSize.height > 0
                            ? videoSize.height
                            : 180, // Fallback height
                  );
                  _clipFlips[clipId] = Flip.none; // Default flip
                }
              }
              _updateAspectRatioIfNeeded();
              if (isPlaying && mounted) {
                controller.play();
              }
              if (mounted) setState(() {}); // Rebuild to show player
            })
            .catchError((error) {
              debugPrint(
                "Error initializing controller for clip $clipId: $error",
              );
              if (mounted) {
                _disposeController(clipId);
                setState(() {});
              }
            })
            .whenComplete(() {
              _initializationFutures.remove(clipId);
            });

        _initializationFutures[clipId] = initFuture;
        initSyncFutures.add(initFuture);
      }
    }

    try {
      await Future.wait(initSyncFutures);
    } catch (e) {
      debugPrint("Error during batch init/sync: $e");
    }

    if (mounted) {
      _updateVisibleClips();
      _updateAspectRatioIfNeeded();
      setState(() {});
    }
  }

  /// Disposes controllers (video and box) for a specific clip ID.
  void _disposeController(int clipId) {
    final controller = _controllers.remove(clipId);
    _initializationFutures.remove(clipId);
    _clipBaseSizes.remove(clipId);
    // Remove transform state
    _clipRects.remove(clipId);
    _clipFlips.remove(clipId);
    // Dispose video controller
    Future.microtask(() => controller?.dispose());

    if (mounted && _currentVisibleClips.any((c) => c.databaseId == clipId)) {
      Future.microtask(() {
        // Schedule after current frame
        if (mounted) {
          _updateVisibleClips();
          _initializeAndSyncControllers(); // Attempt re-init if needed
        }
      });
    } else if (mounted) {
      _updateAspectRatioIfNeeded();
    }
  }

  /// Disposes all managed controllers.
  void _disposeAllControllers() {
    _initializationFutures.clear();
    final controllersToDispose = List<VideoPlayerController>.from(
      _controllers.values,
    );
    _clipBaseSizes.clear();
    _controllers.clear();
    _clipRects.clear();
    _clipFlips.clear();
    for (final controller in controllersToDispose) {
      Future.microtask(() => controller.dispose());
    }
  }

  /// Callback handler for when a TransformableBox's Rect is changed by user interaction.
  void _handleRectChanged(int clipId, Rect rect) {
    if (!mounted) return;

    // Find the clip model
    final clip = _findClipById(clipId);
    if (clip == null) {
      debugPrint("[PreviewPanel] Clip not found for rect change: $clipId");
      return;
    }

    // Update the stored Rect state for the specific clip locally
    setState(() {
      _clipRects[clipId] = rect;
      // Note: Flip state cannot be updated via onChanged callback in this setup.
    });

    debugPrint("[PreviewPanel] Rect changed for clip $clipId: Rect=$rect");

    // Update the clip model's metadata and save to database
    final updatedClip = clip.copyWithPreviewRect(rect);
    // Use the clipDao to update the clip in the database
    _projectDatabaseService.clipDao!.updateClip(updatedClip.toDbCompanion());

    // TODO: Consider debouncing or other strategies if updates trigger expensive operations
  }

  // --- Aspect Ratio Lock/Unlock Logic ---

  /// Toggles the aspect ratio lock state.
  void _toggleAspectRatioLock() {
    setState(() {
      _aspectRatioLocked = !_aspectRatioLocked;
      // Rebuild triggers TransformableBox to re-evaluate resizeModeResolver
    });
  }

  // --- Build Method ---

  @override
  Widget build(BuildContext context) {
    // Pass necessary state down to the stateless content widget
    return PreviewPanelContent(
      controllers: _controllers,
      aspectRatio: _aspectRatio,
      currentVisibleClips: _currentVisibleClips,
      clipRects: _clipRects, // Pass manual Rect state
      clipFlips: _clipFlips, // Pass manual Flip state
      onRectChanged: _handleRectChanged, // Pass update callback (int, Rect)
      onClipListChange: _handleClipListChange,
      onFrameChange: _handleFrameChange,
      onPlaybackStateChange: _handlePlaybackStateChange,
      aspectRatioLocked: _aspectRatioLocked,
      onToggleAspectRatioLock: _toggleAspectRatioLock,
    );
  }
}

// Stateless widget to display content and handle watch_it reactivity
class PreviewPanelContent extends StatelessWidget with WatchItMixin {
  final Map<int, VideoPlayerController> controllers;
  final double aspectRatio;
  final List<ClipModel> currentVisibleClips;
  final Map<int, Rect> clipRects; // Receive manual Rect state
  final Map<int, Flip> clipFlips; // Receive manual Flip state
  // Revert to non-nullable function type
  final Function(int, Rect) onRectChanged;
  final VoidCallback onClipListChange;
  final VoidCallback onFrameChange;
  final Function(bool) onPlaybackStateChange;
  final bool aspectRatioLocked;
  final VoidCallback onToggleAspectRatioLock;

  const PreviewPanelContent({
    Key? key,
    required this.controllers,
    required this.aspectRatio,
    required this.currentVisibleClips,
    required this.clipRects, // Receive map
    required this.clipFlips, // Receive map
    required this.onRectChanged, // Receive non-nullable callback
    required this.onClipListChange,
    required this.onFrameChange,
    required this.onPlaybackStateChange,
    required this.aspectRatioLocked,
    required this.onToggleAspectRatioLock,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Register handlers to react to ViewModel changes
    final timelineViewModel = di<TimelineViewModel>();
    registerHandler<TimelineViewModel, List<ClipModel>>(
      select: (vm) => vm.clipsNotifier,
      handler: (context, value, __) => onClipListChange(),
    );
    registerHandler<TimelineViewModel, int>(
      select: (vm) => vm.currentFrameNotifier,
      handler: (context, value, __) => onFrameChange(),
    );
    registerHandler<TimelineViewModel, bool>(
      select: (vm) => vm.isPlayingNotifier,
      handler:
          (context, bool isPlaying, __) => onPlaybackStateChange(isPlaying),
    );

    final bool isPlaying = timelineViewModel.isPlayingNotifier.value;

    // Build list of transformable video players
    final List<Widget> transformablePlayers = [];
    for (final clip in currentVisibleClips) {
      if (clip.type == ClipType.video &&
          controllers.containsKey(clip.databaseId)) {
        final videoController = controllers[clip.databaseId]!;
        // Get manual state, providing defaults if not found (should normally exist if video is initialized)
        final currentRect =
            clipRects[clip.databaseId] ?? Rect.fromLTWH(0, 0, 100, 100);
        final currentFlip = clipFlips[clip.databaseId] ?? Flip.none;

        // Only add if video controller is ready (Rect state should exist if video is ready)
        if (videoController.value.isInitialized) {
          transformablePlayers.add(
            // The core interactive widget, now using manual state management
            TransformableBox(
              key: Key(clip.databaseId!.toString()), // Assign Key correctly
              // Controller removed, using manual state below
              rect: currentRect, // Use 'rect' parameter
              flip: currentFlip, // Use 'flip' parameter
              resizeModeResolver:
                  () =>
                      aspectRatioLocked
                          ? ResizeMode.symmetricScale
                          : ResizeMode.freeform,
              // Explicitly cast the callback function to the required type
              // Corrected onChanged callback signature and implementation
              onChanged: (result, details) {
                onRectChanged(clip.databaseId!, result.rect);
              },
              // Define constraints directly here if needed, mirroring previous controller setup
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 36,
                maxWidth: 1920, // Placeholder for parent container size
                maxHeight: 1080, // Placeholder for parent container size
              ),
              contentBuilder: (context, rect, flip) {
                // The content is the VideoPlayer widget.
                return VideoPlayer(videoController);
              },
            ),
          );
        }
      }
    }

    // Determine the main content based on whether any players are ready
    Widget content;
    if (transformablePlayers.isEmpty) {
      content = Center(
        child: Text(
          'No video at current playback position',
          style: FluentTheme.of(
            context,
          ).typography.bodyLarge?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    } else {
      // Stack the transformable players. They will be positioned based on their controller's Rect.
      content = Stack(
        // alignment: Alignment.center, // Alignment might interfere with controller positioning
        children: transformablePlayers,
      );
    }

    // Build the overall panel structure
    return Container(
      color: Colors.grey[160], // Use Fluent UI color for background
      child: Column(
        children: [
          Expanded(
            child: Center(
              // The outer AspectRatio constraints the container where the Stack lives
              child: AspectRatio(
                aspectRatio:
                    aspectRatio, // Use the dynamically calculated aspect ratio
                // This container provides the bounds for the Stack and TransformableBox positioning
                child: Container(
                  color: Colors.black.withOpacity(
                    0.1,
                  ), // Slight tint for visibility
                  child:
                      content, // The Stack containing TransformableBox widgets
                ),
              ),
            ),
          ),
          // --- Playback Controls ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            color: Colors.black.withOpacity(0.6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying ? FluentIcons.pause : FluentIcons.play_solid,
                  ),
                  onPressed: timelineViewModel.togglePlayPause,
                  style: ButtonStyle(
                    foregroundColor: ButtonState.all(Colors.white),
                    iconSize: ButtonState.all(24.0),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: Icon(
                    aspectRatioLocked ? FluentIcons.lock : FluentIcons.unlock,
                  ),
                  onPressed: onToggleAspectRatioLock,
                  style: ButtonStyle(
                    foregroundColor: ButtonState.all(Colors.white),
                    iconSize: ButtonState.all(24.0),
                    backgroundColor: ButtonState.all(
                      aspectRatioLocked
                          ? Colors.blue.withOpacity(0.5)
                          : Colors.transparent,
                    ),
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

// Helper extension for timeline frame time calculation
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
