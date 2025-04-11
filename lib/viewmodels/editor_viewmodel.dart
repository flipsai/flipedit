import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/services/layout_service.dart'; // Import LayoutService

// Define typedefs for the function types expected by DockingLayout
typedef DockingAreaParser = dynamic Function(DockingArea area);
typedef DockingAreaBuilder = DockingArea? Function(dynamic data);

/// Manages the editor layout and currently selected panels, tools, etc.
/// Now uses stringify/load for basic layout structure persistence.
class EditorViewModel with Disposable {
  // Inject LayoutService
  final LayoutService _layoutService = di<LayoutService>();

  // --- State Notifiers ---
  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>('video');
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<DockingLayout?> layoutNotifier = ValueNotifier<DockingLayout?>(null);
  // Keep visibility notifiers for backwards compatibility
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<List<String>> videoUrlsNotifier = ValueNotifier<List<String>>([]);
  final ValueNotifier<List<double>> opacitiesNotifier = ValueNotifier<List<double>>([]);

  // Last known parent and position for panels, used to restore them to their previous positions
  Map<String, Map<String, dynamic>> _lastPanelPositions = {};
  
  // Listener for layout changes
  VoidCallback? _layoutListener;
  
  // Flag to prevent saving during initial load
  bool _isInitialLoad = true;

  // --- Getters ---
  String get selectedExtension => selectedExtensionNotifier.value;
  String? get selectedClipId => selectedClipIdNotifier.value;
  DockingLayout? get layout => layoutNotifier.value;
  // Continue to derive visibility from layout
  bool get isTimelineVisible => layoutNotifier.value?.findDockingItem('timeline') != null;
  bool get isInspectorVisible => layoutNotifier.value?.findDockingItem('inspector') != null;
  List<String> get videoUrls => videoUrlsNotifier.value;
  List<double> get opacities => opacitiesNotifier.value;

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
  
  set videoUrls(List<String> value) {
    if (listEquals(videoUrlsNotifier.value, value)) return;
    videoUrlsNotifier.value = value;
  }

  set opacities(List<double> value) {
    if (listEquals(opacitiesNotifier.value, value)) return;
    opacitiesNotifier.value = value;
  }
  
  EditorViewModel() {
    _initializeSampleVideos();
    _loadAndBuildInitialLayout();
  }

  // --- Layout Persistence & Handling ---

  // Called when the layout object notifies listeners (drag, resize, close)
  void _onLayoutChanged() {
    print("DockingLayout changed internally.");
    
    if (_isInitialLoad) {
      // Skip saving during initial load
      print("Skipping save during initial load.");
      return;
    }
    
    // Always save the visibility state when it changes
    _saveLayoutState();
    
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
        
        if (parent is DockingRow || parent is DockingColumn) {
          // Use safer method to get children
          final List<DockingArea> children = _getChildrenSafely(parent);
          final index = children.indexOf(item);
          
          // Find a stable reference item (adjacent sibling)
          DockingItem? referenceItem;
          if (index > 0) {
            final prevArea = children[index - 1];
            referenceItem = _findReferenceItem(prevArea);
            position = parent is DockingRow ? DropPosition.right : DropPosition.bottom;
          } else if (index < children.length - 1) {
            final nextArea = children[index + 1];
            referenceItem = _findReferenceItem(nextArea);
            position = parent is DockingRow ? DropPosition.left : DropPosition.top;
          }
          
          if (referenceItem != null) {
            adjacentId = referenceItem.id;
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
          position = DropPosition.right;
        }
        
        _lastPanelPositions[item.id] = {
          'adjacentId': adjacentId,
          'position': position,
        };
        
        print("Stored position for ${item.id}: adjacent=${adjacentId}, pos=${position}");
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
          } else if (child is DockingArea) {
            // For sub-containers, visit them recursively
            visitArea(child, position);
          }
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

  Future<void> _loadAndBuildInitialLayout() async {
    _isInitialLoad = true;
    print("Attempting to load panel layout state...");
    
    try {
      // Try to load saved visibility state
      final visibilityState = await _layoutService.loadVisibilityState();
      
      // Start with default layout
      layout = _buildDefaultLayout();
      
      // Apply visibility state if available
      if (visibilityState != null) {
        final isTimelineVisible = visibilityState['isTimelineVisible'] ?? true;
        final isInspectorVisible = visibilityState['isInspectorVisible'] ?? true;
        
        // Apply visibility settings to the layout
        final currentLayout = layoutNotifier.value;
        if (currentLayout != null) {
          if (!isTimelineVisible) {
            currentLayout.removeItemByIds(['timeline']);
            isTimelineVisibleNotifier.value = false;
          }
          
          if (!isInspectorVisible) {
            currentLayout.removeItemByIds(['inspector']);
            isInspectorVisibleNotifier.value = false;
          }
        }
        
        print("Applied visibility state: timeline=$isTimelineVisible, inspector=$isInspectorVisible");
      } else {
        print("No saved visibility state found. Using default layout.");
      }
    } catch (e) {
      print("Error during layout initialization: $e");
      layout = _buildDefaultLayout();
    } finally {
      // Set flag after a brief delay to ensure loading is complete
      Future.delayed(const Duration(milliseconds: 500), () {
        _isInitialLoad = false;
        print("Initial load complete. Layout changes will now be saved.");
      });
    }
  }
  
  Future<void> _saveLayoutState() async {
    if (_isInitialLoad) return; // Don't save during initial load
    
    // Just save visibility state
    try {
      final visibilityState = {
        'isTimelineVisible': isTimelineVisible,
        'isInspectorVisible': isInspectorVisible,
      };
      await _layoutService.saveVisibilityState(visibilityState);
      print("Panel visibility state saved.");
    } catch (e) {
      print("Error saving visibility state: $e");
    }
  }

  // --- Basic Parser and Builder ---
  
  // Very simple parser that captures just the structure and IDs
  dynamic _basicParser(DockingArea area) {
    // Create a basic map with the type
    final Map<String, dynamic> result = {'type': area.runtimeType.toString()};
    
    try {
      // Add type-specific properties
      if (area is DockingRow || area is DockingColumn) {
        // Use our safer method to get children
        final children = <dynamic>[];
        final safeChildren = _getChildrenSafely(area);
        for (final child in safeChildren) {
          children.add(_basicParser(child));
        }
        result['children'] = children;
      } else if (area is DockingTabs) {
        // For DockingTabs, just save the IDs of tab items
        final tabItems = <Map<String, dynamic>>[];
        final safeChildren = _getChildrenSafely(area);
        for (final child in safeChildren) {
          if (child is DockingItem) {
            tabItems.add({'id': child.id, 'name': child.name});
          }
        }
        result['items'] = tabItems;
      } else if (area is DockingItem) {
        // For DockingItem, just save ID and name
        result['id'] = area.id;
        result['name'] = area.name;
      }
    } catch (e) {
      print("Error in basicParser for ${area.runtimeType}: $e");
      // If error occurs, at least save the type
    }
    
    return result;
  }
  
  // Very simple builder that creates a basic layout
  DockingArea? _areaBuilder(dynamic data) {
    if (data == null) return null;
    
    try {
      final type = data['type'];
      switch (type) {
        case 'DockingRow':
          final childrenData = data['children'] as List<dynamic>?;
          final children = <DockingArea>[];
          
          if (childrenData != null) {
            for (final childData in childrenData) {
              final child = _areaBuilder(childData);
              if (child != null) {
                children.add(child);
              }
            }
          }
          return children.isEmpty ? null : DockingRow(children);
        
        case 'DockingColumn':
          final childrenData = data['children'] as List<dynamic>?;
          final children = <DockingArea>[];
          
          if (childrenData != null) {
            for (final childData in childrenData) {
              final child = _areaBuilder(childData);
              if (child != null) {
                children.add(child);
              }
            }
          }
          return children.isEmpty ? null : DockingColumn(children);
        
        case 'DockingTabs':
          final items = data['items'] as List<dynamic>?;
          final tabItems = <DockingItem>[];
          
          if (items != null) {
            for (final itemData in items) {
              final id = itemData['id'];
              // Create the appropriate panel item based on ID
              switch (id) {
                case 'preview':
                  tabItems.add(_buildPreviewItem());
                  break;
                case 'timeline':
                  tabItems.add(_buildTimelineItem());
                  break;
                case 'inspector':
                  tabItems.add(_buildInspectorItem());
                  break;
              }
            }
          }
          return tabItems.isEmpty ? null : DockingTabs(tabItems);
        
        case 'DockingItem':
          final id = data['id'];
          // Create the appropriate panel item based on ID
          switch (id) {
            case 'preview':
              return _buildPreviewItem();
            case 'timeline':
              return _buildTimelineItem();
            case 'inspector':
              return _buildInspectorItem();
            default:
              return null;
          }
        
        default:
          print("Unknown area type: $type");
          return null;
      }
    } catch (e) {
      print("Error building area from data: $e");
      return null;
    }
  }

  // --- Default Layout ---
  
  // Build the default layout
  DockingLayout _buildDefaultLayout() {
    final previewItem = _buildPreviewItem();
    final timelineItem = _buildTimelineItem();
    final inspectorItem = _buildInspectorItem();
    
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
      widget: PreviewPanel(
        videoUrls: videoUrlsNotifier.value, 
        opacities: opacitiesNotifier.value,
      ),
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
        this.layout = DockingLayout(root: _buildTimelineItem());
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
    if (targetItem == null) {
      targetItem = layout.findDockingItem('inspector');
      // Position remains bottom, assuming inspector is typically on the right
    }

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
        this.layout = DockingLayout(root: _buildInspectorItem());
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
    if (targetItem == null) {
      targetItem = layout.findDockingItem('timeline');
      // Position remains right
    }
    
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
    _saveLayoutState(); // Also explicitly trigger save for robustness
  }
  
  void markTimelineClosed() {
    // Store position *before* the item is removed by the library
    _storePanelPositions();
    
    isTimelineVisibleNotifier.value = false; // Update menu state
    _saveLayoutState(); // Also explicitly trigger save for robustness
  }

  // --- Sample Data & Video Management (remain the same) ---
  void _initializeSampleVideos() {
    videoUrls = [];
    opacities = []; 
    addVideo("http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4");
    addVideo("http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4");
    addVideo("http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4");
    setVideoOpacity(1, 0.5);
    setVideoOpacity(2, 0.5);
  }

  void addVideo(String url) {
    final newUrls = List<String>.from(videoUrlsNotifier.value)..add(url);
    final newOpacities = List<double>.from(opacitiesNotifier.value)..add(1.0);
    videoUrls = newUrls;
    opacities = newOpacities;
  }

  void removeVideo(int index) {
    if (index < 0 || index >= videoUrlsNotifier.value.length) return;
    final urlToRemove = videoUrlsNotifier.value[index];
    di<VideoPlayerManager>().disposeController(urlToRemove);
    final newUrls = List<String>.from(videoUrlsNotifier.value)..removeAt(index);
    final newOpacities = List<double>.from(opacitiesNotifier.value)..removeAt(index);
    videoUrls = newUrls;
    opacities = newOpacities;
  }

  void setVideoOpacity(int index, double opacity) {
    if (index < 0 || index >= opacitiesNotifier.value.length) return;
    final newOpacities = List<double>.from(opacitiesNotifier.value);
    newOpacities[index] = opacity.clamp(0.0, 1.0);
    opacities = newOpacities;
  }

  // --- Cleanup ---
  @override
  void onDispose() {
     print("Disposing EditorViewModel and removing layout listener.");
     if (layoutNotifier.value != null && _layoutListener != null) {
       layoutNotifier.value!.removeListener(_layoutListener!);
       _layoutListener = null;
     }
     selectedExtensionNotifier.dispose();
     selectedClipIdNotifier.dispose();
     layoutNotifier.dispose(); 
     isTimelineVisibleNotifier.dispose();
     isInspectorVisibleNotifier.dispose();
     videoUrlsNotifier.dispose();
     opacitiesNotifier.dispose();
  }
}

// Helper function for list equality check
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

