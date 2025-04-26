import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
// import 'package:flutter/material.dart' show Colors; // Removed Material Colors import
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
  // Flag to track if a transform operation (drag/resize) is in progress
  bool _isTransforming = false;

  // State for snapping guidelines
  bool _snappingEnabled = true; // ADDED: Toggle for magnets
  Size? _containerSize; // Size of the Stack area where videos are placed
  double? _activeHorizontalSnapY; // Y-coordinate of the active horizontal snap line
  double? _activeVerticalSnapX; // X-coordinate of the active vertical snap line
  static const double _snapThreshold = 8.0; // Pixels for snapping sensitivity

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

  // --- Snapping Guideline State Updates ---

  void _updateContainerSize(Size size) {
    // Avoid unnecessary rebuilds if size hasn't changed meaningfully
    if (_containerSize != null &&
        (_containerSize!.width - size.width).abs() < 0.1 &&
        (_containerSize!.height - size.height).abs() < 0.1) {
      return;
    }
    if (mounted) {
      setState(() {
        _containerSize = size;
        debugPrint("[PreviewPanel] Container size updated: $size");
        // Re-initialize rects if container size changes significantly?
        // Maybe needed if initial rects depend on container size.
      });
    }
  }

  void _updateSnapLines({double? hSnap, double? vSnap}) {
    if (!mounted) return;
    // Only update if the snap lines actually change
    if (_activeHorizontalSnapY != hSnap || _activeVerticalSnapX != vSnap) {
       setState(() {
         _activeHorizontalSnapY = hSnap;
         _activeVerticalSnapX = vSnap;
       });
    }
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
  /// This now ONLY updates the local state for immediate visual feedback during drag/resize.
  void _handleRectChanged(int clipId, Rect rect) {
    if (!mounted || _containerSize == null) return;

    // Find the clip model - needed to ensure we only update state for existing clips
    final clip = _findClipById(clipId);
    if (clip == null) {
      debugPrint("[PreviewPanel] Clip not found for rect change: $clipId");
      return;
    }

    Rect snappedRect = rect; // Start with the original rect
    double? currentHSnap;
    double? currentVSnap;

    // --- Snapping Logic ---
    if (_isTransforming && _snappingEnabled) { 
        // Define potential snap targets
        final containerCenter = _containerSize!.center(Offset.zero);
        final List<double> hTargets = [0.0, containerCenter.dy, _containerSize!.height]; // Top, Center Y, Bottom
        final List<double> vTargets = [0.0, containerCenter.dx, _containerSize!.width];  // Left, Center X, Right

        // Add edges and centers of *other* visible clips as snap targets
        for (final otherClipId in _clipRects.keys) {
            if (otherClipId == clipId) continue; // Don't snap to self
            final otherRect = _clipRects[otherClipId];
            if (otherRect != null) {
                hTargets.addAll([otherRect.top, otherRect.center.dy, otherRect.bottom]);
                vTargets.addAll([otherRect.left, otherRect.center.dx, otherRect.right]);
            }
        }

        // --- Check Horizontal Snapping (Y-axis) ---
        final rectCenterY = rect.center.dy;
        final rectTop = rect.top;
        final rectBottom = rect.bottom;

        // Check Center Y
        for (final targetY in hTargets) {
            if ((rectCenterY - targetY).abs() < _snapThreshold) {
                snappedRect = Rect.fromCenter(center: Offset(snappedRect.center.dx, targetY), width: snappedRect.width, height: snappedRect.height);
                currentHSnap = targetY;
                break;
            }
        }
        // Check Top Y (only if center didn't snap)
        if (currentHSnap == null) {
           for (final targetY in hTargets) {
                if ((rectTop - targetY).abs() < _snapThreshold) {
                    snappedRect = Rect.fromLTWH(snappedRect.left, targetY, snappedRect.width, snappedRect.height);
                    currentHSnap = targetY;
                    break;
                }
            }
        }
        // Check Bottom Y (only if top/center didn't snap)
        if (currentHSnap == null) {
           for (final targetY in hTargets) {
                if ((rectBottom - targetY).abs() < _snapThreshold) {
                    snappedRect = Rect.fromLTWH(snappedRect.left, targetY - snappedRect.height, snappedRect.width, snappedRect.height);
                    currentHSnap = targetY;
                    break;
                }
            }
        }

         // --- Check Vertical Snapping (X-axis) ---
        final rectCenterX = snappedRect.center.dx; // Use potentially snapped Y position
        final rectLeft = snappedRect.left;
        final rectRight = snappedRect.right;

        // Check Center X
        for (final targetX in vTargets) {
            if ((rectCenterX - targetX).abs() < _snapThreshold) {
                snappedRect = Rect.fromCenter(center: Offset(targetX, snappedRect.center.dy), width: snappedRect.width, height: snappedRect.height);
                currentVSnap = targetX;
                break;
            }
        }
        // Check Left X (only if center didn't snap)
        if (currentVSnap == null) {
           for (final targetX in vTargets) {
                if ((rectLeft - targetX).abs() < _snapThreshold) {
                    snappedRect = Rect.fromLTWH(targetX, snappedRect.top, snappedRect.width, snappedRect.height);
                    currentVSnap = targetX;
                    break;
                }
            }
        }
        // Check Right X (only if left/center didn't snap)
         if (currentVSnap == null) {
           for (final targetX in vTargets) {
                if ((rectRight - targetX).abs() < _snapThreshold) {
                    snappedRect = Rect.fromLTWH(targetX - snappedRect.width, snappedRect.top, snappedRect.width, snappedRect.height);
                    currentVSnap = targetX;
                    break;
                }
            }
        }
    }

    // Update the stored Rect state for the specific clip locally
    // Use the *snappedRect* if snapping occurred
    setState(() {
      _clipRects[clipId] = snappedRect;
      // Note: Flip state cannot be updated via onChanged callback in this setup.
    });

    // Update the visual snap lines
    _updateSnapLines(
      hSnap: _snappingEnabled ? currentHSnap : null, 
      vSnap: _snappingEnabled ? currentVSnap : null
    );

    // Database update logic is removed from here.
    // debugPrint("[PreviewPanel] Rect changed for clip $clipId: Rect=$rect, Snapped=$snappedRect, HSnap=$currentHSnap, VSnap=$currentVSnap");
  }

  /// Callback handler for when a TransformableBox drag or resize interaction STARTS.
  void _handleTransformStart(int clipId) {
    if (!_isTransforming) {
      setState(() {
        _isTransforming = true;
      });
      debugPrint("[PreviewPanel] Transform STARTED for clip $clipId");
    }
  }

  /// Callback handler for when a TransformableBox drag or resize interaction ENDS.
  /// This handles persisting the final state to the database.
  void _handleTransformEnd(int clipId) { // No longer needs finalRect argument
    if (!mounted) return; // Only save if we were transforming

    // If we were transforming, clear snap lines and reset the flag
    if (_isTransforming) {
      setState(() {
        _isTransforming = false;
      });
       _updateSnapLines(hSnap: null, vSnap: null); // Clear lines on end
    }

    // Find the clip model
    final clip = _findClipById(clipId);
    if (clip == null) {
      debugPrint("[PreviewPanel] Clip not found for transform end: $clipId");
      return;
    }

    // Get the most recent Rect state stored locally by _handleRectChanged
    final finalRect = _clipRects[clipId];
    if (finalRect == null) {
       debugPrint("[PreviewPanel] Final Rect not found in state for transform end: $clipId");
       return; // Should not happen if onChanged updated state correctly
    }

    debugPrint("[PreviewPanel] Transform ENDED for clip $clipId: Final Rect=$finalRect");

    // Update the clip model's metadata and save to database
    final updatedClip = clip.copyWithPreviewRect(finalRect);
    _projectDatabaseService.clipDao!.updateClip(updatedClip.toDbCompanion());
  }

  // --- Aspect Ratio Lock/Unlock Logic ---

  /// Toggles the aspect ratio lock state.
  void _toggleAspectRatioLock() {
    setState(() {
      _aspectRatioLocked = !_aspectRatioLocked;
      // Rebuild triggers TransformableBox to re-evaluate resizeModeResolver
    });
  }

  // ADDED: Method to toggle snapping
  void _toggleSnapping() {
    if (mounted) {
      setState(() {
        _snappingEnabled = !_snappingEnabled;
        // If disabling snapping during a transform, clear the lines immediately
        if (!_snappingEnabled) {
           _updateSnapLines(hSnap: null, vSnap: null);
        }
      });
    }
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
      onTransformStart: _handleTransformStart,
      onTransformEnd: _handleTransformEnd,
      onClipListChange: _handleClipListChange,
      onFrameChange: _handleFrameChange,
      onPlaybackStateChange: _handlePlaybackStateChange,
      aspectRatioLocked: _aspectRatioLocked,
      onToggleAspectRatioLock: _toggleAspectRatioLock,
      // Pass snap line state and container size update callback
      containerSize: _containerSize,
      activeHorizontalSnapY: _activeHorizontalSnapY,
      activeVerticalSnapX: _activeVerticalSnapX,
      onContainerSizeChanged: _updateContainerSize,
      // ADDED: Pass snapping state and toggle callback
      snappingEnabled: _snappingEnabled,
      onToggleSnapping: _toggleSnapping,
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
  // Add the new callback parameters
  final Function(int) onTransformStart;
  final Function(int) onTransformEnd;

  // New parameters for snapping guidelines
  final Size? containerSize;
  final double? activeHorizontalSnapY;
  final double? activeVerticalSnapX;
  final Function(Size) onContainerSizeChanged;
  // ADDED: Snapping parameters
  final bool snappingEnabled;
  final VoidCallback onToggleSnapping;

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
    required this.onTransformStart, 
    required this.onTransformEnd,
    required this.containerSize,
    required this.activeHorizontalSnapY,
    required this.activeVerticalSnapX,
    required this.onContainerSizeChanged,
    // ADDED: Snapping parameters
    required this.snappingEnabled,
    required this.onToggleSnapping,
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
              // --- Add handlers for drag/resize start/end ---
              onDragStart: (result) {
                onTransformStart(clip.databaseId!);
              },
              onResizeStart: (HandlePosition handle, DragStartDetails event) {
                 onTransformStart(clip.databaseId!);
              },
              onDragEnd: (result) {
                onTransformEnd(clip.databaseId!);
              },
              onResizeEnd: (HandlePosition handle, DragEndDetails event) {
                 onTransformEnd(clip.databaseId!);
              },
              // -------------------------------------------
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
                  color: Colors.black.withOpacity(0.1), // Slight tint for visibility
                  // Use LayoutBuilder to get the size of the container where the Stack lives
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Report the size back to the stateful widget
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (containerSize != constraints.biggest) {
                              onContainerSizeChanged(constraints.biggest);
                          }
                      });

                      // Build the Stack with videos and snap lines
                      return Stack(
                        children: [
                          // The Stack containing TransformableBox widgets
                          content,
                          // Add the snap guide painter on top
                          if (containerSize != null && (activeHorizontalSnapY != null || activeVerticalSnapX != null)) 
                            SnapGuidePainter(
                                containerSize: containerSize!,
                                horizontalSnapY: activeHorizontalSnapY,
                                verticalSnapX: activeVerticalSnapX,
                            ),
                        ],
                      );
                    }
                  ),
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
                    backgroundColor: ButtonState.resolveWith((states) {
                       return aspectRatioLocked
                         ? Colors.blue.withOpacity(0.5)
                         : Colors.transparent;
                    }),
                  ),
                ),
                // ADDED: Snapping Toggle Button
                const SizedBox(width: 8.0),
                 IconButton(
                  icon: Icon(
                    FluentIcons.gripper_tool, // Using gripper_tool as alternative
                    color: snappingEnabled ? Colors.white : Colors.grey[80],
                  ),
                  onPressed: onToggleSnapping,
                  style: ButtonStyle(
                    // Optional: Add visual feedback like background color change
                    // backgroundColor: ButtonState.resolveWith((states) {
                    //   return snappingEnabled
                    //     ? Colors.blue.withOpacity(0.5)
                    //     : Colors.transparent;
                    // }),
                    iconSize: ButtonState.all(24.0),
                    foregroundColor: ButtonState.all(snappingEnabled ? Colors.white : Colors.grey[80]),
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

// --- Snap Guide Painter --- 

class SnapGuidePainter extends StatelessWidget {
  final Size containerSize;
  final double? horizontalSnapY;
  final double? verticalSnapX;

  const SnapGuidePainter({
    Key? key,
    required this.containerSize,
    this.horizontalSnapY,
    this.verticalSnapX,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Access FluentTheme here to get the accent color
    final accentColor = FluentTheme.of(context).accentColor;

    return CustomPaint(
      size: containerSize,
      painter: _GuidePainter(
        horizontalSnapY: horizontalSnapY,
        verticalSnapX: verticalSnapX,
        lineColor: accentColor, // Pass the color to the painter
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final double? horizontalSnapY;
  final double? verticalSnapX;
  final Color lineColor; // Receive the color

  final Paint _paint;

  _GuidePainter({
    this.horizontalSnapY,
    this.verticalSnapX,
    required this.lineColor,
  }) : _paint = Paint()
          ..color = lineColor // Use the passed color
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw horizontal line
    if (horizontalSnapY != null) {
      canvas.drawLine(
        Offset(0, horizontalSnapY!),          // Start point (left edge)
        Offset(size.width, horizontalSnapY!), // End point (right edge)
        _paint,
      );
    }

    // Draw vertical line
    if (verticalSnapX != null) {
      canvas.drawLine(
        Offset(verticalSnapX!, 0),          // Start point (top edge)
        Offset(verticalSnapX!, size.height), // End point (bottom edge)
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) {
    // Repaint only if the snap line positions or color change
    return oldDelegate.horizontalSnapY != horizontalSnapY ||
           oldDelegate.verticalSnapX != verticalSnapX ||
           oldDelegate.lineColor != lineColor; // Check color change too
  }
}
