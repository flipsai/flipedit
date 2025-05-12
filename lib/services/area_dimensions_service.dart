import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:docking/docking.dart';

/// Service responsible for persisting and restoring area dimensions in SharedPreferences
class AreaDimensionsService {
  String get _logTag => runtimeType.toString();

  static const String _areaDimensionsKey = 'area_dimensions';

  /// Saves area dimensions to SharedPreferences
  /// 
  /// Takes a map of area IDs to dimension objects containing width and height
  Future<void> saveAreaDimensions(Map<String, Map<String, double>> dimensions) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonDimensions = jsonEncode(dimensions);
      await prefs.setString(_areaDimensionsKey, jsonDimensions);
      logDebug(_logTag, 'Area dimensions saved: ${dimensions.length} areas');
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
      final jsonDimensions = prefs.getString(_areaDimensionsKey);
      
      if (jsonDimensions != null && jsonDimensions.isNotEmpty) {
        final Map<String, dynamic> decodedMap = jsonDecode(jsonDimensions);
        
        // Convert the decoded JSON into the correct type
        final dimensions = <String, Map<String, double>>{};
        decodedMap.forEach((areaId, dimensionData) {
          // Ensure dimensionData is treated as Map<String, dynamic> before mapping
          if (dimensionData is Map) {
             final dimensionMap = Map<String, dynamic>.from(dimensionData)
                .map((key, value) => MapEntry(key, value as double));
             dimensions[areaId] = dimensionMap; 
          } else {
             logWarning(_logTag, 'Skipping invalid dimension data for area $areaId: $dimensionData');
          }
        });
        
        logDebug(_logTag, 'Area dimensions loaded: ${dimensions.length} areas');
        return dimensions;
      } else {
        logDebug(_logTag, 'No saved area dimensions found.');
        return null;
      }
    } catch (e) {
      logError(_logTag, 'Error loading area dimensions: $e');
      return null;
    }
  }
  
  /// Collects dimensions from all areas in a DockingLayout
  Map<String, Map<String, double>> collectAreaDimensions(DockingLayout layout) {
    final dimensions = <String, Map<String, double>>{};
    
    void processDockingArea(DockingArea area) {
      // Only process areas with an ID and dimensions
      if (area.id != null && (area.width != null || area.height != null)) {
        final Map<String, double> areaDimensions = {};
        
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
      
      // Process children if this is a parent area
      if (area is DockingParentArea) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
             final child = area.childAt(i);
             processDockingArea(child);
          } catch (e) {
             logError(_logTag, 'Error accessing child at index $i for area ${area.id}: $e');
          } 
        }
      }
    }
    
    if (layout.root != null) {
      processDockingArea(layout.root!);
    }
    
    return dimensions;
  }
  
  /// Applies saved dimensions to areas in a DockingLayout
  void applyDimensions(DockingLayout layout, Map<String, Map<String, double>> dimensions) {
    void processDockingArea(DockingArea area) {
      // Apply dimensions if this area has an ID and saved data exists
      if (area.id != null && dimensions.containsKey(area.id.toString())) {
        final areaDimensions = dimensions[area.id.toString()]!;
        logDebug(_logTag, 'Applying dimensions to ${area.id}: w=${areaDimensions['width']}, h=${areaDimensions['height']}');
        area.updateDimensions(
          areaDimensions['width'], 
          areaDimensions['height'],
        );
      }
      
      // Process children if this is a parent area
      if (area is DockingParentArea) {
        for (int i = 0; i < area.childrenCount; i++) {
          try {
            final child = area.childAt(i);
            processDockingArea(child);
          } catch (e) {
            logError(_logTag, 'Error applying dimensions to child at index $i for area ${area.id}: $e');
          }
        }
      }
    }
    
    if (layout.root != null) {
      processDockingArea(layout.root!); 
    }
  }
} 