import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import '../models/tab_item.dart';
import '../models/tab_group.dart';
import '../services/tab_system_persistence_service.dart';
import '../utils/logger.dart' as logger;

enum TabSystemLayout { horizontal, vertical }

class TabSystemViewModel extends ChangeNotifier {
  final String _logTag = 'TabSystemViewModel';
  final TabSystemPersistenceService _persistenceService = TabSystemPersistenceService.instance;

  final ValueNotifier<List<TabGroup>> tabGroupsNotifier = 
      ValueNotifier<List<TabGroup>>([]);
  List<TabGroup> get tabGroups => List.unmodifiable(tabGroupsNotifier.value);

  final ValueNotifier<String?> activeGroupIdNotifier = ValueNotifier<String?>(null);
  String? get activeGroupId => activeGroupIdNotifier.value;
  set activeGroupId(String? value) {
    if (activeGroupIdNotifier.value != value) {
      logger.logInfo('Active tab group changed: ${activeGroupIdNotifier.value} -> $value', _logTag);
      activeGroupIdNotifier.value = value;
      _saveState();
    }
  }

  final ValueNotifier<TabSystemLayout> layoutOrientationNotifier = 
      ValueNotifier<TabSystemLayout>(TabSystemLayout.horizontal);
  TabSystemLayout get layoutOrientation => layoutOrientationNotifier.value;
  set layoutOrientation(TabSystemLayout value) {
    if (layoutOrientationNotifier.value != value) {
      logger.logInfo('Layout orientation changed: ${layoutOrientationNotifier.value} -> $value', _logTag);
      layoutOrientationNotifier.value = value;
      _saveState();
    }
  }

  final ValueNotifier<Map<String, double>> panelSizesNotifier = 
      ValueNotifier<Map<String, double>>({});
  Map<String, double> get panelSizes => Map.unmodifiable(panelSizesNotifier.value);

  final ValueNotifier<bool> isDraggingTabNotifier = ValueNotifier<bool>(false);
  bool get isDraggingTab => isDraggingTabNotifier.value;
  set isDraggingTab(bool value) {
    if (isDraggingTabNotifier.value != value) {
      isDraggingTabNotifier.value = value;
      logger.logDebug('Tab dragging state changed: $value', _logTag);
    }
  }

  TabGroup? get activeGroup {
    if (activeGroupId == null) return null;
    try {
      return tabGroups.firstWhere((group) => group.id == activeGroupId);
    } catch (e) {
      return null;
    }
  }

  TabItem? get activeTab => activeGroup?.activeTab;

  bool get hasTabGroups => tabGroups.isNotEmpty;
  bool get hasActiveTabs => activeGroup?.hasActiveTabs ?? false;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  TabSystemViewModel() {
    logger.logInfo('Initializing TabSystemViewModel', _logTag);
    _setupAutoSave();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    logger.logInfo('Loading persisted tab system state', _logTag);
    
    try {
      final hasPersistedState = await _persistenceService.hasPersistedState();
      
      if (hasPersistedState) {
        final state = await _persistenceService.loadTabSystemState();
        
        if (state.tabGroups.isNotEmpty) {
          tabGroupsNotifier.value = state.tabGroups;
          activeGroupId = state.activeGroupId;
          panelSizesNotifier.value = state.panelSizes;
          layoutOrientation = state.layoutOrientation;
          
          logger.logInfo('Restored ${state.tabGroups.length} tab groups from persistence', _logTag);
        } else {
          _createDefaultGroup();
        }
      } else {
        _createDefaultGroup();
      }
    } catch (e) {
      logger.logError('Failed to load persisted state, creating default: $e', _logTag);
      _createDefaultGroup();
    }
    
    _isInitialized = true;
  }

  void _createDefaultGroup() {
    final defaultGroup = TabGroup(
      id: 'default',
      tabs: [],
    );
    tabGroupsNotifier.value = [defaultGroup];
    activeGroupId = defaultGroup.id;
  }

  void _setupAutoSave() {
    // Listen to tab groups changes
    tabGroupsNotifier.addListener(_saveState);
    panelSizesNotifier.addListener(_saveState);
    layoutOrientationNotifier.addListener(_saveState);
  }

  void _saveState() {
    if (!_isInitialized) return;
    
    // Debounce saves to avoid too frequent writes
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _persistenceService.saveTabSystemState(
          tabGroups: tabGroups,
          activeGroupId: activeGroupId,
          panelSizes: panelSizes.isNotEmpty ? panelSizes : null,
          layoutOrientation: layoutOrientation,
        );
      } catch (e) {
        logger.logError('Failed to save tab system state: $e', _logTag);
      }
    });
  }

  Timer? _saveDebouncer;

  void updatePanelSize(String groupId, double size) {
    final updatedSizes = Map<String, double>.from(panelSizes);
    updatedSizes[groupId] = size;
    panelSizesNotifier.value = updatedSizes;
  }

  void createTabGroup({
    String? groupId,
    TabGroupOrientation orientation = TabGroupOrientation.horizontal,
    double? flexSize,
  }) {
    final String id = groupId ?? 'group_${DateTime.now().millisecondsSinceEpoch}';
    
    if (tabGroups.any((group) => group.id == id)) {
      logger.logWarning('Tab group with id $id already exists', _logTag);
      return;
    }

    final newGroup = TabGroup(
      id: id,
      tabs: [],
      orientation: orientation,
      flexSize: flexSize,
    );

    final updatedGroups = List<TabGroup>.from(tabGroups);
    updatedGroups.add(newGroup);
    tabGroupsNotifier.value = updatedGroups;
    
    logger.logInfo('Created new tab group: $id', _logTag);
  }

  void createTerminalGroup() {
    final terminalGroupId = 'terminal_group';
    
    // Don't create if already exists
    if (tabGroups.any((group) => group.id == terminalGroupId)) {
      logger.logInfo('Terminal group already exists', _logTag);
      return;
    }

    // Switch to vertical layout for terminal
    layoutOrientation = TabSystemLayout.vertical;
    
    // Create terminal group with smaller flex size
    createTabGroup(
      groupId: terminalGroupId,
      flexSize: 0.3, // 30% of vertical space
    );

    logger.logInfo('Created terminal group and switched to vertical layout', _logTag);
  }

  void removeTabGroup(String groupId) {
    if (tabGroups.length <= 1) {
      logger.logWarning('Cannot remove the last tab group', _logTag);
      return;
    }

    final groupIndex = tabGroups.indexWhere((group) => group.id == groupId);
    if (groupIndex == -1) {
      logger.logWarning('Tab group $groupId not found', _logTag);
      return;
    }

    final updatedGroups = List<TabGroup>.from(tabGroups);
    updatedGroups.removeAt(groupIndex);
    tabGroupsNotifier.value = updatedGroups;

    // Remove panel size for this group
    final updatedSizes = Map<String, double>.from(panelSizes);
    updatedSizes.remove(groupId);
    panelSizesNotifier.value = updatedSizes;

    if (activeGroupId == groupId) {
      activeGroupId = updatedGroups.isNotEmpty ? updatedGroups.first.id : null;
    }

    // If only one group left, switch back to horizontal layout
    if (updatedGroups.length == 1) {
      layoutOrientation = TabSystemLayout.horizontal;
    }

    logger.logInfo('Removed tab group: $groupId', _logTag);
  }

  void toggleLayoutOrientation() {
    layoutOrientation = layoutOrientation == TabSystemLayout.horizontal 
        ? TabSystemLayout.vertical 
        : TabSystemLayout.horizontal;
    
    logger.logInfo('Toggled layout orientation to: $layoutOrientation', _logTag);
  }

  void handleDropZoneAction(String tabId, String sourceGroupId, String dropZonePosition) {
    final tab = getTab(tabId);
    if (tab == null) {
      logger.logWarning('Tab $tabId not found for drop zone action', _logTag);
      return;
    }

    switch (dropZonePosition) {
      case 'left':
        layoutOrientation = TabSystemLayout.horizontal;
        _createGroupAtPosition(tab, sourceGroupId, 0);
        break;
      case 'right':
        layoutOrientation = TabSystemLayout.horizontal;
        _createGroupAtPosition(tab, sourceGroupId, tabGroups.length);
        break;
      case 'bottom':
        layoutOrientation = TabSystemLayout.vertical;
        _createGroupAtPosition(tab, sourceGroupId, tabGroups.length);
        break;
      case 'center':
        // Add to existing active group - this is handled by existing logic
        break;
    }
  }

  void _createGroupAtPosition(TabItem tab, String sourceGroupId, int position) {
    // Remove tab from source group
    removeTab(tab.id, fromGroupId: sourceGroupId);
    
    // Create new group
    final newGroupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final newGroup = TabGroup(
      id: newGroupId,
      tabs: [tab],
      activeIndex: 0,
      flexSize: 1.0,
    );

    // Insert group at specified position
    final updatedGroups = List<TabGroup>.from(tabGroups);
    if (position >= updatedGroups.length) {
      updatedGroups.add(newGroup);
    } else {
      updatedGroups.insert(position, newGroup);
    }
    
    tabGroupsNotifier.value = updatedGroups;
    activeGroupId = newGroupId;

    logger.logInfo('Created new group $newGroupId at position $position with tab ${tab.id}', _logTag);
  }

  void addTab(TabItem tab, {String? targetGroupId, int? atIndex}) {
    final String groupId = targetGroupId ?? activeGroupId ?? tabGroups.first.id;
    final groupIndex = tabGroups.indexWhere((group) => group.id == groupId);
    
    if (groupIndex == -1) {
      logger.logWarning('Target group $groupId not found for adding tab', _logTag);
      return;
    }

    final updatedGroups = List<TabGroup>.from(tabGroups);
    final targetGroup = updatedGroups[groupIndex];
    final updatedGroup = targetGroup.addTab(tab, atIndex: atIndex);
    updatedGroups[groupIndex] = updatedGroup;
    
    tabGroupsNotifier.value = updatedGroups;
    activeGroupId = groupId;

    logger.logInfo('Added tab ${tab.id} to group $groupId at index ${atIndex ?? targetGroup.tabs.length}', _logTag);
  }

  void removeTab(String tabId, {String? fromGroupId}) {
    TabGroup? targetGroup;
    int groupIndex = -1;

    if (fromGroupId != null) {
      groupIndex = tabGroups.indexWhere((group) => group.id == fromGroupId);
      if (groupIndex != -1) {
        targetGroup = tabGroups[groupIndex];
      }
    } else {
      for (int i = 0; i < tabGroups.length; i++) {
        final group = tabGroups[i];
        if (group.tabs.any((tab) => tab.id == tabId)) {
          targetGroup = group;
          groupIndex = i;
          break;
        }
      }
    }

    if (targetGroup == null || groupIndex == -1) {
      logger.logWarning('Tab $tabId not found in any group', _logTag);
      return;
    }

    final updatedGroups = List<TabGroup>.from(tabGroups);
    final updatedGroup = targetGroup.removeTab(tabId);
    updatedGroups[groupIndex] = updatedGroup;
    
    tabGroupsNotifier.value = updatedGroups;

    logger.logInfo('Removed tab $tabId from group ${targetGroup.id}', _logTag);
  }

  void moveTab(String tabId, String fromGroupId, String toGroupId, {int? toIndex}) {
    if (fromGroupId == toGroupId) {
      _moveTabWithinGroup(tabId, fromGroupId, toIndex);
      return;
    }

    final fromGroupIndex = tabGroups.indexWhere((group) => group.id == fromGroupId);
    final toGroupIndex = tabGroups.indexWhere((group) => group.id == toGroupId);

    if (fromGroupIndex == -1 || toGroupIndex == -1) {
      logger.logWarning('Source or target group not found for moving tab $tabId', _logTag);
      return;
    }

    final fromGroup = tabGroups[fromGroupIndex];
    final tabIndex = fromGroup.tabs.indexWhere((tab) => tab.id == tabId);
    
    if (tabIndex == -1) {
      logger.logWarning('Tab $tabId not found in source group $fromGroupId', _logTag);
      return;
    }

    final tab = fromGroup.tabs[tabIndex];
    final updatedGroups = List<TabGroup>.from(tabGroups);

    updatedGroups[fromGroupIndex] = fromGroup.removeTab(tabId);
    updatedGroups[toGroupIndex] = updatedGroups[toGroupIndex].addTab(tab, atIndex: toIndex);

    tabGroupsNotifier.value = updatedGroups;
    activeGroupId = toGroupId;

    logger.logInfo('Moved tab $tabId from $fromGroupId to $toGroupId', _logTag);
  }

  void _moveTabWithinGroup(String tabId, String groupId, int? toIndex) {
    final groupIndex = tabGroups.indexWhere((group) => group.id == groupId);
    if (groupIndex == -1) return;

    final group = tabGroups[groupIndex];
    final fromIndex = group.tabs.indexWhere((tab) => tab.id == tabId);
    
    if (fromIndex == -1 || toIndex == null || fromIndex == toIndex) return;

    final updatedGroups = List<TabGroup>.from(tabGroups);
    updatedGroups[groupIndex] = group.moveTab(fromIndex, toIndex);
    tabGroupsNotifier.value = updatedGroups;

    logger.logInfo('Moved tab $tabId within group $groupId from $fromIndex to $toIndex', _logTag);
  }

  void setActiveTab(String tabId, {String? inGroupId}) {
    String? targetGroupId = inGroupId;
    
    if (targetGroupId == null) {
      for (final group in tabGroups) {
        if (group.tabs.any((tab) => tab.id == tabId)) {
          targetGroupId = group.id;
          break;
        }
      }
    }

    if (targetGroupId == null) {
      logger.logWarning('Tab $tabId not found in any group', _logTag);
      return;
    }

    final groupIndex = tabGroups.indexWhere((group) => group.id == targetGroupId);
    if (groupIndex == -1) return;

    final updatedGroups = List<TabGroup>.from(tabGroups);
    updatedGroups[groupIndex] = updatedGroups[groupIndex].setActiveTab(tabId);
    tabGroupsNotifier.value = updatedGroups;
    activeGroupId = targetGroupId;

    logger.logInfo('Set active tab to $tabId in group $targetGroupId', _logTag);
  }

  void setActiveTabIndex(int index, {String? inGroupId}) {
    final String groupId = inGroupId ?? activeGroupId ?? tabGroups.first.id;
    final groupIndex = tabGroups.indexWhere((group) => group.id == groupId);
    
    if (groupIndex == -1) return;

    final updatedGroups = List<TabGroup>.from(tabGroups);
    updatedGroups[groupIndex] = updatedGroups[groupIndex].setActiveIndex(index);
    tabGroupsNotifier.value = updatedGroups;
    activeGroupId = groupId;

    logger.logInfo('Set active tab index to $index in group $groupId', _logTag);
  }

  void updateTab(String tabId, TabItem updatedTab) {
    for (int groupIndex = 0; groupIndex < tabGroups.length; groupIndex++) {
      final group = tabGroups[groupIndex];
      final tabIndex = group.tabs.indexWhere((tab) => tab.id == tabId);
      
      if (tabIndex != -1) {
        final updatedGroups = List<TabGroup>.from(tabGroups);
        final updatedTabs = List<TabItem>.from(group.tabs);
        updatedTabs[tabIndex] = updatedTab;
        updatedGroups[groupIndex] = group.copyWith(tabs: updatedTabs);
        tabGroupsNotifier.value = updatedGroups;
        
        logger.logInfo('Updated tab $tabId', _logTag);
        return;
      }
    }

    logger.logWarning('Tab $tabId not found for update', _logTag);
  }

  TabItem? getTab(String tabId) {
    for (final group in tabGroups) {
      try {
        return group.tabs.firstWhere((tab) => tab.id == tabId);
      } catch (e) {
        continue;
      }
    }
    return null;
  }

  List<TabItem> getAllTabs() {
    final List<TabItem> allTabs = [];
    for (final group in tabGroups) {
      allTabs.addAll(group.tabs);
    }
    return allTabs;
  }

  void closeAllTabs({String? inGroupId}) {
    if (inGroupId != null) {
      final groupIndex = tabGroups.indexWhere((group) => group.id == inGroupId);
      if (groupIndex != -1) {
        final updatedGroups = List<TabGroup>.from(tabGroups);
        updatedGroups[groupIndex] = updatedGroups[groupIndex].copyWith(tabs: [], activeIndex: -1);
        tabGroupsNotifier.value = updatedGroups;
        logger.logInfo('Closed all tabs in group $inGroupId', _logTag);
      }
    } else {
      final updatedGroups = tabGroups.map((group) => 
        group.copyWith(tabs: [], activeIndex: -1)
      ).toList();
      tabGroupsNotifier.value = updatedGroups;
      logger.logInfo('Closed all tabs in all groups', _logTag);
    }
  }

  Future<void> clearPersistedState() async {
    await _persistenceService.clearTabSystemState();
    logger.logInfo('Cleared persisted tab system state', _logTag);
  }

  @override
  void dispose() {
    logger.logInfo('Disposing TabSystemViewModel', _logTag);
    _saveDebouncer?.cancel();
    
    tabGroupsNotifier.removeListener(_saveState);
    panelSizesNotifier.removeListener(_saveState);
    layoutOrientationNotifier.removeListener(_saveState);
    
    tabGroupsNotifier.dispose();
    activeGroupIdNotifier.dispose();
    panelSizesNotifier.dispose();
    layoutOrientationNotifier.dispose();
    isDraggingTabNotifier.dispose();
    super.dispose();
  }
} 