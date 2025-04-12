import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/widgets.dart'; // Import for WidgetsBinding
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_player_manager.dart';
// import 'package:flipedit/services/layout_service.dart'; // Temporarily commented out
import 'package:flipedit/models/project.dart'; // Assuming Project model exists
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Import TimelineViewModel
import 'dart:async'; // Import for StreamSubscription
import 'package:flipedit/models/clip.dart'; // Import Clip model
import 'package:flipedit/models/enums/clip_type.dart'; // Import ClipType enum
import 'package:video_player/video_player.dart'; // Import for VideoPlayerController

// Define typedefs for the function types expected by DockingLayout
typedef DockingAreaParser = dynamic Function(DockingArea area);
typedef DockingAreaBuilder = DockingArea? Function(dynamic data);

/// Manages the editor layout and currently selected panels, tools, etc.
/// Now uses stringify/load for basic layout structure persistence.
class EditorViewModel with Disposable {
  // Temporarily commented out LayoutService injection
  // final LayoutService _layoutService = di<LayoutService>();
  
  // Inject TimelineViewModel
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  // Keep VideoPlayerManager for potential future use (preloading etc)
  final VideoPlayerManager _videoPlayerManager = di<VideoPlayerManager>();

  // --- State Notifiers ---
  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>('video');
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<DockingLayout?> layoutNotifier = ValueNotifier<DockingLayout?>(null);
  // Keep visibility notifiers for backwards compatibility
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  // Notifier for the video URL currently under the playhead
  final ValueNotifier<String?> currentPreviewVideoUrlNotifier = ValueNotifier<String?>(null);

  // Last known parent and position for panels, used to restore them to their previous positions
  final Map<String, Map<String, dynamic>> _lastPanelPositions = {};
  
  // Listener for layout changes
  VoidCallback? _layoutListener;
  
  // Flag to prevent saving during initial load
  bool _isInitialLoad = true;

  // Store the current project (replace with actual project loading logic)
  late Project _currentProject; // Added Project field

  // Subscription to timeline changes
  VoidCallback? _timelineFrameListener;
  VoidCallback? _timelineClipsListener;
  VoidCallback? _timelinePlayStateListener; // Listener for play state

  // --- Getters ---
  String get selectedExtension => selectedExtensionNotifier.value;
  String? get selectedClipId => selectedClipIdNotifier.value;
  DockingLayout? get layout => layoutNotifier.value;
  // Continue to derive visibility from layout
  bool get isTimelineVisible => layoutNotifier.value?.findDockingItem('timeline') != null;
  bool get isInspectorVisible => layoutNotifier.value?.findDockingItem('inspector') != null;
  String? get currentPreviewVideoUrl => currentPreviewVideoUrlNotifier.value; // Getter for new notifier

  // --- Setters ---
  set selectedExtension(String value) {
    if (selectedExtensionNotifier.value == value) return;
    selectedExtensionNotifier.value = value;
  }
  
  set selectedClipId(String? value) {
    if (selectedClipIdNotifier.value == value) return;
    selectedClipIdNotifier.value = value;
  }
  
  // Layout setter manages the listener
  set layout(DockingLayout? value) {
    if (layoutNotifier.value == value) return;

     // Remove listener from old layout
     if (layoutNotifier.value != null && _layoutListener != null) {
       layoutNotifier.value!.removeListener(_layoutListener!);
       print("Removed listener from old layout.");
     }
     
     layoutNotifier.value = value;
     
     // Add listener to new layout
     if (layoutNotifier.value != null) {
       _layoutListener = _onLayoutChanged;
       layoutNotifier.value!.addListener(_layoutListener!);
       print("Added listener to new layout.");
     } else {
       _layoutListener = null;
       print("Layout set to null, listener removed.");
     }
     
     // Update visibility flags for compatibility (for menu item state)
     if (layoutNotifier.value != null) {
       isTimelineVisibleNotifier.value = isTimelineVisible;
       isInspectorVisibleNotifier.value = isInspectorVisible;
     }
  }
  
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
    _buildInitialLayout(); // Use simplified initial build
    _subscribeToTimelineChanges(); // Subscribe to timeline
  }

  @override
  void onDispose() {
    selectedExtensionNotifier.dispose();
    selectedClipIdNotifier.dispose();
    layoutNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
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
    if (layoutNotifier.value != null && _layoutListener != null) {
      layoutNotifier.value!.removeListener(_layoutListener!);
    }
  }

  // --- Layout Persistence & Handling ---

  // Called when the layout object notifies listeners (drag, resize, close)
  void _onLayoutChanged() {
    print("DockingLayout changed internally.");
    
    // Temporarily disable saving
    // if (!_isInitialLoad) {
    //   _saveLayoutState(); 
    // }
    
    // Update visibility notifiers for compatibility with menus
    final currentLayout = layoutNotifier.value;
    if (currentLayout != null) {
      bool timelineFound = currentLayout.findDockingItem('timeline') != null;
      bool inspectorFound = currentLayout.findDockingItem('inspector') != null;
      
      if (isTimelineVisibleNotifier.value != timelineFound) {
        isTimelineVisibleNotifier.value = timelineFound;
        print("Timeline visibility flag updated to $timelineFound");
      }
      
      if (isInspectorVisibleNotifier.value != inspectorFound) {
        isInspectorVisibleNotifier.value = inspectorFound;
        print("Inspector visibility flag updated to $inspectorFound");
      }
    }
  }
  
  // Store positions of all panels for later restoration
  void _storePanelPositions() {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;
    
    void processItem(DockingItem item, DockingArea parent, DropPosition position) {
      if (item.id == 'timeline' || item.id == 'inspector') {
        // Store adjacent item (sibling) ID and relative position
        String adjacentId = 'preview'; // Default fallback
        DropPosition relativePosition = DropPosition.right; // Default
        
        if (parent is DockingRow || parent is DockingColumn) {
          // Use safer method to get children
          final List<DockingArea> children = _getChildrenSafely(parent);
          final index = children.indexOf(item);
          
          // Find a stable reference item (adjacent sibling)
          DockingItem? referenceItem;
          if (index > 0) {
            final prevArea = children[index - 1];
            referenceItem = _findReferenceItem(prevArea);
            relativePosition = parent is DockingRow ? DropPosition.right : DropPosition.bottom;
          } else if (index < children.length - 1) {
            final nextArea = children[index + 1];
            referenceItem = _findReferenceItem(nextArea);
            relativePosition = parent is DockingRow ? DropPosition.left : DropPosition.top;
          }
          
          if (referenceItem != null) {
            adjacentId = referenceItem.id;
            position = relativePosition;
          }
        } else if (parent is DockingTabs) {
          // Use safer method for tabs
          final List<DockingArea> tabItems = _getChildrenSafely(parent);
          for (final tabItem in tabItems) {
            if (tabItem != item && tabItem is DockingItem) {
              adjacentId = tabItem.id;
              break;
            }
          }
          // For tabs, using center/tab behavior (right is a common fallback)
          position = DropPosition.right; // Use right for tabs as default drop
        }
        
        _lastPanelPositions[item.id] = {
          'adjacentId': adjacentId,
          'position': position,
        };
        
        print("Stored position for ${item.id}: adjacent=$adjacentId, pos=$position");
      }
    }
    
    // Walk through the layout to find and store panel positions
    void visitArea(DockingArea area, DropPosition position) {
      if (area is DockingItem) {
        // If an item is encountered directly (likely the root),
        // we don't need to process its position relative to siblings
        // as it has none in this context. Just return.
        print("Skipping position storage for root DockingItem: ${area.id}");
        return;
      } else if (area is DockingRow || area is DockingColumn) {
        // Use safer method to get children
        final List<DockingArea> children = _getChildrenSafely(area);
        for (final child in children) {
          if (child is DockingItem) {
            // For items, process them with their actual parent
            processItem(child, area, position);
          } else          // For sub-containers, visit them recursively
          visitArea(child, position);
        
        }
      } else if (area is DockingTabs) {
        // Use safer method for tabs
        final List<DockingArea> tabItems = _getChildrenSafely(area);
        for (final child in tabItems) {
          if (child is DockingItem) {
            processItem(child, area, DropPosition.right);
          }
        }
      }
    }
    
    // Start traversal from root
    final root = currentLayout.root;
    if (root != null) {
      visitArea(root, DropPosition.right);
    }
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

  // Simplified initial layout build (no loading)
  void _buildInitialLayout() {
     _isInitialLoad = true; 
     layout = _buildDefaultLayout();
     print("Built default layout.");
     // Set flag after a delay
     Future.delayed(const Duration(milliseconds: 100), () {
      _isInitialLoad = false;
      print("Initial load complete. Layout saving disabled (commented out).");
    });
  }
  
  // Future<void> _saveLayoutState() async {
  //   final currentLayout = layoutNotifier.value;
  //   if (currentLayout == null) {
  //     print("Save requested but layout is null, clearing saved state.");
  //     await _layoutService.clearLayout();
  //     await _layoutService.clearPanelPositions();
  //     return;
  //   } 

  //   if (_isInitialLoad) {
  //     print("Save requested during initial load, skipping.");
  //     return; // Don't save during initial load phase
  //   }
    
  //   try {
  //     // Save the current layout structure
  //     final layoutJson = currentLayout.toJson(
  //       itemEncoder: (item) => item.id, // Save only the ID for item reference
  //     );
  //     await _layoutService.saveLayout(layoutJson);
  //     print("Layout state saved successfully.");
      
  //     // Store current positions before saving them
  //     _storePanelPositions(); 
  //     await _layoutService.savePanelPositions(_lastPanelPositions);
  //     print("Panel positions saved: $_lastPanelPositions");
      
  //   } catch (e) {
  //     print("Error saving layout state: $e");
  //   }
  // }

  // --- Timeline Integration ---
  void _subscribeToTimelineChanges() {
    // Listen to changes in the timeline ViewModel (clips and current frame)
    _timelineFrameListener = _updatePreviewVideo; // Store the listener
    _timelineViewModel.currentFrameNotifier.addListener(_timelineFrameListener!);

    // Also listen to clip changes, as adding/removing clips affects the preview
    _timelineClipsListener = _updatePreviewVideo; // Store the listener
    _timelineViewModel.clipsNotifier.addListener(_timelineClipsListener!); // Assuming clipsNotifier is Listenable
    
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
    
    return DockingLayout(
      root: DockingRow([
        DockingColumn([previewItem, timelineItem]),
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
      widget: const PreviewPanel(), // Correct: No params needed
    );
  }
  
  DockingItem _buildTimelineItem() {
    return DockingItem(id: 'timeline', name: 'Timeline', widget: const Timeline());
  }
  
  DockingItem _buildInspectorItem() {
    return DockingItem(id: 'inspector', name: 'Inspector', widget: const InspectorPanel());
  }

  // --- Actions ---
  
  // Toggle actions now modify the layout directly
  void toggleTimeline() {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;
    
    final isCurrentlyVisible = isTimelineVisible;
    debugPrint("Toggle Timeline visibility. Currently visible: $isCurrentlyVisible");
    
    if (isCurrentlyVisible) {
      // Store position *before* removing the item via menu toggle
      _storePanelPositions(); 
      currentLayout.removeItemByIds(['timeline']);
    } else {
      // Check if the layout is effectively empty (no core panels found)
      bool isLayoutEmpty = currentLayout.findDockingItem('preview') == null &&
                           currentLayout.findDockingItem('inspector') == null &&
                           currentLayout.findDockingItem('timeline') == null;

      if (isLayoutEmpty) {
        debugPrint("Layout is empty. Resetting layout with Timeline as root.");
        // IMPORTANT: Assign to the layout property to trigger notifier and listener attachment
        layout = DockingLayout(root: _buildTimelineItem());
      } else {
        // Layout is not empty, proceed with restoring/adding
        final lastPosition = _lastPanelPositions['timeline'];
        
        if (lastPosition != null) {
          final adjacentId = lastPosition['adjacentId'] as String;
          final position = lastPosition['position'] as DropPosition;
          
          final adjacentItem = currentLayout.findDockingItem(adjacentId);
          if (adjacentItem != null) {
            // Restore to its last position relative to the adjacent item
            debugPrint("Restoring timeline next to $adjacentId in position $position");
            currentLayout.addItemOn(
              newItem: _buildTimelineItem(),
              targetArea: adjacentItem,
              dropPosition: position
            );
          } else {
            // Adjacent item not found, fall back to default position
            _addTimelineDefaultPosition(currentLayout);
          }
        } else {
          // No last position, use default positioning
          _addTimelineDefaultPosition(currentLayout);
        }
      }
    }
    
    // Layout listener will trigger save
    isTimelineVisibleNotifier.value = !isCurrentlyVisible; // Update for menu state
  }
  
  // Helper for default timeline positioning
  void _addTimelineDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem = layout.findDockingItem('preview');
    DropPosition position = DropPosition.bottom;

    // If preview isn't found, try adding below inspector
    targetItem ??= layout.findDockingItem('inspector');

    if (targetItem != null) {
      layout.addItemOn(
        newItem: _buildTimelineItem(),
        targetArea: targetItem,
        dropPosition: position
      );
    } else {
      // Fallback - add to root if no suitable target found
      debugPrint("Timeline: No suitable target (Preview/Inspector) found, adding to root.");
      layout.addItemOnRoot(newItem: _buildTimelineItem());
    }
  }
  
  void toggleInspector() {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;
    
    final isCurrentlyVisible = isInspectorVisible;
    debugPrint("Toggle Inspector visibility. Currently visible: $isCurrentlyVisible");
    
    if (isCurrentlyVisible) {
      // Store position *before* removing the item via menu toggle
      _storePanelPositions();
      currentLayout.removeItemByIds(['inspector']);
    } else {
      // Check if the layout is effectively empty (no core panels found)
      bool isLayoutEmpty = currentLayout.findDockingItem('preview') == null &&
                           currentLayout.findDockingItem('inspector') == null &&
                           currentLayout.findDockingItem('timeline') == null;

      if (isLayoutEmpty) {
        debugPrint("Layout is empty. Resetting layout with Inspector as root.");
        // IMPORTANT: Assign to the layout property to trigger notifier and listener attachment
        layout = DockingLayout(root: _buildInspectorItem());
      } else {
        // Layout is not empty, proceed with restoring/adding
        final lastPosition = _lastPanelPositions['inspector'];
        
        if (lastPosition != null) {
          final adjacentId = lastPosition['adjacentId'] as String;
          final position = lastPosition['position'] as DropPosition;
          
          final adjacentItem = currentLayout.findDockingItem(adjacentId);
          if (adjacentItem != null) {
            // Restore to its last position relative to the adjacent item
            debugPrint("Restoring inspector next to $adjacentId in position $position");
            currentLayout.addItemOn(
              newItem: _buildInspectorItem(),
              targetArea: adjacentItem,
              dropPosition: position
            );
          } else {
            // Adjacent item not found, fall back to default position
            _addInspectorDefaultPosition(currentLayout);
          }
        } else {
          // No last position, use default positioning
          _addInspectorDefaultPosition(currentLayout);
        }
      }
    }
    
    // Layout listener will trigger save
    isInspectorVisibleNotifier.value = !isCurrentlyVisible; // Update for menu state
  }
  
  // Helper for default inspector positioning
  void _addInspectorDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem = layout.findDockingItem('preview');
    DropPosition position = DropPosition.right;

    // If preview isn't found, try adding to the right of timeline
    targetItem ??= layout.findDockingItem('timeline');
    
    if (targetItem != null) {
      layout.addItemOn(
        newItem: _buildInspectorItem(),
        targetArea: targetItem,
        dropPosition: position
      );
    } else {
      // Fallback - add to root if no suitable target found
      debugPrint("Inspector: No suitable target (Preview/Timeline) found, adding to root.");
      layout.addItemOnRoot(newItem: _buildInspectorItem());
    }
  }

  // These are called by Docking widget when the close button on an item is clicked
  void markInspectorClosed() {
    // Store position *before* the item is removed by the library
    _storePanelPositions(); 
    
    isInspectorVisibleNotifier.value = false; // Update menu state
    // _saveLayoutState(); // Temporarily disabled
  }
  
  void markTimelineClosed() {
    // Store position *before* the item is removed by the library
    _storePanelPositions();
    
    isTimelineVisibleNotifier.value = false; // Update menu state
    // _saveLayoutState(); // Temporarily disabled
  }
}

