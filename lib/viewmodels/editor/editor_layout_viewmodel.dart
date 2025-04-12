import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';

/// Manages the editor's docking layout state and visibility toggles.
class EditorLayoutViewModel with Disposable {
  // --- State Notifiers ---
  final ValueNotifier<DockingLayout?> layoutNotifier = ValueNotifier<DockingLayout?>(null);
  // Keep visibility notifiers for backwards compatibility/menu state
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isPreviewVisibleNotifier = ValueNotifier<bool>(true);

  // Last known parent and position for panels, used to restore them
  final Map<String, Map<String, dynamic>> _lastPanelPositions = {};

  // Listener for layout changes
  VoidCallback? _layoutListener;

  // Flag to prevent saving during initial load (if needed later)
  bool _isInitialLoad = true;

  // --- Getters ---
  DockingLayout? get layout => layoutNotifier.value;
  // Derive visibility from layout
  bool get isTimelineVisible => layoutNotifier.value?.findDockingItem('timeline') != null;
  bool get isInspectorVisible => layoutNotifier.value?.findDockingItem('inspector') != null;
  bool get isPreviewVisible => layoutNotifier.value?.findDockingItem('preview') != null;

  // --- Setters ---
  // Layout setter manages the listener
  set layout(DockingLayout? value) {
    if (layoutNotifier.value == value) return;

     // Remove listener from old layout
     if (layoutNotifier.value != null && _layoutListener != null) {
       layoutNotifier.value!.removeListener(_layoutListener!);
       print("LayoutManager: Removed listener from old layout.");
     }

     layoutNotifier.value = value;

     // Add listener to new layout
     if (layoutNotifier.value != null) {
       _layoutListener = _onLayoutChanged;
       layoutNotifier.value!.addListener(_layoutListener!);
       print("LayoutManager: Added listener to new layout.");
     } else {
       _layoutListener = null;
       print("LayoutManager: Layout set to null, listener removed.");
     }

     // Update visibility flags for compatibility (for menu item state)
     if (layoutNotifier.value != null) {
       isTimelineVisibleNotifier.value = isTimelineVisible;
       isInspectorVisibleNotifier.value = isInspectorVisible;
       isPreviewVisibleNotifier.value = isPreviewVisible;
     }
  }

  EditorLayoutViewModel() {
    _buildInitialLayout();
  }

  @override
  void onDispose() {
    layoutNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
    isPreviewVisibleNotifier.dispose();

    // Remove layout listener
    if (layoutNotifier.value != null && _layoutListener != null) {
      layoutNotifier.value!.removeListener(_layoutListener!);
    }
  }

  // --- Layout Persistence & Handling ---

  // Called when the layout object notifies listeners (drag, resize, close)
  void _onLayoutChanged() {
    print("LayoutManager: DockingLayout changed internally.");
    // Update visibility notifiers for compatibility with menus
    final currentLayout = layoutNotifier.value;
    if (currentLayout != null) {
      bool timelineFound = currentLayout.findDockingItem('timeline') != null;
      bool inspectorFound = currentLayout.findDockingItem('inspector') != null;
      bool previewFound = currentLayout.findDockingItem('preview') != null;

      if (isTimelineVisibleNotifier.value != timelineFound) {
        isTimelineVisibleNotifier.value = timelineFound;
        print("LayoutManager: Timeline visibility flag updated to $timelineFound");
      }

      if (isInspectorVisibleNotifier.value != inspectorFound) {
        isInspectorVisibleNotifier.value = inspectorFound;
        print("LayoutManager: Inspector visibility flag updated to $inspectorFound");
      }

      if (isPreviewVisibleNotifier.value != previewFound) {
        isPreviewVisibleNotifier.value = previewFound;
        print("LayoutManager: Preview visibility flag updated to $previewFound");
      }
    }
    // Future: Call layout saving logic here if re-enabled
  }

  // Store positions of all panels for later restoration
  void _storePanelPositions() {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;

    void processItem(DockingItem item, DockingArea parent, DropPosition position) {
      if (item.id == 'timeline' || item.id == 'inspector' || item.id == 'preview') {
        // Store adjacent item (sibling) ID and relative position
        String adjacentId = 'preview'; // Default fallback
        DropPosition relativePosition = DropPosition.right; // Default

        if (parent is DockingRow || parent is DockingColumn) {
          final List<DockingArea> children = _getChildrenSafely(parent);
          final index = children.indexOf(item);

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
          final List<DockingArea> tabItems = _getChildrenSafely(parent);
          for (final tabItem in tabItems) {
            if (tabItem != item && tabItem is DockingItem) {
              adjacentId = tabItem.id;
              break;
            }
          }
          position = DropPosition.right; // Use right for tabs as default drop
        }

        _lastPanelPositions[item.id] = {
          'adjacentId': adjacentId,
          'position': position,
        };

        print("LayoutManager: Stored position for ${item.id}: adjacent=$adjacentId, pos=$position");
      }
    }

    void visitArea(DockingArea area, DropPosition position) {
      if (area is DockingItem) {
        print("LayoutManager: Skipping position storage for root DockingItem: ${area.id}");
        return;
      } else if (area is DockingRow || area is DockingColumn) {
        final List<DockingArea> children = _getChildrenSafely(area);
        for (final child in children) {
          if (child is DockingItem) {
            processItem(child, area, position);
          } else {
            visitArea(child, position);
          }
        }
      } else if (area is DockingTabs) {
        final List<DockingArea> tabItems = _getChildrenSafely(area);
        for (final child in tabItems) {
          if (child is DockingItem) {
            processItem(child, area, DropPosition.right);
          }
        }
      }
    }

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
        for (int i = 0; i < container.childrenCount; i++) {
          final child = container.childAt(i);
          result.add(child);
        }
      }
    } catch (e) {
      print("LayoutManager: Error accessing children of ${container.runtimeType}: $e");
    }
    return result;
  }

  // Helper to find a stable reference item in an area
  DockingItem? _findReferenceItem(DockingArea area) {
    if (area is DockingItem) {
      return area;
    } else {
      final List<DockingArea> children = _getChildrenSafely(area);
      for (final child in children) {
        final item = (child is DockingItem) ? child : _findReferenceItem(child);
        if (item != null) {
          return item;
        }
      }
    }
    return null;
  }

  // Simplified initial layout build
  void _buildInitialLayout() {
     _isInitialLoad = true;
     layout = _buildDefaultLayout();
     print("LayoutManager: Built default layout.");
     // Set flag after a delay if needed for saving logic later
     Future.delayed(const Duration(milliseconds: 100), () {
      _isInitialLoad = false;
      print("LayoutManager: Initial load complete.");
    });
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
  // These create the DockingItems with their associated widgets
  DockingItem _buildPreviewItem() {
    return DockingItem(
      id: 'preview',
      name: 'Preview',
      maximizable: false,
      widget: const PreviewPanel(), // Assumes PreviewPanel takes no args
    );
  }

  DockingItem _buildTimelineItem() {
    return DockingItem(
      id: 'timeline',
      name: 'Timeline',
      widget: const Timeline(), // Assumes Timeline takes no args
    );
  }

  DockingItem _buildInspectorItem() {
    return DockingItem(
      id: 'inspector',
      name: 'Inspector',
      widget: const InspectorPanel(), // Assumes InspectorPanel takes no args
    );
  }

  // --- Actions ---

  // Generic method to toggle panel visibility
  void _togglePanel({
    required String panelId,
    required bool isCurrentlyVisible,
    required ValueNotifier<bool> visibilityNotifier,
    required DockingItem Function() itemBuilder,
    required void Function(DockingLayout) defaultPositionHandler
  }) {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;

    debugPrint("LayoutManager: Toggle $panelId visibility. Currently visible: $isCurrentlyVisible");

    if (isCurrentlyVisible) {
      // Store position *before* removing the item via menu toggle
      _storePanelPositions();
      currentLayout.removeItemByIds([panelId]);
    } else {
      // Check if the layout is effectively empty
      bool isLayoutEmpty = currentLayout.findDockingItem('preview') == null &&
                           currentLayout.findDockingItem('inspector') == null &&
                           currentLayout.findDockingItem('timeline') == null;

      if (isLayoutEmpty) {
        debugPrint("LayoutManager: Layout is empty. Resetting layout with $panelId as root.");
        // IMPORTANT: Assign using the setter to trigger notifier and listener attachment
        layout = DockingLayout(root: itemBuilder());
      } else {
        // Layout is not empty, proceed with restoring/adding
        final lastPosition = _lastPanelPositions[panelId];

        if (lastPosition != null) {
          final adjacentId = lastPosition['adjacentId'] as String;
          final position = lastPosition['position'] as DropPosition;

          final adjacentItem = currentLayout.findDockingItem(adjacentId);
          if (adjacentItem != null) {
            debugPrint("LayoutManager: Restoring $panelId next to $adjacentId in position $position");
            currentLayout.addItemOn(
              newItem: itemBuilder(),
              targetArea: adjacentItem,
              dropPosition: position
            );
          } else {
            defaultPositionHandler(currentLayout);
          }
        } else {
          defaultPositionHandler(currentLayout);
        }
      }
    }
    // The layout listener (_onLayoutChanged) will update the visibility notifiers
  }

  // Toggle timeline visibility using generic method
  void toggleTimeline() {
    _togglePanel(
      panelId: 'timeline',
      isCurrentlyVisible: isTimelineVisible,
      visibilityNotifier: isTimelineVisibleNotifier,
      itemBuilder: _buildTimelineItem,
      defaultPositionHandler: _addTimelineDefaultPosition
    );
  }

  // Toggle inspector visibility using generic method
  void toggleInspector() {
    _togglePanel(
      panelId: 'inspector',
      isCurrentlyVisible: isInspectorVisible,
      visibilityNotifier: isInspectorVisibleNotifier,
      itemBuilder: _buildInspectorItem,
      defaultPositionHandler: _addInspectorDefaultPosition
    );
  }

  void togglePreview() {
    _togglePanel(
      panelId: 'preview',
      isCurrentlyVisible: isPreviewVisible,
      visibilityNotifier: isPreviewVisibleNotifier,
      itemBuilder: _buildPreviewItem,
      defaultPositionHandler: _addPreviewDefaultPosition
    );
  }

  // Helper for default timeline positioning
  void _addTimelineDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem = layout.findDockingItem('preview') ?? layout.findDockingItem('inspector');
    DropPosition position = DropPosition.bottom;

    if (targetItem != null) {
      layout.addItemOn(newItem: _buildTimelineItem(), targetArea: targetItem, dropPosition: position);
    } else {
      debugPrint("LayoutManager: Timeline - No suitable target, adding to root.");
      layout.addItemOnRoot(newItem: _buildTimelineItem());
    }
  }

  // Helper for default inspector positioning
  void _addInspectorDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem = layout.findDockingItem('preview') ?? layout.findDockingItem('timeline');
    DropPosition position = DropPosition.right;

    if (targetItem != null) {
      layout.addItemOn(newItem: _buildInspectorItem(), targetArea: targetItem, dropPosition: position);
    } else {
      debugPrint("LayoutManager: Inspector - No suitable target, adding to root.");
      layout.addItemOnRoot(newItem: _buildInspectorItem());
    }
  }

  void _addPreviewDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem = layout.findDockingItem('timeline') ?? layout.findDockingItem('inspector');
     // Typically add preview to the left or top-left of the main area
    DropPosition position = DropPosition.left;

    if (targetItem != null) {
      layout.addItemOn(newItem: _buildPreviewItem(), targetArea: targetItem, dropPosition: position);
    } else {
      debugPrint("LayoutManager: Preview - No suitable target, adding to root.");
      layout.addItemOnRoot(newItem: _buildPreviewItem());
    }
  }


  // These are called by Docking widget when the close button on an item is clicked
  // (Or potentially proxied from EditorViewModel if needed)
  void markInspectorClosed() {
    _storePanelPositions();
    isInspectorVisibleNotifier.value = false; // Update menu state directly here
  }

  void markTimelineClosed() {
    _storePanelPositions();
    isTimelineVisibleNotifier.value = false; // Update menu state directly here
  }

  void markPreviewClosed() {
    _storePanelPositions();
    isPreviewVisibleNotifier.value = false; // Update menu state directly here
  }
} 