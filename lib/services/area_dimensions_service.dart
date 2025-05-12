import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:docking/docking.dart';

/// Service responsible for persisting and restoring area dimensions in SharedPreferences
class AreaDimensionsService {
  static const String _dimensionsKey = 'editor_area_dimensions';
  static const String _layoutStringKey = 'editor_layout_string';
  final String _logTag = 'AreaDimensionsService';

  /// Saves area dimensions to SharedPreferences
  /// 
  /// Takes a map of area IDs to dimension objects containing width and height
  Future<void> saveAreaDimensions(Map<String, Map<String, double>> dimensions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert dimensions to a format that can be stored in SharedPreferences
      Map<String, String> serializedDimensions = {};
      dimensions.forEach((areaId, areaDimensions) {
        serializedDimensions[areaId] = areaDimensions.entries
            .map((e) => '${e.key}:${e.value}')
            .join(',');
      });
      
      await prefs.setString(_dimensionsKey, serializedDimensions.toString());
      logDebug(_logTag, 'Saved dimensions for ${dimensions.length} areas');
    } catch (e) {
      logError(_logTag, 'Error saving area dimensions: $e');
    }
  }

  /// Loads area dimensions from SharedPreferences
  /// 
  /// Returns a map of area IDs to dimension objects containing width and height
  Future<Map<String, Map<String, double>>?> loadAreaDimensions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? serialized = prefs.getString(_dimensionsKey);
      
      if (serialized == null || serialized.isEmpty) {
        return null;
      }
      
      // Parse the serialized string back to a Map
      Map<String, Map<String, double>> dimensions = {};
      
      // Remove the outer braces
      String content = serialized.substring(1, serialized.length - 1);
      
      // Split by comma and space outside of values
      List<String> entries = content.split(', ');
      
      for (String entry in entries) {
        List<String> keyValue = entry.split(': ');
        if (keyValue.length == 2) {
          String areaId = keyValue[0].replaceAll(RegExp(r'^"|"$'), '');
          String dimensionsStr = keyValue[1];
          
          // Parse the inner dimensions map
          Map<String, double> areaDimensions = {};
          List<String> dimensionEntries = dimensionsStr.split(',');
          
          for (String dimEntry in dimensionEntries) {
            List<String> dimKeyValue = dimEntry.split(':');
            if (dimKeyValue.length == 2) {
              areaDimensions[dimKeyValue[0]] = double.parse(dimKeyValue[1]);
            }
          }
          
          dimensions[areaId] = areaDimensions;
        }
      }
      
      logDebug(_logTag, 'Loaded dimensions for ${dimensions.length} areas');
      return dimensions;
    } catch (e) {
      logError(_logTag, 'Error loading area dimensions: $e');
      return null;
    }
  }
  
  /// Collects dimensions from all areas in a DockingLayout
  Map<String, Map<String, double>> collectAreaDimensions(DockingLayout layout) {
    Map<String, Map<String, double>> dimensions = {};

    void processArea(DockingArea area) {
      // Only store dimensions for areas with IDs
      if (area.id != null) {
        Map<String, double> areaDimensions = {};
        
        if (area.width != null) {
          areaDimensions['width'] = area.width!;
        }
        
        if (area.height != null) {
          areaDimensions['height'] = area.height!;
        }
        
        if (areaDimensions.isNotEmpty) {
          dimensions[area.id.toString()] = areaDimensions;
        }
      }

      // Process children recursively
      if (area is DockingParentArea) {
        for (int i = 0; i < area.childrenCount; i++) {
          processArea(area.childAt(i));
        }
      }
    }

    if (layout.root != null) {
      processArea(layout.root!);
    }

    return dimensions;
  }
  
  /// Applies saved dimensions to areas in a DockingLayout
  void applyDimensions(DockingLayout layout, Map<String, Map<String, double>> dimensions) {
    void processArea(DockingArea area) {
      if (area.id != null && dimensions.containsKey(area.id.toString())) {
        final areaDimensions = dimensions[area.id.toString()]!;
        
        if (areaDimensions.containsKey('width')) {
          area.width = areaDimensions['width'];
        }
        
        if (areaDimensions.containsKey('height')) {
          area.height = areaDimensions['height'];
        }
      }

      // Process children recursively
      if (area is DockingParentArea) {
        for (int i = 0; i < area.childrenCount; i++) {
          processArea(area.childAt(i));
        }
      }
    }

    if (layout.root != null) {
      processArea(layout.root!);
    }
  }

  // Save complete layout string
  Future<void> saveLayoutString(String layoutString) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_layoutStringKey, layoutString);
      logDebug(_logTag, 'Saved complete layout string (length: ${layoutString.length})');
    } catch (e) {
      logError(_logTag, 'Error saving layout string: $e');
    }
  }

  // Load complete layout string
  Future<String?> loadLayoutString() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? layoutString = prefs.getString(_layoutStringKey);
      
      if (layoutString != null && layoutString.isNotEmpty) {
        logDebug(_logTag, 'Loaded layout string (length: ${layoutString.length})');
      } else {
        logDebug(_logTag, 'No saved layout string found');
      }
      
      return layoutString;
    } catch (e) {
      logError(_logTag, 'Error loading layout string: $e');
      return null;
    }
  }
} 