import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:docking/docking.dart';

/// Manages the editor layout and currently selected panels, tools, etc.
class EditorViewModel extends ChangeNotifier {
  String _selectedExtension = '';
  String get selectedExtension => _selectedExtension;
  
  String? _selectedClipId;
  String? get selectedClipId => _selectedClipId;
  
  DockingLayout? _layout;
  DockingLayout? get layout => _layout;
  
  void toggleTimeline() {
    debugPrint("Toggle Timeline - Docking interaction TBD");
  }
  
  void toggleInspector() {
    debugPrint("Toggle Inspector - Docking interaction TBD");
  }
  
  void selectExtension(String extensionId) {
    _selectedExtension = extensionId;
    debugPrint("Select Extension $extensionId - Docking interaction TBD");
    notifyListeners();
  }
  
  void selectClip(String? clipId) {
    _selectedClipId = clipId;
    notifyListeners();
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
    
    _layout = DockingLayout(
      root: DockingRow([ // Root horizontal split
        DockingColumn([ // Left column
            previewItem, // Preview (takes weight from Column)
            timelineItem // Timeline (takes weight from Column)
          ]
        ),
        inspectorItem // Right column (Inspector, takes remaining space)
      ])
    );
    
    notifyListeners();
  }
  
  DockingLayout? getInitialLayout() {
      return layout;
  }

}
