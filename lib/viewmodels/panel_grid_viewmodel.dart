import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/panel_system/panel_models.dart';

class PanelGridViewModel extends ChangeNotifier {
  String? _dropTargetId;
  DropPosition? _dropPosition;

  String? get dropTargetId => _dropTargetId;
  DropPosition? get dropPosition => _dropPosition;

  void updateDropTarget(String? targetId, DropPosition? position) {
    if (_dropTargetId != targetId || _dropPosition != position) {
      _dropTargetId = targetId;
      _dropPosition = position;
      notifyListeners();
    }
  }

  void clearDropTarget() {
    if (_dropTargetId != null || _dropPosition != null) {
      _dropTargetId = null;
      _dropPosition = null;
      notifyListeners();
    }
  }
} 