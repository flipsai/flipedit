import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tab_group.dart';
import '../viewmodels/tab_system_viewmodel.dart';
import '../utils/logger.dart' as logger;

class TabSystemPersistenceService {
  static const String _logTag = 'TabSystemPersistenceService';
  static const String _tabGroupsKey = 'tab_system_groups';
  static const String _activeGroupKey = 'tab_system_active_group';
  static const String _panelSizesKey = 'tab_system_panel_sizes';
  static const String _layoutOrientationKey = 'tab_system_layout_orientation';

  static TabSystemPersistenceService? _instance;
  static TabSystemPersistenceService get instance {
    _instance ??= TabSystemPersistenceService._();
    return _instance!;
  }

  TabSystemPersistenceService._();

  Future<void> saveTabSystemState({
    required List<TabGroup> tabGroups,
    required String? activeGroupId,
    Map<String, double>? panelSizes,
    TabSystemLayout? layoutOrientation,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save tab groups
      final groupsJson = tabGroups.map((group) => group.toJson()).toList();
      await prefs.setString(_tabGroupsKey, jsonEncode(groupsJson));

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

      // Save layout orientation
      if (layoutOrientation != null) {
        await prefs.setString(_layoutOrientationKey, layoutOrientation.name);
      }

      logger.logInfo('Saved tab system state: ${tabGroups.length} groups, active: $activeGroupId, layout: ${layoutOrientation?.name}', _logTag);
    } catch (e) {
      logger.logError('Failed to save tab system state: $e', _logTag);
    }
  }

  Future<TabSystemState> loadTabSystemState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load tab groups
      final groupsString = prefs.getString(_tabGroupsKey);
      List<TabGroup> tabGroups = [];
      
      if (groupsString != null) {
        final groupsJson = jsonDecode(groupsString) as List;
        tabGroups = groupsJson
            .map((json) => TabGroup.fromJson(json as Map<String, dynamic>))
            .toList();
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

      logger.logInfo('Loaded tab system state: ${tabGroups.length} groups, active: $activeGroupId, layout: ${layoutOrientation.name}', _logTag);
      
      return TabSystemState(
        tabGroups: tabGroups,
        activeGroupId: activeGroupId,
        panelSizes: panelSizes,
        layoutOrientation: layoutOrientation,
      );
    } catch (e) {
      logger.logError('Failed to load tab system state: $e', _logTag);
      return TabSystemState(
        tabGroups: [], 
        activeGroupId: null, 
        panelSizes: {},
        layoutOrientation: TabSystemLayout.horizontal,
      );
    }
  }

  Future<void> clearTabSystemState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tabGroupsKey);
      await prefs.remove(_activeGroupKey);
      await prefs.remove(_panelSizesKey);
      await prefs.remove(_layoutOrientationKey);
      
      logger.logInfo('Cleared tab system state', _logTag);
    } catch (e) {
      logger.logError('Failed to clear tab system state: $e', _logTag);
    }
  }

  Future<bool> hasPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_tabGroupsKey);
    } catch (e) {
      logger.logError('Failed to check for persisted state: $e', _logTag);
      return false;
    }
  }
}

class TabSystemState {
  final List<TabGroup> tabGroups;
  final String? activeGroupId;
  final Map<String, double> panelSizes;
  final TabSystemLayout layoutOrientation;

  const TabSystemState({
    required this.tabGroups,
    required this.activeGroupId,
    required this.panelSizes,
    required this.layoutOrientation,
  });
} 