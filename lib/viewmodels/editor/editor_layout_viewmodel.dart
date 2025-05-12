import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:docking/docking.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/area_dimensions_service.dart';
import 'package:watch_it/watch_it.dart';

class EditorLayoutViewModel {
  final ValueNotifier<DockingLayout?> layoutNotifier =
      ValueNotifier<DockingLayout?>(null);
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<bool> isPreviewVisibleNotifier = ValueNotifier<bool>(
    true,
  );

  final Map<String, Map<String, dynamic>> _lastPanelPositions = {};
  
  final AreaDimensionsService _areaDimensionsService = di<AreaDimensionsService>();
  
  // Flag to track if dimensions have been applied to avoid re-applying on every layout change
  bool _initialDimensionsApplied = false;

  VoidCallback? _layoutListener;

  String get _logTag => runtimeType.toString();

  DockingLayout? get layout => layoutNotifier.value;
  bool get isTimelineVisible =>
      layoutNotifier.value?.findDockingItem('timeline') != null;
  bool get isInspectorVisible =>
      layoutNotifier.value?.findDockingItem('inspector') != null;
  bool get isPreviewVisible =>
      layoutNotifier.value?.findDockingItem('preview') != null;

  set layout(DockingLayout? value) {
    if (layoutNotifier.value == value) return;

    if (layoutNotifier.value != null && _layoutListener != null) {
      layoutNotifier.value!.removeListener(_layoutListener!);
      logDebug(_logTag, "LayoutManager: Removed listener from old layout.");
    }

    layoutNotifier.value = value;

    if (layoutNotifier.value != null) {
      _layoutListener = _onLayoutChanged;
      layoutNotifier.value!.addListener(_layoutListener!);
      logDebug(_logTag, "LayoutManager: Added listener to new layout.");
      
      // Load and apply saved dimensions if not already done for this session
      if (!_initialDimensionsApplied) {
        _loadAndApplyDimensions();
        _initialDimensionsApplied = true;
      }
    } else {
      _layoutListener = null;
      logDebug(_logTag, "LayoutManager: Layout set to null, listener removed.");
    }

    if (layoutNotifier.value != null) {
      isTimelineVisibleNotifier.value = isTimelineVisible;
      isInspectorVisibleNotifier.value = isInspectorVisible;
      isPreviewVisibleNotifier.value = isPreviewVisible;
    }
  }

  EditorLayoutViewModel() {
    _buildInitialLayout(); // Build initial layout with default proportions
                         // Saved dimensions will be applied AFTER this by the listener
  }

  void dispose() {
    if (layoutNotifier.value != null) {
      _saveAreaDimensions();
    }
    
    layoutNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
    isPreviewVisibleNotifier.dispose();

    if (layoutNotifier.value != null && _layoutListener != null) {
      layoutNotifier.value!.removeListener(_layoutListener!);
    }
  }

  void _onLayoutChanged() {
    logDebug(_logTag, "LayoutManager: DockingLayout changed internally (e.g., due to resize).");
    
    // Save current dimensions after any layout change (including resize completion)
    _saveAreaDimensions();
    
    final currentLayout = layoutNotifier.value;
    if (currentLayout != null) {
      bool timelineFound = currentLayout.findDockingItem('timeline') != null;
      bool inspectorFound = currentLayout.findDockingItem('inspector') != null;
      bool previewFound = currentLayout.findDockingItem('preview') != null;

      if (isTimelineVisibleNotifier.value != timelineFound) {
        isTimelineVisibleNotifier.value = timelineFound;
        logDebug(
          _logTag,
          "LayoutManager: Timeline visibility flag updated to $timelineFound",
        );
      }

      if (isInspectorVisibleNotifier.value != inspectorFound) {
        isInspectorVisibleNotifier.value = inspectorFound;
        logDebug(
          _logTag,
          "LayoutManager: Inspector visibility flag updated to $inspectorFound",
        );
      }

      if (isPreviewVisibleNotifier.value != previewFound) {
        isPreviewVisibleNotifier.value = previewFound;
        logDebug(
          _logTag,
          "LayoutManager: Preview visibility flag updated to $previewFound",
        );
      }
    }
  }
  
  Future<void> _loadAndApplyDimensions() async {
    if (layoutNotifier.value == null) {
      logDebug(_logTag, "LayoutManager: Layout not ready for applying dimensions.");
      return;
    }
    
    try {
      final dimensions = await _areaDimensionsService.loadAreaDimensions();
      final currentLayout = layoutNotifier.value!;
      if (dimensions != null) {
        logDebug(_logTag, "LayoutManager: Applying saved area dimensions (width/height properties) to existing layout.");
        _areaDimensionsService.applyDimensions(currentLayout, dimensions);
        
        // Now, explicitly update the _size property of Area objects for MultiSplitView
        logDebug(_logTag, "LayoutManager: Updating internal _size of Area objects based on applied dimensions.");
        _applyLoadedSizesToLayout(currentLayout);
        
        currentLayout.notifyListeners(); // Force a rebuild/relayout
      } else {
        logDebug(_logTag, "LayoutManager: No saved dimensions to apply or layout is null.");
      }
    } catch (e) {
      logError(_logTag, "LayoutManager: Error loading/applying area dimensions: $e");
    }
  }
  
  void _applyLoadedSizesToLayout(DockingLayout layout) {
    void processArea(DockingArea area, {Axis? parentAxis}) {
      if (area is DockingItem || area is DockingTabs) {
        // For items/tabs, determine which dimension (width or height) should be used for _size
        // This depends on its immediate parent (Row or Column)
        // MultiSplitView uses a single 'size' property for its children.
        if (parentAxis == Axis.horizontal && area.width != null) {
          (area as Area).updateSize(area.width); // Area from multi_split_view
        } else if (parentAxis == Axis.vertical && area.height != null) {
          (area as Area).updateSize(area.height);
        } else if (parentAxis == null) {
          // If it's the root and not in a row/column, or if parentAxis is unknown,
          // we might default or use a preferred dimension if available.
          // This case needs careful handling if root can be an item directly.
          // For now, if width is available, prioritize it for _size.
          if (area.width != null) {
             (area as Area).updateSize(area.width);
          } else if (area.height != null) {
             (area as Area).updateSize(area.height);
          }
        }
      }

      if (area is DockingRow) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            processArea(area.childAt(i), parentAxis: Axis.horizontal);
          } catch (e) {
            logError(_logTag, 'Error processing child of DockingRow for size application: $e');
          }
        }
      } else if (area is DockingColumn) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            processArea(area.childAt(i), parentAxis: Axis.vertical);
          } catch (e) {
            logError(_logTag, 'Error processing child of DockingColumn for size application: $e');
          }
        }
      } else if (area is DockingParentArea) { // Catch-all for other parent types if any
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            // Pass parentAxis as null if unknown for generic parent types
            processArea(area.childAt(i), parentAxis: null); 
          } catch (e) {
            logError(_logTag, 'Error processing child of generic DockingParentArea for size application: $e');
          }
        }
      }
    }

    if (layout.root != null) {
      processArea(layout.root!); // Start with null parentAxis for root
    }
  }
  
  Future<void> _saveAreaDimensions() async {
    if (layoutNotifier.value == null) return;
    
    try {
      final dimensions = _areaDimensionsService.collectAreaDimensions(layoutNotifier.value!);
      if (dimensions.isNotEmpty) {
        logDebug(_logTag, "LayoutManager: Saving area dimensions: ${dimensions.length} areas");
        await _areaDimensionsService.saveAreaDimensions(dimensions);
      }
    } catch (e) {
      logError(_logTag, "LayoutManager: Error saving area dimensions: $e");
    }
  }
  
  // This method is now called by ResizableDocking's listener and internal _onLayoutChanged
  void updateAreaDimensions() { // Renamed back
    // This method is now primarily for triggering a save after a resize operation via ResizableDocking
    // The actual updating of Area.width/height is done by the Docking widget itself.
    // We just need to make sure the latest state is saved.
    logDebug(_logTag, "LayoutManager: updateAreaDimensions called (likely after resize). Saving current state.");
    _saveAreaDimensions();
  }

  void _storePanelPositions() {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;

    void processItem(
      DockingItem item,
      DockingArea parent,
      DropPosition position,
    ) {
      if (item.id == 'timeline' ||
          item.id == 'inspector' ||
          item.id == 'preview') {
        String adjacentId = 'preview'; // Default fallback
        DropPosition relativePosition = DropPosition.right; // Default

        if (parent is DockingRow || parent is DockingColumn) {
          final List<DockingArea> children = _getChildrenSafely(parent);
          final index = children.indexOf(item);

          DockingItem? referenceItem;
          if (index > 0) {
            final prevArea = children[index - 1];
            referenceItem = _findReferenceItem(prevArea);
            relativePosition =
                parent is DockingRow ? DropPosition.right : DropPosition.bottom;
          } else if (index < children.length - 1) {
            final nextArea = children[index + 1];
            referenceItem = _findReferenceItem(nextArea);
            relativePosition =
                parent is DockingRow ? DropPosition.left : DropPosition.top;
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

        logDebug(
          _logTag,
          "LayoutManager: Stored position for ${item.id}: adjacent=$adjacentId, pos=$position",
        );
      }
    }

    void visitArea(DockingArea area, DropPosition position) {
      if (area is DockingItem) {
        logDebug(
          _logTag,
          "LayoutManager: Skipping position storage for root DockingItem: ${area.id}",
        );
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
      logError(
        _logTag,
        "LayoutManager: Error accessing children of ${container.runtimeType}: $e",
      );
    }
    return result;
  }

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

  void _buildInitialLayout() {
    // Build with default/initial sizes/weights. Saved dimensions will be applied later.
    final previewItem = _buildPreviewItem(); // No weight initially
    final timelineItem = _buildTimelineItem(); // No weight initially
    final inspectorItem = _buildInspectorItem(); // No weight initially

    isTimelineVisibleNotifier.value = true;
    isInspectorVisibleNotifier.value = true;
    isPreviewVisibleNotifier.value = true;

    // The MultiSplitView will distribute available space. Weights can be used for initial proportion.
    // If we want saved pixel dimensions to truly work, they must be applied *after* this initial layout,
    // and MultiSplitView must be able to re-layout based on new Area.size values.
    // For now, let's give them some default weights or let MultiSplitView decide based on Area.size if provided.

    // Pass the initial weights via the constructor
    final col = DockingColumn([previewItem, timelineItem], weight: 0.7, id: 'preview_timeline_column');
    final insp = _buildInspectorItem(weight: 0.3);

    layout = DockingLayout(
      root: DockingRow([col, insp]),
    );
    logDebug(_logTag, "LayoutManager: Built default layout. Saved dimensions will be applied if available.");
  }

  // Build methods now can optionally take weight for initial layout
  DockingItem _buildPreviewItem({double? weight}) {
    return DockingItem(
      id: 'preview',
      name: 'Preview',
      maximizable: false,
      widget: const PreviewPanel(),
      weight: weight, // Allow initial weight
    );
  }

  DockingItem _buildTimelineItem({double? weight}) {
    return DockingItem(
      id: 'timeline',
      name: 'Timeline',
      widget: const Timeline(),
      weight: weight, // Allow initial weight
    );
  }

  DockingItem _buildInspectorItem({double? weight}) {
    return DockingItem(
      id: 'inspector',
      name: 'Inspector',
      widget: const InspectorPanel(),
      weight: weight, // Allow initial weight
    );
  }

  void _togglePanel({
    required String panelId,
    required bool isCurrentlyVisible,
    required ValueNotifier<bool> visibilityNotifier,
    required DockingItem Function({double? weight}) itemBuilder, // Adjusted signature to allow weight
    required void Function(DockingLayout) defaultPositionHandler,
  }) {
    final currentLayout = layoutNotifier.value;
    if (currentLayout == null) return;

    logDebug(
      _logTag,
      "LayoutManager: Toggle $panelId visibility. Currently visible: $isCurrentlyVisible",
    );

    if (isCurrentlyVisible) {
      _storePanelPositions();
      currentLayout.removeItemByIds([panelId]);
    } else {
      bool isLayoutEmpty =
          currentLayout.findDockingItem('preview') == null &&
          currentLayout.findDockingItem('inspector') == null &&
          currentLayout.findDockingItem('timeline') == null;

      final newItem = itemBuilder(); // Build without weight, dimensions applied later

      if (isLayoutEmpty) {
        logDebug(
          _logTag,
          "LayoutManager: Layout is empty. Resetting layout with $panelId as root.",
        );
        layout = DockingLayout(root: newItem);
        _loadAndApplyDimensions(); 
      } else {
        final lastPosition = _lastPanelPositions[panelId];

        if (lastPosition != null) {
          final adjacentId = lastPosition['adjacentId'] as String;
          final position = lastPosition['position'] as DropPosition;

          final adjacentItem = currentLayout.findDockingItem(adjacentId);
          if (adjacentItem != null) {
            logDebug(
              _logTag,
              "LayoutManager: Restoring $panelId next to $adjacentId in position $position",
            );
            currentLayout.addItemOn(
              newItem: newItem,
              targetArea: adjacentItem,
              dropPosition: position,
            );
          } else {
            defaultPositionHandler(currentLayout);
          }
        } else {
          defaultPositionHandler(currentLayout);
        }
        _loadAndApplyDimensions();
      }
    }
  }

  void toggleTimeline() {
    _togglePanel(
      panelId: 'timeline',
      isCurrentlyVisible: isTimelineVisible,
      visibilityNotifier: isTimelineVisibleNotifier,
      itemBuilder: _buildTimelineItem,
      defaultPositionHandler: _addTimelineDefaultPosition,
    );
  }

  void toggleInspector() {
    _togglePanel(
      panelId: 'inspector',
      isCurrentlyVisible: isInspectorVisible,
      visibilityNotifier: isInspectorVisibleNotifier,
      itemBuilder: _buildInspectorItem,
      defaultPositionHandler: _addInspectorDefaultPosition,
    );
  }

  void togglePreview() {
    _togglePanel(
      panelId: 'preview',
      isCurrentlyVisible: isPreviewVisible,
      visibilityNotifier: isPreviewVisibleNotifier,
      itemBuilder: _buildPreviewItem,
      defaultPositionHandler: _addPreviewDefaultPosition,
    );
  }

  void _addTimelineDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem =
        layout.findDockingItem('preview') ??
        layout.findDockingItem('inspector');
    DropPosition position = DropPosition.bottom;
    final newItem = _buildTimelineItem();

    if (targetItem != null) {
      layout.addItemOn(
        newItem: newItem,
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Timeline - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: newItem);
    }
  }

  void _addInspectorDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem =
        layout.findDockingItem('preview') ?? layout.findDockingItem('timeline');
    DropPosition position = DropPosition.right;
    final newItem = _buildInspectorItem();

    if (targetItem != null) {
      layout.addItemOn(
        newItem: newItem,
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Inspector - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: newItem);
    }
  }

  void _addPreviewDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem =
        layout.findDockingItem('timeline') ??
        layout.findDockingItem('inspector');
    DropPosition position = DropPosition.left;
    final newItem = _buildPreviewItem();

    if (targetItem != null) {
      layout.addItemOn(
        newItem: newItem,
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Preview - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: newItem);
    }
  }

  void markInspectorClosed() {
    _storePanelPositions();
    isInspectorVisibleNotifier.value = false;
  }

  void markTimelineClosed() {
    _storePanelPositions();
    isTimelineVisibleNotifier.value = false;
  }

  void markPreviewClosed() {
    _storePanelPositions();
    isPreviewVisibleNotifier.value = false;
  }
}
