import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flipedit/utils/logger.dart';

class LayoutService {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  static const String _visibilityStateKey = 'editor_panel_visibility';
  static const String _layoutStringKey = 'editor_layout_string';

  Future<void> saveVisibilityState(Map<String, bool> visibilityState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonState = jsonEncode(visibilityState);
      await prefs.setString(_visibilityStateKey, jsonState);
      logDebug(_logTag, 'Panel visibility state saved: $jsonState');
    } catch (e) {
      logError(_logTag, 'Error saving visibility state: $e');
    }
  }

  Future<Map<String, bool>?> loadVisibilityState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonState = prefs.getString(_visibilityStateKey);
      if (jsonState != null && jsonState.isNotEmpty) {
        final Map<String, dynamic> decodedMap = jsonDecode(jsonState);
        final visibilityState = decodedMap.map((key, value) => MapEntry(key, value as bool));
        logDebug(_logTag, 'Panel visibility state loaded: $visibilityState');
        return visibilityState;
      } else {
        logDebug(_logTag, 'No saved visibility state found.');
        return null;
      }
    } catch (e) {
      logError(_logTag, 'Error loading visibility state: $e');
      return null;
    }
  }

  Future<void> saveLayoutString(String layoutString) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_layoutStringKey, layoutString);
      logDebug(_logTag, 'Layout string saved. Length: ${layoutString.length}');
    } catch (e) {
      logError(_logTag, 'Error saving layout string: $e');
    }
  }

  Future<String?> loadLayoutString() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final layoutString = prefs.getString(_layoutStringKey);
      if (layoutString != null && layoutString.isNotEmpty) {
        logDebug(_logTag, 'Layout string loaded. Length: ${layoutString.length}');
        return layoutString;
      } else {
        logDebug(_logTag, 'No saved layout string found.');
        return null;
      }
    } catch (e) {
      logError(_logTag, 'Error loading layout string: $e');
      return null;
    }
  }
} 