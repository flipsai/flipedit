import 'package:flutter/foundation.dart';

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
  
  // Toggle sidebar panels
  void toggleTimeline() {
    _showTimeline = !_showTimeline;
    notifyListeners();
  }
  
  void toggleInspector() {
    _showInspector = !_showInspector;
    notifyListeners();
  }
  
  void togglePreview() {
    _showPreview = !_showPreview;
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
}
