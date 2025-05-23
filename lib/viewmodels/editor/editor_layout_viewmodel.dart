import 'package:fluent_ui/fluent_ui.dart';
import 'package:docking/docking.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/player/player_panel.dart'; // Added
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/area_dimensions_service.dart';
import 'package:watch_it/watch_it.dart';

class EditorLayoutViewModel with LayoutParserMixin, AreaBuilderMixin {
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

  final AreaDimensionsService _areaDimensionsService =
      di<AreaDimensionsService>();

  // Flag to track if dimensions have been applied to avoid re-applying on every layout change
  bool _initialDimensionsApplied = false;

  // For saving and loading the entire layout
  String _lastLayoutString = '';

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
        _loadLayout();
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
    // Saved layout will be loaded AFTER this by the listener
  }

  void dispose() {
    if (layoutNotifier.value != null) {
      _saveLayout();
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
    logDebug(
      _logTag,
      "LayoutManager: DockingLayout changed internally (e.g., due to resize).",
    );

    // Save current layout after any change
    _saveLayout();

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

  // Save the entire layout state including tab positions
  Future<void> _saveLayout() async {
    if (layoutNotifier.value == null) return;

    try {
      // Save the complete layout structure
      _lastLayoutString = layoutNotifier.value!.stringify(parser: this);
      logDebug(_logTag, "LayoutManager: Saved complete layout state");

      // Store the layout string to persistent storage
      await _areaDimensionsService.saveLayoutString(_lastLayoutString);

      // Also save dimensions for backward compatibility
      final dimensions = _areaDimensionsService.collectAreaDimensions(
        layoutNotifier.value!,
      );
      if (dimensions.isNotEmpty) {
        await _areaDimensionsService.saveAreaDimensions(dimensions);
      }
    } catch (e) {
      logError(_logTag, "LayoutManager: Error saving layout: $e");
    }
  }

  // Load the entire layout state
  Future<void> _loadLayout() async {
    try {
      // Try to load the complete layout first
      final savedLayoutString = await _areaDimensionsService.loadLayoutString();
      final dimensions = await _areaDimensionsService.loadAreaDimensions();

      if (savedLayoutString != null && savedLayoutString.isNotEmpty) {
        logDebug(_logTag, "LayoutManager: Loading complete saved layout");
        _lastLayoutString = savedLayoutString;

        // Apply the layout
        layoutNotifier.value?.load(
          layout: _lastLayoutString,
          parser: this,
          builder: this,
        );

        // Important: After loading the layout structure, also apply the saved dimensions
        // This ensures both tab positions AND size information are restored
        if (dimensions != null) {
          _areaDimensionsService.applyDimensions(
            layoutNotifier.value!,
            dimensions,
          );
          _applyLoadedSizesToLayout(layoutNotifier.value!);
        }

        layoutNotifier.value?.notifyListeners(); // Force a rebuild
        return;
      }

      // Fall back to loading just dimensions if no complete layout is available
      _loadAndApplyDimensions();
    } catch (e) {
      logError(_logTag, "LayoutManager: Error loading layout: $e");
      // Fall back to dimensions
      _loadAndApplyDimensions();
    }
  }

  // Implementation of AreaBuilderMixin
  @override
  DockingItem buildDockingItem({
    required dynamic id,
    required double? weight,
    required bool maximized,
  }) {
    // Load dimensions for this item if available
    Map<String, double>? itemDimensions;
    try {
      final dimensions = _areaDimensionsService.collectAreaDimensions(
        layoutNotifier.value!,
      );
      if (dimensions.containsKey(id.toString())) {
        itemDimensions = dimensions[id.toString()];
        logDebug(
          _logTag,
          "LayoutManager: Found saved dimensions for $id: $itemDimensions",
        );
      }
    } catch (e) {
      logError(
        _logTag,
        "LayoutManager: Error getting dimensions for item $id: $e",
      );
    }

    // Extract size for the Area constructor
    double? size = itemDimensions?['width'] ?? itemDimensions?['height'];

    if (id == 'preview') {
      return _buildPreviewItem(
        weight: weight,
        maximized: maximized,
        size: size,
      );
    } else if (id == 'timeline') {
      return _buildTimelineItem(
        weight: weight,
        maximized: maximized,
        size: size,
      );
    } else if (id == 'inspector') {
      return _buildInspectorItem(
        weight: weight,
        maximized: maximized,
        size: size,
      );
    } else if (id == 'preview_timeline_column') {
      // Handle special case for composite IDs if needed
      return DockingItem(
        id: id,
        name: 'Column',
        widget: Container(),
        weight: weight,
        maximized: maximized,
        size: size,
      );
    }

    throw StateError('Unknown item ID: $id');
  }

  Future<void> _loadAndApplyDimensions() async {
    if (layoutNotifier.value == null) {
      logDebug(
        _logTag,
        "LayoutManager: Layout not ready for applying dimensions.",
      );
      return;
    }

    try {
      final dimensions = await _areaDimensionsService.loadAreaDimensions();
      final currentLayout = layoutNotifier.value!;
      if (dimensions != null) {
        logDebug(
          _logTag,
          "LayoutManager: Applying saved area dimensions (width/height properties) to existing layout.",
        );
        _areaDimensionsService.applyDimensions(currentLayout, dimensions);

        // Now, explicitly update the _size property of Area objects for MultiSplitView
        logDebug(
          _logTag,
          "LayoutManager: Updating internal _size of Area objects based on applied dimensions.",
        );
        _applyLoadedSizesToLayout(currentLayout);

        currentLayout.notifyListeners(); // Force a rebuild/relayout
      } else {
        logDebug(
          _logTag,
          "LayoutManager: No saved dimensions to apply or layout is null.",
        );
      }
    } catch (e) {
      logError(
        _logTag,
        "LayoutManager: Error loading/applying area dimensions: $e",
      );
    }
  }

  void _applyLoadedSizesToLayout(DockingLayout layout) {
    void processArea(DockingArea area, {Axis? parentAxis}) {
      if (area is DockingItem || area is DockingTabs) {
        // For items/tabs in the docking layout
        Map<String, double>? dimensions;
        try {
          final allDimensions = _areaDimensionsService.collectAreaDimensions(
            layout,
          );
          if (area.id != null &&
              allDimensions.containsKey(area.id.toString())) {
            dimensions = allDimensions[area.id.toString()];
          }
        } catch (e) {
          logError(_logTag, "Error getting dimensions for area ${area.id}: $e");
        }

        double? sizeToApply;

        // Determine which dimension to use based on parent axis
        if (parentAxis == Axis.horizontal &&
            dimensions != null &&
            dimensions.containsKey('width')) {
          sizeToApply = dimensions['width'];
          logDebug(
            _logTag,
            "LayoutManager: Using width=$sizeToApply for ${area.id} in horizontal parent",
          );
        } else if (parentAxis == Axis.vertical &&
            dimensions != null &&
            dimensions.containsKey('height')) {
          sizeToApply = dimensions['height'];
          logDebug(
            _logTag,
            "LayoutManager: Using height=$sizeToApply for ${area.id} in vertical parent",
          );
        } else if (parentAxis == null) {
          // If parent axis is unknown, try width first, then height
          if (dimensions != null) {
            sizeToApply = dimensions['width'] ?? dimensions['height'];
            logDebug(
              _logTag,
              "LayoutManager: Using size=$sizeToApply for ${area.id} (root or unknown parent)",
            );
          }
        }

        // Apply the size if we have one
        if (sizeToApply != null) {
          (area as Area).updateSize(sizeToApply);
        }
      }

      // Process children recursively
      if (area is DockingRow) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            processArea(area.childAt(i), parentAxis: Axis.horizontal);
          } catch (e) {
            logError(
              _logTag,
              'Error processing child of DockingRow for size application: $e',
            );
          }
        }
      } else if (area is DockingColumn) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            processArea(area.childAt(i), parentAxis: Axis.vertical);
          } catch (e) {
            logError(
              _logTag,
              'Error processing child of DockingColumn for size application: $e',
            );
          }
        }
      } else if (area is DockingParentArea) {
        // Catch-all for other parent types if any
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            // Pass parentAxis as null if unknown for generic parent types
            processArea(area.childAt(i), parentAxis: null);
          } catch (e) {
            logError(
              _logTag,
              'Error processing child of generic DockingParentArea for size application: $e',
            );
          }
        }
      }
    }

    if (layout.root != null) {
      processArea(layout.root!); // Start with null parentAxis for root
    }
  }

  // This method is now called by ResizableDocking's listener and internal _onLayoutChanged
  void updateAreaDimensions() {
    // Renamed back
    // This method is now primarily for triggering a save after a resize operation via ResizableDocking
    // The actual updating of Area.width/height is done by the Docking widget itself.
    // We just need to make sure the latest state is saved.
    logDebug(
      _logTag,
      "LayoutManager: updateAreaDimensions called (likely after resize). Saving current state.",
    );
    _saveLayout();
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
    final col = DockingColumn(
      [previewItem, timelineItem],
      weight: 0.7,
      id: 'preview_timeline_column',
    );
    final insp = _buildInspectorItem(weight: 0.3);

    layout = DockingLayout(root: DockingRow([col, insp]));
    logDebug(
      _logTag,
      "LayoutManager: Built default layout. Saved layout will be applied if available.",
    );
  }

  // Build methods now can optionally take weight, maximized, and size for initial layout and restoration
  DockingItem _buildPreviewItem({
    double? weight,
    bool maximized = false,
    double? size,
  }) {
    return DockingItem(
      id: 'preview',
      name: 'Player',
      maximizable: false,
      widget: const PlayerPanel(),
      weight: weight,
      maximized: maximized,
      size: size,
    );
  }

  DockingItem _buildTimelineItem({
    double? weight,
    bool maximized = false,
    double? size,
  }) {
    return DockingItem(
      id: 'timeline',
      name: 'Timeline',
      widget: const Timeline(),
      weight: weight,
      maximized: maximized,
      size: size,
    );
  }

  DockingItem _buildInspectorItem({
    double? weight,
    bool maximized = false,
    double? size,
  }) {
    return DockingItem(
      id: 'inspector',
      name: 'Inspector',
      widget: const InspectorPanel(),
      weight: weight,
      maximized: maximized,
      size: size,
    );
  }

  void _togglePanel({
    required String panelId,
    required bool isCurrentlyVisible,
    required ValueNotifier<bool> visibilityNotifier,
    required DockingItem Function({
      double? weight,
      bool maximized,
      double? size,
    })
    itemBuilder,
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

      final newItem =
          itemBuilder(); // Build without specific dimensions, they'll be applied later

      if (isLayoutEmpty) {
        logDebug(
          _logTag,
          "LayoutManager: Layout is empty. Resetting layout with $panelId as root.",
        );
        layout = DockingLayout(root: newItem);
        _loadLayout();
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
        _saveLayout();
      }
    }
  }

  void toggleTimeline() {
    _togglePanel(
      panelId: 'timeline',
      isCurrentlyVisible: isTimelineVisible,
      visibilityNotifier: isTimelineVisibleNotifier,
      itemBuilder:
          ({double? weight, bool maximized = false, double? size}) =>
              _buildTimelineItem(
                weight: weight,
                maximized: maximized,
                size: size,
              ),
      defaultPositionHandler: _addTimelineDefaultPosition,
    );
  }

  void toggleInspector() {
    _togglePanel(
      panelId: 'inspector',
      isCurrentlyVisible: isInspectorVisible,
      visibilityNotifier: isInspectorVisibleNotifier,
      itemBuilder:
          ({double? weight, bool maximized = false, double? size}) =>
              _buildInspectorItem(
                weight: weight,
                maximized: maximized,
                size: size,
              ),
      defaultPositionHandler: _addInspectorDefaultPosition,
    );
  }

  void togglePreview() {
    _togglePanel(
      panelId: 'preview',
      isCurrentlyVisible: isPreviewVisible,
      visibilityNotifier: isPreviewVisibleNotifier,
      itemBuilder:
          ({double? weight, bool maximized = false, double? size}) =>
              _buildPreviewItem(
                weight: weight,
                maximized: maximized,
                size: size,
              ),
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
