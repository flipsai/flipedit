import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tab_group.dart';
import '../models/tab_line.dart';
import '../viewmodels/tab_system_viewmodel.dart';
import '../utils/logger.dart' as logger;

class TabSystemPersistenceService {
  static const String _logTag = 'TabSystemPersistenceService';
  static const String _tabLinesKey = 'tab_system_lines';
  static const String _activeLineKey = 'tab_system_active_line';
  static const String _activeGroupKey = 'tab_system_active_group';
  static const String _panelSizesKey = 'tab_system_panel_sizes';
  static const String _lineSizesKey = 'tab_system_line_sizes';
  static const String _layoutOrientationKey = 'tab_system_layout_orientation';

  // Legacy keys for backward compatibility
  static const String _legacyTabGroupsKey = 'tab_system_groups';

  static TabSystemPersistenceService? _instance;
  static TabSystemPersistenceService get instance {
    _instance ??= TabSystemPersistenceService._();
    return _instance!;
  }

  TabSystemPersistenceService._();

  Future<void> saveTabSystemState({
    List<TabLine>? tabLines,
    List<TabGroup>? tabGroups, // For backward compatibility
    String? activeLineId,
    required String? activeGroupId,
    Map<String, double>? panelSizes,
    Map<String, double>? lineSizes,
    TabSystemLayout? layoutOrientation,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // If we have the new structure, save it
      if (tabLines != null) {
        final linesJson = tabLines.map((line) => line.toJson()).toList();
        await prefs.setString(_tabLinesKey, jsonEncode(linesJson));
        
        // Save active line
        if (activeLineId != null) {
          await prefs.setString(_activeLineKey, activeLineId);
        } else {
          await prefs.remove(_activeLineKey);
        }
        
        // Clear legacy format
        await prefs.remove(_legacyTabGroupsKey);
      } 
      // Fall back to legacy format for backward compatibility
      else if (tabGroups != null) {
        final groupsJson = tabGroups.map((group) => group.toJson()).toList();
        await prefs.setString(_legacyTabGroupsKey, jsonEncode(groupsJson));
      }

      // Save active group
      if (activeGroupId != null) {
        await prefs.setString(_activeGroupKey, activeGroupId);
      } else {
        await prefs.remove(_activeGroupKey);
      }

      // Save panel sizes
      if (panelSizes != null && panelSizes.isNotEmpty) {
        await prefs.setString(_panelSizesKey, jsonEncode(panelSizes));
      }

      // Save line sizes
      if (lineSizes != null && lineSizes.isNotEmpty) {
        await prefs.setString(_lineSizesKey, jsonEncode(lineSizes));
      }

      // Save layout orientation
      if (layoutOrientation != null) {
        await prefs.setString(_layoutOrientationKey, layoutOrientation.name);
      }

      final count = tabLines?.length ?? tabGroups?.length ?? 0;
      logger.logInfo('Saved tab system state: $count ${tabLines != null ? 'lines' : 'groups'}, active line: $activeLineId, active group: $activeGroupId, layout: ${layoutOrientation?.name}', _logTag);
    } catch (e) {
      logger.logError('Failed to save tab system state: $e', _logTag);
    }
  }

  Future<TabSystemState> loadTabSystemState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      List<TabLine> tabLines = [];
      List<TabGroup> tabGroups = [];
      String? activeLineId;

      // Try to load new format first
      final linesString = prefs.getString(_tabLinesKey);
      if (linesString != null) {
        final linesJson = jsonDecode(linesString) as List;
        tabLines = linesJson
            .map((json) => TabLine.fromJson(json as Map<String, dynamic>))
            .toList();
        
        // Load active line
        activeLineId = prefs.getString(_activeLineKey);
        
        // Convert TabLines to legacy TabGroups for compatibility
        for (final line in tabLines) {
          tabGroups.addAll(line.tabColumns);
        }
      } else {
        // Fall back to legacy format
        final groupsString = prefs.getString(_legacyTabGroupsKey);
        if (groupsString != null) {
          final groupsJson = jsonDecode(groupsString) as List;
          tabGroups = groupsJson
              .map((json) => TabGroup.fromJson(json as Map<String, dynamic>))
              .toList();
          
          // Create a single TabLine from legacy groups for migration
          if (tabGroups.isNotEmpty) {
            final defaultLine = TabLine(
              id: 'migrated_line',
              tabColumns: tabGroups,
            );
            tabLines = [defaultLine];
            activeLineId = defaultLine.id;
          }
        }
      }

      // Load active group
      final activeGroupId = prefs.getString(_activeGroupKey);

      // Load panel sizes
      final panelSizesString = prefs.getString(_panelSizesKey);
      Map<String, double> panelSizes = {};
      
      if (panelSizesString != null) {
        final sizesJson = jsonDecode(panelSizesString) as Map<String, dynamic>;
        panelSizes = sizesJson.map((key, value) => MapEntry(key, (value as num).toDouble()));
      }

      // Load line sizes
      final lineSizesString = prefs.getString(_lineSizesKey);
      Map<String, double> lineSizes = {};
      
      if (lineSizesString != null) {
        final sizesJson = jsonDecode(lineSizesString) as Map<String, dynamic>;
        lineSizes = sizesJson.map((key, value) => MapEntry(key, (value as num).toDouble()));
      }

      // Load layout orientation
      final layoutOrientationString = prefs.getString(_layoutOrientationKey);
      TabSystemLayout layoutOrientation = TabSystemLayout.horizontal; // default
      
      if (layoutOrientationString != null) {
        switch (layoutOrientationString) {
          case 'horizontal':
            layoutOrientation = TabSystemLayout.horizontal;
            break;
          case 'vertical':
            layoutOrientation = TabSystemLayout.vertical;
            break;
          default:
            layoutOrientation = TabSystemLayout.horizontal;
        }
      }

      logger.logInfo('Loaded tab system state: ${tabLines.length} lines, ${tabGroups.length} groups, active line: $activeLineId, active group: $activeGroupId, layout: ${layoutOrientation.name}', _logTag);
      
      return TabSystemState(
        tabLines: tabLines,
        tabGroups: tabGroups,
        activeLineId: activeLineId,
        activeGroupId: activeGroupId,
        panelSizes: panelSizes,
        lineSizes: lineSizes,
        layoutOrientation: layoutOrientation,
      );
    } catch (e) {
      logger.logError('Failed to load tab system state: $e', _logTag);
      return TabSystemState(
        tabLines: [],
        tabGroups: [], 
        activeLineId: null,
        activeGroupId: null, 
        panelSizes: {},
        lineSizes: {},
        layoutOrientation: TabSystemLayout.horizontal,
      );
    }
  }

  Future<void> clearTabSystemState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tabLinesKey);
      await prefs.remove(_activeLineKey);
      await prefs.remove(_activeGroupKey);
      await prefs.remove(_panelSizesKey);
      await prefs.remove(_lineSizesKey);
      await prefs.remove(_layoutOrientationKey);
      
      // Clear legacy keys too
      await prefs.remove(_legacyTabGroupsKey);
      
      logger.logInfo('Cleared tab system state', _logTag);
    } catch (e) {
      logger.logError('Failed to clear tab system state: $e', _logTag);
    }
  }

  Future<bool> hasPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_tabLinesKey) || prefs.containsKey(_legacyTabGroupsKey);
    } catch (e) {
      logger.logError('Failed to check for persisted state: $e', _logTag);
      return false;
    }
  }
}

class TabSystemState {
  final List<TabLine> tabLines;
  final List<TabGroup> tabGroups;
  final String? activeLineId;
  final String? activeGroupId;
  final Map<String, double> panelSizes;
  final Map<String, double> lineSizes;
  final TabSystemLayout layoutOrientation;

  const TabSystemState({
    required this.tabLines,
    required this.tabGroups,
    this.activeLineId,
    required this.activeGroupId,
    required this.panelSizes,
    required this.lineSizes,
    required this.layoutOrientation,
  });
} 