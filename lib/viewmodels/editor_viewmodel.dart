import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/models/project.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'dart:async';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:video_player/video_player.dart';
import 'package:flipedit/viewmodels/editor/editor_layout_viewmodel.dart';
import 'package:flipedit/viewmodels/editor/editor_preview_viewmodel.dart';

// Define typedefs for the function types expected by DockingLayout
typedef DockingAreaParser = dynamic Function(DockingArea area);
typedef DockingAreaBuilder = DockingArea? Function(dynamic data);

/// Acts as a coordinator for editor-related view models and state.
/// Delegates layout management to [EditorLayoutManager] and preview control to [EditorPreviewController].
class EditorViewModel with Disposable {
  // Temporarily commented out LayoutService injection
  // final LayoutService _layoutService = di<LayoutService>();
  
  // Inject TimelineViewModel
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  // Keep VideoPlayerManager for potential future use (preloading etc)
  final VideoPlayerManager _videoPlayerManager = di<VideoPlayerManager>();

  // --- Child Controllers/Managers ---
  final EditorLayoutViewModel layoutManager = EditorLayoutViewModel();
  final EditorPreviewViewModel previewController = EditorPreviewViewModel();

  // --- State Notifiers (Kept in EditorViewModel) ---
  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>('media');
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(null);
  // Keep visibility notifiers for backwards compatibility
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isPreviewVisibleNotifier = ValueNotifier<bool>(true);
  // Notifier for the video URL currently under the playhead
  final ValueNotifier<String?> currentPreviewVideoUrlNotifier = ValueNotifier<String?>(null);

  // Listener for layout changes
  VoidCallback? _layoutListener;
  
  // Store the current project (replace with actual project loading logic)
  late Project _currentProject;

  // Subscription to timeline changes
  VoidCallback? _timelineFrameListener;
  VoidCallback? _timelineClipsListener;
  VoidCallback? _timelinePlayStateListener; // Listener for play state

  // --- Getters ---
  String get selectedExtension => selectedExtensionNotifier.value;
  String? get selectedClipId => selectedClipIdNotifier.value;
  DockingLayout? get layout => layoutManager.layout;
  ValueNotifier<DockingLayout?> get layoutNotifier => layoutManager.layoutNotifier;
  bool get isTimelineVisible => layoutManager.isTimelineVisible;
  bool get isInspectorVisible => layoutManager.isInspectorVisible;
  bool get isPreviewVisible => layoutManager.isPreviewVisible;
  String? get currentPreviewVideoUrl => previewController.currentPreviewVideoUrl;

  // --- Setters ---
  set selectedExtension(String value) {
    if (selectedExtensionNotifier.value == value) return;
    selectedExtensionNotifier.value = value;
  }
  
  set selectedClipId(String? value) {
    if (selectedClipIdNotifier.value == value) return;
    selectedClipIdNotifier.value = value;
  }
  
  // Layout setter is now handled within EditorLayoutManager
  // If external setting is needed, expose a method or setter that calls layoutManager.layout = value

  EditorViewModel() {
    // Initialize with a dummy project or load from storage
    _currentProject = Project(
      id: 'temp',
      name: 'Temp Project',
      path: '/temp/project', // Added dummy path
      createdAt: DateTime.now(), // Added dummy timestamp
      lastModifiedAt: DateTime.now(), // Added dummy timestamp
      clips: [], 
    ); 
    // Initialization of layout and preview is handled within their respective classes' constructors
    print("EditorViewModel initialized. Layout and Preview controllers created.");
  }

  @override
  void onDispose() {
    print("Disposing EditorViewModel...");
    // Dispose local notifiers
    selectedExtensionNotifier.dispose();
    selectedClipIdNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
    isPreviewVisibleNotifier.dispose();
    currentPreviewVideoUrlNotifier.dispose(); // Dispose new notifier
    
    // Remove timeline listeners
    if (_timelineFrameListener != null) {
      _timelineViewModel.currentFrameNotifier.removeListener(_timelineFrameListener!);
    }
    if (_timelineClipsListener != null) {
       _timelineViewModel.clipsNotifier.removeListener(_timelineClipsListener!); // Assuming clipsNotifier is Listenable
    }
    if (_timelinePlayStateListener != null) { // Remove play state listener
       _timelineViewModel.isPlayingNotifier.removeListener(_timelinePlayStateListener!);
    }
    
    // Remove layout listener
    if (layoutManager.layoutNotifier.value != null && _layoutListener != null) {
      layoutManager.layoutNotifier.value!.removeListener(_layoutListener!);
    }

    // Dispose child controllers/managers
    layoutManager.onDispose();
    previewController.onDispose();
    print("EditorViewModel disposed.");
  }

  // Helper function to safely get children from various container types
  List<DockingArea> _getChildrenSafely(DockingArea container) {
    List<DockingArea> result = [];
    
    try {
      if (container is DockingParentArea) {
        // Use the proper API methods for any DockingParentArea (DockingRow, DockingColumn, DockingTabs)
        for (int i = 0; i < container.childrenCount; i++) {
          final child = container.childAt(i);
          result.add(child);
        }
      }
    } catch (e) {
      print("Error accessing children of ${container.runtimeType}: $e");
    }
    
    return result;
  }
  
  // Helper to find a stable reference item in an area
  DockingItem? _findReferenceItem(DockingArea area) {
    if (area is DockingItem) {
      return area;
    } else {
      // Use our safer method to get children
      final List<DockingArea> children = _getChildrenSafely(area);
      for (final child in children) {
        if (child is DockingItem) {
          return child;
        } else {
          final item = _findReferenceItem(child);
          if (item != null) {
            return item;
          }
        }
      }
    }
    return null;
  }

  // Calculate the target frame within the clip's local timeline
  int _calculateLocalFrame(ClipModel clip, int globalFrame) {
      // Ensure the frame is within the clip's duration
      return (globalFrame - clip.startFrame).clamp(0, clip.durationFrames - 1).toInt();
  }

  // Updated to accept isPlaying state
  Future<void> _seekController(VideoPlayerController controller, int frame, bool isPlaying) async {
    const double frameRate = 30.0; 
    final targetPosition = Duration(
      milliseconds: (frame * 1000 / frameRate).round(),
    );
    
    if (controller.value.isInitialized && 
        (controller.value.position - targetPosition).abs() > const Duration(milliseconds: 50)) {
       print("[_seekController] Seeking controller for ${controller.dataSource} to frame $frame (pos: $targetPosition). Timeline playing: $isPlaying");
       await controller.seekTo(targetPosition);
       
       // Only pause if the timeline is NOT playing
       if (!isPlaying && controller.value.isPlaying) {
          print("[_seekController] Pausing controller after seek because timeline is paused.");
          await controller.pause(); 
       }
       // If timeline IS playing, we assume the play command will come separately 
       // or is already handled, so we don't explicitly play here after seeking.
    }
  }

  // New method to handle play/pause commands based on timeline state
  Future<void> _updatePreviewPlaybackState() async {
     final bool isPlaying = _timelineViewModel.isPlaying;
     final String? currentUrl = currentPreviewVideoUrlNotifier.value;
     print("[_updatePreviewPlaybackState] Called. Timeline playing: $isPlaying, Current URL: $currentUrl");

     if (currentUrl == null) return; // No video to control

     try {
       // Get the controller (don't necessarily need isNew here)
       final (controller, _) = await _videoPlayerManager.getOrCreatePlayerController(currentUrl);

       if (!controller.value.isInitialized) {
          print("[_updatePreviewPlaybackState] Controller for $currentUrl not initialized yet.");
          // Could potentially add a listener here similar to _updatePreviewVideo, but 
          // it might be simpler to rely on the next frame/seek update to handle playback.
          return;
       }

       // Apply the correct state
       if (isPlaying && !controller.value.isPlaying) {
          print("[_updatePreviewPlaybackState] Playing controller for $currentUrl");
          await controller.play();
       } else if (!isPlaying && controller.value.isPlaying) {
          print("[_updatePreviewPlaybackState] Pausing controller for $currentUrl");
          await controller.pause();
       }
     } catch (e) {
        print("[_updatePreviewPlaybackState] Error getting/controlling controller for $currentUrl: $e");
     }
  }

  void _updatePreviewVideo() {
    final globalFrame = _timelineViewModel.currentFrame;
    final clips = _timelineViewModel.clips; 
    final bool isPlaying = _timelineViewModel.isPlaying; // Get current play state
    String? videoUrlToShow;
    ClipModel? foundClip;

    for (var clip in clips.reversed) { 
      final int endFrame = clip.startFrame + clip.durationFrames;
      if ((clip.type == ClipType.video || clip.type == ClipType.image) &&
          globalFrame >= clip.startFrame &&
          globalFrame < endFrame) {
        foundClip = clip;
        videoUrlToShow = clip.sourcePath;
        break; 
      }
    }

    bool urlChanged = currentPreviewVideoUrlNotifier.value != videoUrlToShow;
    if (urlChanged) {
      currentPreviewVideoUrlNotifier.value = videoUrlToShow;
    }

    if (foundClip != null && videoUrlToShow != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final (controller, _) = await _videoPlayerManager.getOrCreatePlayerController(videoUrlToShow!);
          final localFrame = _calculateLocalFrame(foundClip!, globalFrame);

          if (!controller.value.isInitialized) {
             print("[_updatePreviewVideo post-frame] Waiting for controller initialization for seek...");
             void Function()? initListener;
             initListener = () {
                if(controller.value.isInitialized){
                  print("[_updatePreviewVideo post-frame] Controller initialized, seeking now.");
                   // Seek and apply correct initial play state
                  _seekController(controller, localFrame, isPlaying);
                  // Ensure playback state is correct *after* potential seek
                  _updatePreviewPlaybackState(); 
                  controller.removeListener(initListener!); 
                }
             };
             controller.addListener(initListener);
             if(controller.value.isInitialized) initListener();
             
          } else {
             // Seek and apply correct initial play state
             await _seekController(controller, localFrame, isPlaying);
             // Ensure playback state is correct *after* potential seek
             _updatePreviewPlaybackState(); 
          }
        } catch (e) {
            print("[_updatePreviewVideo post-frame] Error getting/seeking/controlling controller: $e");
        }
      });
    } else if (urlChanged && videoUrlToShow == null) {
       // If the URL changed to null (no clip at this frame), ensure any previously playing video is paused
       final previousUrl = currentPreviewVideoUrlNotifier.value; // This is now null, need the value *before* the change
       // We might need to store the previous URL temporarily if we want precise pausing
       // For now, let's assume pausing the *current* (null) is harmless or rely on player manager disposal later
       print("[_updatePreviewVideo] No clip found at frame $globalFrame. Ensuring no playback (if possible).");
       // Potentially call _updatePreviewPlaybackState here, which will find no URL and do nothing
       // Or, more robustly, explicitly pause the controller associated with the *previous* URL if known.
    }
  }

  // --- Default Layout ---
  
  // Build the default layout
  DockingLayout _buildDefaultLayout() {
    final previewItem = _buildPreviewItem();
    final timelineItem = _buildTimelineItem();
    final inspectorItem = _buildInspectorItem();
    
    // Ensure visibility notifiers match the default layout state
    isTimelineVisibleNotifier.value = true;
    isInspectorVisibleNotifier.value = true;
    isPreviewVisibleNotifier.value = true;
    
    return DockingLayout(
      root: DockingRow([
        DockingColumn([
          previewItem, 
          timelineItem
        ]),
        inspectorItem
      ])
    );
  }
  
  // --- Item Builders ---
  DockingItem _buildPreviewItem() {
    return DockingItem(
      id: 'preview',
      name: 'Preview',
      maximizable: false, 
      widget: const PreviewPanel(),
    );
  }
  
  DockingItem _buildTimelineItem() {
    return DockingItem(id: 'timeline', name: 'Timeline', widget: const Timeline());
  }
  
  DockingItem _buildInspectorItem() {
    return DockingItem(id: 'inspector', name: 'Inspector', widget: const InspectorPanel());
  }

  // --- Actions ---
  // Toggle timeline visibility using generic method
  void toggleTimeline() => layoutManager.toggleTimeline();
  
  // Toggle inspector visibility using generic method
  void toggleInspector() => layoutManager.toggleInspector();

  void togglePreview() => layoutManager.togglePreview();

  // These are called by Docking widget when the close button on an item is clicked
  void markInspectorClosed() => layoutManager.markInspectorClosed();
  
  void markTimelineClosed() => layoutManager.markTimelineClosed();

  void markPreviewClosed() => layoutManager.markPreviewClosed();
}

