import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:docking/docking.dart';

/// Manages the editor layout and currently selected panels, tools, etc.
class EditorViewModel {
  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>('');
  String get selectedExtension => selectedExtensionNotifier.value;
  set selectedExtension(String value) {
    if (selectedExtensionNotifier.value == value) return;
    selectedExtensionNotifier.value = value;
  }
  
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(null);
  String? get selectedClipId => selectedClipIdNotifier.value;
  set selectedClipId(String? value) {
    if (selectedClipIdNotifier.value == value) return;
    selectedClipIdNotifier.value = value;
  }
  
  final ValueNotifier<DockingLayout?> layoutNotifier = ValueNotifier<DockingLayout?>(null);
  DockingLayout? get layout => layoutNotifier.value; // This will be watched by the View
  set layout(DockingLayout? value) {
    if (layoutNotifier.value == value) return;
    layoutNotifier.value = value;
  }
  
  // Getter for a key representing the layout structure
  String get layoutStructureKey {
    // Generate a simple string based on visible panels
    final parts = ['preview']; // Preview is always there
    if (isTimelineVisible) parts.add('timeline');
    if (isInspectorVisible) parts.add('inspector');
    return parts.join('_');
  }
  
  // State flags for panel visibility
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  bool get isTimelineVisible => isTimelineVisibleNotifier.value;
  set isTimelineVisible(bool value) {
    if (isTimelineVisibleNotifier.value == value) return;
    isTimelineVisibleNotifier.value = value;
    _updateLayout();
  }
  
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  bool get isInspectorVisible => isInspectorVisibleNotifier.value;
  set isInspectorVisible(bool value) {
    if (isInspectorVisibleNotifier.value == value) return;
    isInspectorVisibleNotifier.value = value;
    _updateLayout();
  }
  
  // Helper methods to build DockingItems (avoids duplication)
  DockingItem _buildPreviewItem() {
    return DockingItem(
        id: 'preview',
        name: 'Preview',
        widget: Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'Preview',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
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
  
  // Build the layout based on current visibility settings
  void _buildLayout() {
    final items = <DockingItem>[];
    
    // Always add the preview
    items.add(_buildPreviewItem());
    
    // Add timeline if visible
    if (isTimelineVisible) {
      items.add(_buildTimelineItem());
    }
    
    // Add inspector if visible
    if (isInspectorVisible) {
      items.add(_buildInspectorItem());
    }
    
    // Create a layout with the items
    if (items.length == 1) {
      // Just preview
      layout = DockingLayout(root: items[0]);
    } else if (items.length == 2) {
      // Preview and one panel
      layout = DockingLayout(
        root: DockingRow([
          DockingItem(
            id: items[0].id,
            name: items[0].name,
            widget: items[0].widget,
            weight: 0.7
          ),
          DockingItem(
            id: items[1].id,
            name: items[1].name,
            widget: items[1].widget,
            weight: 0.3
          ),
        ]),
      );
    } else {
      // Preview and both panels
      layout = DockingLayout(
        root: DockingRow([
          DockingItem(
            id: items[0].id,
            name: items[0].name,
            widget: items[0].widget,
            weight: 0.6
          ),
          DockingColumn([
            DockingItem(
              id: items[1].id,
              name: items[1].name,
              widget: items[1].widget,
              weight: 0.5
            ),
            DockingItem(
              id: items[2].id,
              name: items[2].name,
              widget: items[2].widget,
              weight: 0.5
            ),
          ], weight: 0.4),
        ]),
      );
    }
  }
  
  // Update the layout
  void _updateLayout() {
    _buildLayout();
  }
  
  DockingLayout? getInitialLayout() {
    return layout;
  }
  
  void toggleTimeline() {
    isTimelineVisible = !isTimelineVisible;
    debugPrint("Toggle Timeline - Docking interaction TBD");
  }
  
  void toggleInspector() {
    isInspectorVisible = !isInspectorVisible;
    debugPrint("Toggle Inspector - Docking interaction TBD");
  }
  
  // Methods to update state when docking UI closes a panel
  void markInspectorClosed() {
    if (isInspectorVisible) { // Only update if it was considered visible
      isInspectorVisible = false;
      debugPrint("Marked Inspector Closed by Docking UI");
    }
  }
  
  void markTimelineClosed() {
    if (isTimelineVisible) { // Only update if it was considered visible
      isTimelineVisible = false;
      debugPrint("Marked Timeline Closed by Docking UI");
    }
  }
  
  void selectExtension(String extensionId) {
    selectedExtension = extensionId;
    debugPrint("Select Extension $extensionId - Docking interaction TBD");
  }
  
  void selectClip(String? clipId) {
    selectedClipId = clipId;
  }
  
  void initializePanelLayout() {
    final previewItem = DockingItem(
        id: 'preview', 
        name: 'Preview', 
        widget: Container(
          color: Colors.black,
          child: const Center(
            child: Text(
              'Preview',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
    );
    final timelineItem = DockingItem(
        id: 'timeline',
        name: 'Timeline',
        widget: const Timeline(),
    );
    final inspectorItem = DockingItem(
        id: 'inspector',
        name: 'Inspector',
        widget: const InspectorPanel(),
    );
    
    layout = DockingLayout(
      root: DockingRow([ // Root horizontal split
        DockingColumn([ // Left column
            previewItem, // Preview (takes weight from Column)
            timelineItem // Timeline (takes weight from Column)
          ]
        ),
        inspectorItem // Right column (Inspector, takes remaining space)
      ])
    );
  }
}
