import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/panel_system/panel_system.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

/// Manages the editor layout and currently selected panels, tools, etc.
class EditorViewModel extends ChangeNotifier {
  String _selectedExtension = '';
  String get selectedExtension => _selectedExtension;
  
  bool _showTimeline = true;
  bool get showTimeline => _showTimeline;
  
  bool _showInspector = true;
  bool get showInspector => _showInspector;
  
  bool _showPreview = true;
  bool get showPreview => _showPreview;
  
  String? _selectedClipId;
  String? get selectedClipId => _selectedClipId;
  
  // Panel layout model
  PanelLayoutModel? _panelLayout;
  PanelLayoutModel? get panelLayout => _panelLayout;
  
  // Panel definitions
  final List<PanelDefinition> _panels = [];
  List<PanelDefinition> get panels => List.unmodifiable(_panels);
  
  // Panel IDs for common panels
  String? _previewPanelId;
  String? _timelinePanelId;
  String? _inspectorPanelId;
  
  // Toggle sidebar panels
  void toggleTimeline() {
    _showTimeline = !_showTimeline;
    _updatePanelVisibility();
    notifyListeners();
  }
  
  void toggleInspector() {
    _showInspector = !_showInspector;
    _updatePanelVisibility();
    notifyListeners();
  }
  
  void togglePreview() {
    _showPreview = !_showPreview;
    _updatePanelVisibility();
    notifyListeners();
  }
  
  // Select extension in sidebar
  void selectExtension(String extensionId) {
    _selectedExtension = extensionId;
    notifyListeners();
  }
  
  // Select a clip on the timeline
  void selectClip(String? clipId) {
    _selectedClipId = clipId;
    notifyListeners();
  }
  
  // Initialize panel layout
  void initializePanelLayout() {
    // Create main panels
    _previewPanelId = _createPreviewPanel()?.id;
    _timelinePanelId = _createTimelinePanel()?.id;
    _inspectorPanelId = _createInspectorPanel()?.id;
    
    // Create initial layout
    _panelLayout = PanelLayoutModel.fromInitialPanels(_panels);
    
    notifyListeners();
  }
  
  // Create the preview panel
  PanelDefinition? _createPreviewPanel() {
    final panel = PanelDefinition(
      title: 'Preview',
      icon: fluent.FluentIcons.play,
      content: Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            'Preview',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
    
    _panels.add(panel);
    return panel;
  }
  
  // Create the timeline panel
  PanelDefinition? _createTimelinePanel() {
    final panel = PanelDefinition(
      title: 'Timeline',
      icon: fluent.FluentIcons.timeline,
      content: const Timeline(),
    );
    
    _panels.add(panel);
    return panel;
  }
  
  // Create the inspector panel
  PanelDefinition? _createInspectorPanel() {
    final panel = PanelDefinition(
      title: 'Inspector',
      icon: fluent.FluentIcons.edit_mirrored,
      content: const InspectorPanel(),
    );
    
    _panels.add(panel);
    return panel;
  }
  
  // Create an extension panel
  PanelDefinition createExtensionPanel(String extensionId) {
    final panel = PanelDefinition(
      title: _getExtensionTitle(extensionId),
      icon: _getExtensionIcon(extensionId),
      content: ExtensionPanelContainer(extensionId: extensionId),
    );
    
    _panels.add(panel);
    return panel;
  }
  
  // Get panel definitions for current visible panels
  List<PanelDefinition> getPanelDefinitions() {
    final visiblePanels = <PanelDefinition>[];
    
    // Add visible panels based on current state
    for (var panel in _panels) {
      if (panel.id == _previewPanelId && _showPreview) {
        visiblePanels.add(panel);
      } else if (panel.id == _timelinePanelId && _showTimeline) {
        visiblePanels.add(panel);
      } else if (panel.id == _inspectorPanelId && _showInspector) {
        visiblePanels.add(panel);
      }
      // Add extension panels
      else if (_selectedExtension.isNotEmpty) {
        // Check if this is the panel for the selected extension
        // This is simplified - in a real app, you'd have a proper mapping
        if (panel.title.toLowerCase() == _selectedExtension.toLowerCase()) {
          visiblePanels.add(panel);
        }
      }
    }
    
    return visiblePanels;
  }
  
  // Update panel visibility in the layout model
  void _updatePanelVisibility() {
    // This would update the panel layout model based on visibility changes
    // For now, we'll rely on getPanelDefinitions() for the simplified version
  }
  
  // Helper to get an extension title
  String _getExtensionTitle(String extensionId) {
    switch (extensionId) {
      case 'media':
        return 'Media';
      case 'composition':
        return 'Composition';
      case 'backgroundRemoval':
        return 'Background Removal';
      case 'replace':
        return 'Replace';
      case 'track':
        return 'Object Tracking';
      case 'addFx':
        return 'Add FX';
      case 'generate':
        return 'Generate';
      case 'enhance':
        return 'Enhance';
      case 'export':
        return 'Export';
      case 'settings':
        return 'Settings';
      default:
        return extensionId.toString();
    }
  }
  
  // Helper to get an extension icon
  IconData _getExtensionIcon(String extensionId) {
    switch (extensionId) {
      case 'media':
        return fluent.FluentIcons.folder_open;
      case 'composition':
        return fluent.FluentIcons.video;
      case 'backgroundRemoval':
        return fluent.FluentIcons.broom;
      case 'replace':
        return fluent.FluentIcons.refresh;
      case 'track':
        return fluent.FluentIcons.view;
      case 'addFx':
        return fluent.FluentIcons.add;
      case 'generate':
        return fluent.FluentIcons.picture;
      case 'enhance':
        return fluent.FluentIcons.color;
      case 'export':
        return fluent.FluentIcons.export;
      case 'settings':
        return fluent.FluentIcons.settings;
      default:
        return fluent.FluentIcons.document;
    }
  }
}
