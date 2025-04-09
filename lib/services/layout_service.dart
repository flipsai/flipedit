import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LayoutService {
  static const String _visibilityStateKey = 'editor_panel_visibility';
  static const String _layoutStringKey = 'editor_layout_string';

  Future<void> saveVisibilityState(Map<String, bool> visibilityState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonState = jsonEncode(visibilityState);
      await prefs.setString(_visibilityStateKey, jsonState);
      print('Panel visibility state saved: $jsonState');
    } catch (e) {
      print('Error saving visibility state: $e');
    }
  }

  Future<Map<String, bool>?> loadVisibilityState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonState = prefs.getString(_visibilityStateKey);
      if (jsonState != null && jsonState.isNotEmpty) {
        final Map<String, dynamic> decodedMap = jsonDecode(jsonState);
        final visibilityState = decodedMap.map((key, value) => MapEntry(key, value as bool));
        print('Panel visibility state loaded: $visibilityState');
        return visibilityState;
      } else {
        print('No saved visibility state found.');
        return null;
      }
    } catch (e) {
      print('Error loading visibility state: $e');
      return null;
    }
  }

  Future<void> saveLayoutString(String layoutString) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_layoutStringKey, layoutString);
      print('Layout string saved. Length: ${layoutString.length}');
    } catch (e) {
      print('Error saving layout string: $e');
    }
  }

  Future<String?> loadLayoutString() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final layoutString = prefs.getString(_layoutStringKey);
      if (layoutString != null && layoutString.isNotEmpty) {
        print('Layout string loaded. Length: ${layoutString.length}');
        return layoutString;
      } else {
        print('No saved layout string found.');
        return null;
      }
    } catch (e) {
      print('Error loading layout string: $e');
      return null;
    }
  }
} 