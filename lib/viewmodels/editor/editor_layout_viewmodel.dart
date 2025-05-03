import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:docking/docking.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flipedit/views/widgets/preview/preview_panel.dart';
import 'package:flipedit/utils/logger.dart'; // Add logger import

class EditorLayoutViewModel {
  // Remove LoggerExtension
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
    _buildInitialLayout();
  }

  void dispose() {
    layoutNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
    isPreviewVisibleNotifier.dispose();

    // Remove layout listener
    if (layoutNotifier.value != null && _layoutListener != null) {
      layoutNotifier.value!.removeListener(_layoutListener!);
    }
  }

  void _onLayoutChanged() {
    logDebug(_logTag, "LayoutManager: DockingLayout changed internally.");
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
    layout = _buildDefaultLayout();
    logDebug(_logTag, "LayoutManager: Built default layout.");
  }

  DockingLayout _buildDefaultLayout() {
    final previewItem = _buildPreviewItem();
    final timelineItem = _buildTimelineItem();
    final inspectorItem = _buildInspectorItem();

    isTimelineVisibleNotifier.value = true;
    isInspectorVisibleNotifier.value = true;
    isPreviewVisibleNotifier.value = true;

    return DockingLayout(
      root: DockingRow([
        DockingColumn([previewItem, timelineItem]),
        inspectorItem,
      ]),
    );
  }

  DockingItem _buildPreviewItem() {
    return DockingItem(
      id: 'preview',
      name: 'Preview',
      maximizable: false,
      widget: const PreviewPanel(),
    );
  }

  DockingItem _buildTimelineItem() {
    return DockingItem(
      id: 'timeline',
      name: 'Timeline',
      widget: const Timeline(),
    );
  }

  DockingItem _buildInspectorItem() {
    return DockingItem(
      id: 'inspector',
      name: 'Inspector',
      widget: const InspectorPanel(),
    );
  }

  void _togglePanel({
    required String panelId,
    required bool isCurrentlyVisible,
    required ValueNotifier<bool> visibilityNotifier,
    required DockingItem Function() itemBuilder,
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
      // Check if the layout is effectively empty
      bool isLayoutEmpty =
          currentLayout.findDockingItem('preview') == null &&
          currentLayout.findDockingItem('inspector') == null &&
          currentLayout.findDockingItem('timeline') == null;

      if (isLayoutEmpty) {
        logDebug(
          _logTag,
          "LayoutManager: Layout is empty. Resetting layout with $panelId as root.",
        );
        layout = DockingLayout(root: itemBuilder());
      } else {
        // Layout is not empty, proceed with restoring/adding
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
              newItem: itemBuilder(),
              targetArea: adjacentItem,
              dropPosition: position,
            );
          } else {
            defaultPositionHandler(currentLayout);
          }
        } else {
          defaultPositionHandler(currentLayout);
        }
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

    if (targetItem != null) {
      layout.addItemOn(
        newItem: _buildTimelineItem(),
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Timeline - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: _buildTimelineItem());
    }
  }

  void _addInspectorDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem =
        layout.findDockingItem('preview') ?? layout.findDockingItem('timeline');
    DropPosition position = DropPosition.right;

    if (targetItem != null) {
      layout.addItemOn(
        newItem: _buildInspectorItem(),
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Inspector - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: _buildInspectorItem());
    }
  }

  void _addPreviewDefaultPosition(DockingLayout layout) {
    DockingItem? targetItem =
        layout.findDockingItem('timeline') ??
        layout.findDockingItem('inspector');
    DropPosition position = DropPosition.left;

    if (targetItem != null) {
      layout.addItemOn(
        newItem: _buildPreviewItem(),
        targetArea: targetItem,
        dropPosition: position,
      );
    } else {
      logDebug(
        _logTag,
        "LayoutManager: Preview - No suitable target, adding to root.",
      );
      layout.addItemOnRoot(newItem: _buildPreviewItem());
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
