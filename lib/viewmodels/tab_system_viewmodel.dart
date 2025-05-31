import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/tab_item.dart';
import '../models/tab_group.dart';
import '../models/tab_line.dart';
import '../services/tab_system_persistence_service.dart';
import '../utils/logger.dart' as logger;

enum TabSystemLayout { horizontal, vertical }

class TabSystemViewModel extends ChangeNotifier {
  final String _logTag = 'TabSystemViewModel';
  final TabSystemPersistenceService _persistenceService = TabSystemPersistenceService.instance;

  final ValueNotifier<List<TabLine>> tabLinesNotifier = 
      ValueNotifier<List<TabLine>>([]);
  List<TabLine> get tabLines => List.unmodifiable(tabLinesNotifier.value);

  final ValueNotifier<String?> activeLineIdNotifier = ValueNotifier<String?>(null);
  String? get activeLineId => activeLineIdNotifier.value;
  set activeLineId(String? value) {
    if (activeLineIdNotifier.value != value) {
      logger.logInfo('Active tab line changed: ${activeLineIdNotifier.value} -> $value', _logTag);
      activeLineIdNotifier.value = value;
      _saveState();
    }
  }

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

  final ValueNotifier<Map<String, double>> lineSizesNotifier = 
      ValueNotifier<Map<String, double>>({});
  Map<String, double> get lineSizes => Map.unmodifiable(lineSizesNotifier.value);

  final ValueNotifier<bool> isDraggingTabNotifier = ValueNotifier<bool>(false);
  bool get isDraggingTab => isDraggingTabNotifier.value;
  set isDraggingTab(bool value) {
    if (isDraggingTabNotifier.value != value) {
      isDraggingTabNotifier.value = value;
      logger.logDebug('Tab dragging state changed: $value', _logTag);
    }
  }

  // Legacy compatibility methods
  ValueNotifier<List<TabGroup>> get tabGroupsNotifier {
    // Create a synthetic notifier that updates when tabLines change
    final groupsNotifier = ValueNotifier<List<TabGroup>>(tabGroups);
    
    // Listen to tabLines changes and update the groups notifier
    tabLinesNotifier.addListener(() {
      groupsNotifier.value = tabGroups;
    });
    
    return groupsNotifier;
  }

  List<TabGroup> get tabGroups {
    final List<TabGroup> allGroups = [];
    for (final line in tabLines) {
      allGroups.addAll(line.tabColumns);
    }
    return allGroups;
  }

  TabLine? get activeLine {
    if (activeLineId == null) return null;
    try {
      return tabLines.firstWhere((line) => line.id == activeLineId);
    } catch (e) {
      return null;
    }
  }

  TabGroup? get activeGroup {
    if (activeGroupId == null) return null;
    for (final line in tabLines) {
      try {
        return line.tabColumns.firstWhere((group) => group.id == activeGroupId);
      } catch (e) {
        continue;
      }
    }
    return null;
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
          // Convert legacy TabGroup list to TabLine structure
          _convertLegacyStateToTabLines(state);
          
          logger.logInfo('Restored ${state.tabGroups.length} tab groups from persistence', _logTag);
        } else {
          _createDefaultTabLine();
        }
      } else {
        _createDefaultTabLine();
      }
    } catch (e) {
      logger.logError('Failed to load persisted state, creating default: $e', _logTag);
      _createDefaultTabLine();
    }
    
    _isInitialized = true;
  }

  void _convertLegacyStateToTabLines(TabSystemState state) {
    if (state.tabLines.isNotEmpty) {
      // Use the new TabLine format
      tabLinesNotifier.value = state.tabLines;
      activeLineId = state.activeLineId;
    } else if (state.tabGroups.isNotEmpty) {
      // Convert legacy TabGroup list to TabLine structure
      final defaultLine = TabLine(
        id: 'default_line',
        tabColumns: state.tabGroups,
      );
      
      tabLinesNotifier.value = [defaultLine];
      activeLineId = defaultLine.id;
    }
    
    activeGroupId = state.activeGroupId;
    panelSizesNotifier.value = state.panelSizes;
    lineSizesNotifier.value = state.lineSizes;
    layoutOrientation = state.layoutOrientation;
  }

  void _createDefaultTabLine() {
    final defaultGroup = TabGroup(
      id: 'default',
      tabs: [],
    );
    final defaultLine = TabLine(
      id: 'default_line',
      tabColumns: [defaultGroup],
    );
    
    tabLinesNotifier.value = [defaultLine];
    activeLineId = defaultLine.id;
    activeGroupId = defaultGroup.id;
  }

  void _setupAutoSave() {
    tabLinesNotifier.addListener(_saveState);
    panelSizesNotifier.addListener(_saveState);
    lineSizesNotifier.addListener(_saveState);
    layoutOrientationNotifier.addListener(_saveState);
  }

  void _saveState() {
    if (!_isInitialized) return;
    
    _saveDebouncer?.cancel();
    _saveDebouncer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _persistenceService.saveTabSystemState(
          tabLines: tabLines, // Save the new hierarchical structure
          activeLineId: activeLineId,
          activeGroupId: activeGroupId,
          panelSizes: panelSizes.isNotEmpty ? panelSizes : null,
          lineSizes: lineSizes.isNotEmpty ? lineSizes : null,
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

  void updateLineSize(String lineId, double size) {
    final updatedSizes = Map<String, double>.from(lineSizes);
    updatedSizes[lineId] = size;
    lineSizesNotifier.value = updatedSizes;
  }

  void updateLineSizes(List<String> lineIds, List<double> weights) {
    final updatedSizes = Map<String, double>.from(lineSizes);
    for (int i = 0; i < lineIds.length && i < weights.length; i++) {
      updatedSizes[lineIds[i]] = weights[i];
    }
    lineSizesNotifier.value = updatedSizes;
  }

  void updateColumnSizes(String lineId, List<String> columnIds, List<double> weights) {
    final updatedSizes = Map<String, double>.from(panelSizes);
    for (int i = 0; i < columnIds.length && i < weights.length; i++) {
      updatedSizes[columnIds[i]] = weights[i];
    }
    panelSizesNotifier.value = updatedSizes;
  }

  void createTabLine({String? lineId, double? flexSize}) {
    final String id = lineId ?? 'line_${DateTime.now().millisecondsSinceEpoch}';
    
    if (tabLines.any((line) => line.id == id)) {
      logger.logWarning('Tab line with id $id already exists', _logTag);
      return;
    }

    final defaultGroup = TabGroup(
      id: '${id}_group_0',
      tabs: [],
    );

    final newLine = TabLine(
      id: id,
      tabColumns: [defaultGroup],
      flexSize: flexSize,
    );

    final updatedLines = List<TabLine>.from(tabLines);
    updatedLines.add(newLine);
    tabLinesNotifier.value = updatedLines;
    
    logger.logInfo('Created new tab line: $id', _logTag);
  }

  void createTabGroup({
    String? groupId,
    TabGroupOrientation orientation = TabGroupOrientation.horizontal,
    double? flexSize,
    String? targetLineId,
    int? atColumnIndex,
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

    // Find target line or use active line
    TabLine? targetLine;
    if (targetLineId != null) {
      try {
        targetLine = tabLines.firstWhere((line) => line.id == targetLineId);
      } catch (e) {
        targetLine = activeLine;
      }
    } else {
      targetLine = activeLine;
    }
    
    if (targetLine == null) {
      logger.logWarning('No active line available to add tab group', _logTag);
      return;
    }

    final updatedLine = targetLine.addColumn(newGroup, atIndex: atColumnIndex);
    updateTabLine(targetLine.id, updatedLine);
    
    logger.logInfo('Created new tab group: $id in line: ${targetLine.id}', _logTag);
  }

  void createTerminalGroup() {
    final terminalGroupId = 'terminal_group';
    
    if (tabGroups.any((group) => group.id == terminalGroupId)) {
      logger.logInfo('Terminal group already exists', _logTag);
      return;
    }

    // Create a new tab line for terminal
    createTabLine(lineId: 'terminal_line', flexSize: 0.3);
    
    // Get the terminal line and add the terminal group
    final terminalLine = tabLines.firstWhere((line) => line.id == 'terminal_line');
    final terminalGroup = TabGroup(
      id: terminalGroupId,
      tabs: [],
    );
    
    final updatedLine = terminalLine.updateColumn(terminalLine.tabColumns.first.id, terminalGroup);
    updateTabLine(terminalLine.id, updatedLine);

    logger.logInfo('Created terminal group in new line', _logTag);
  }

  void removeTabGroup(String groupId) {
    TabLine? targetLine;
    
    // Find the line containing this group
    for (final line in tabLines) {
      if (line.tabColumns.any((group) => group.id == groupId)) {
        targetLine = line;
        break;
      }
    }
    
    if (targetLine == null) {
      logger.logWarning('Tab group $groupId not found', _logTag);
      return;
    }

    final updatedLine = targetLine.removeColumn(groupId);
    
    // If line becomes empty, remove the line
    if (updatedLine.isEmpty) {
      _removeTabLine(targetLine.id);
    } else {
      updateTabLine(targetLine.id, updatedLine);
    }

    final updatedSizes = Map<String, double>.from(panelSizes);
    updatedSizes.remove(groupId);
    panelSizesNotifier.value = updatedSizes;

    if (activeGroupId == groupId) {
      activeGroupId = tabGroups.isNotEmpty ? tabGroups.first.id : null;
    }

    logger.logInfo('Removed tab group: $groupId', _logTag);
  }

  void updateTabLine(String lineId, TabLine updatedLine) {
    final lineIndex = tabLines.indexWhere((line) => line.id == lineId);
    if (lineIndex == -1) return;

    final updatedLines = List<TabLine>.from(tabLines);
    updatedLines[lineIndex] = updatedLine;
    tabLinesNotifier.value = updatedLines;
  }

  void _removeTabLine(String lineId) {
    if (tabLines.length <= 1) {
      // If this is the last line, clear it and create a new default line
      logger.logInfo('Removing last tab line, creating new default line', _logTag);
      _createDefaultTabLine();
      return;
    }

    final updatedLines = tabLines.where((line) => line.id != lineId).toList();
    tabLinesNotifier.value = updatedLines;

    if (activeLineId == lineId) {
      activeLineId = updatedLines.isNotEmpty ? updatedLines.first.id : null;
    }
    
    logger.logInfo('Removed tab line: $lineId', _logTag);
  }

  void toggleLayoutOrientation() {
    layoutOrientation = layoutOrientation == TabSystemLayout.horizontal 
        ? TabSystemLayout.vertical 
        : TabSystemLayout.horizontal;
    
    logger.logInfo('Toggled layout orientation to: $layoutOrientation', _logTag);
  }

  // Legacy compatibility methods
  void addTab(TabItem tab, {String? targetGroupId, String? targetLineId, int? atIndex}) {
    String groupId = targetGroupId ?? activeGroupId ?? '';
    
    if (groupId.isEmpty) {
      _createDefaultTabLine();
      groupId = activeGroupId!;
    }

    TabGroup? targetGroup = activeGroup;
    TabLine? targetLine;
    
    if (targetGroupId != null) {
      for (final line in tabLines) {
        for (final group in line.tabColumns) {
          if (group.id == targetGroupId) {
            targetGroup = group;
            targetLine = line;
        break;
          }
        }
        if (targetGroup != null) break;
    }
    } else {
      targetLine = activeLine;
      targetGroup = activeGroup;
    }

    if (targetGroup == null || targetLine == null) {
      logger.logWarning('Cannot add tab: no valid target group', _logTag);
      return;
    }

    final updatedGroup = targetGroup.addTab(tab, atIndex: atIndex);
    final updatedLine = targetLine.updateColumn(targetGroup.id, updatedGroup);
    updateTabLine(targetLine.id, updatedLine);

    activeGroupId = targetGroup.id;
    activeLineId = targetLine.id;

    logger.logInfo('Added tab ${tab.id} to group ${targetGroup.id}', _logTag);
  }

  void removeTab(String tabId, {String? fromGroupId}) {
    TabGroup? sourceGroup;
    TabLine? sourceLine;
    
    // Find the group containing this tab
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        if (group.tabs.any((tab) => tab.id == tabId)) {
          sourceGroup = group;
          sourceLine = line;
          break;
        }
      }
      if (sourceGroup != null) break;
    }

    if (sourceGroup == null || sourceLine == null) {
      logger.logWarning('Tab $tabId not found', _logTag);
      return;
    }

    final updatedGroup = sourceGroup.removeTab(tabId);
    
    // Check if the group is now empty
    if (updatedGroup.isEmpty) {
      // Remove the empty group instead of updating it
      final updatedLine = sourceLine.removeColumn(sourceGroup.id);
      
      // Check if the line is now empty
      if (updatedLine.isEmpty) {
        // Remove the empty line
        _removeTabLine(sourceLine.id);
      } else {
        // Update the line without the empty group
        updateTabLine(sourceLine.id, updatedLine);
      }
      
      // Update active states if needed
      if (activeGroupId == sourceGroup.id) {
        // Set active group to the first available group
        activeGroupId = tabGroups.isNotEmpty ? tabGroups.first.id : null;
        
        // Set active line to the line containing the new active group
        if (activeGroupId != null) {
          for (final line in tabLines) {
            if (line.tabColumns.any((group) => group.id == activeGroupId)) {
              activeLineId = line.id;
              break;
            }
          }
        } else {
          activeLineId = null;
        }
      }
      
      logger.logInfo('Removed tab $tabId and empty group ${sourceGroup.id}', _logTag);
    } else {
      // Update the group with the removed tab
      final updatedLine = sourceLine.updateColumn(sourceGroup.id, updatedGroup);
      updateTabLine(sourceLine.id, updatedLine);

      logger.logInfo('Removed tab $tabId from group ${sourceGroup.id}', _logTag);
    }
  }

  void setActiveTab(String tabId, {String? inGroupId}) {
    TabGroup? targetGroup;
    TabLine? targetLine;
    
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        if (group.tabs.any((tab) => tab.id == tabId)) {
          targetGroup = group;
          targetLine = line;
          break;
        }
      }
      if (targetGroup != null) break;
    }

    if (targetGroup == null || targetLine == null) {
      logger.logWarning('Tab $tabId not found', _logTag);
      return;
    }

    final updatedGroup = targetGroup.setActiveTab(tabId);
    final updatedLine = targetLine.updateColumn(targetGroup.id, updatedGroup);
    updateTabLine(targetLine.id, updatedLine);
    
    activeGroupId = targetGroup.id;
    activeLineId = targetLine.id;
  }

  List<TabItem> getAllTabs() {
    final List<TabItem> allTabs = [];
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        allTabs.addAll(group.tabs);
      }
    }
    return allTabs;
  }

  TabItem? getTab(String tabId) {
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        for (final tab in group.tabs) {
          if (tab.id == tabId) {
            return tab;
          }
        }
      }
    }
    return null;
  }

  void closeAllTabs() {
    tabLinesNotifier.value = [];
    activeLineId = null;
    activeGroupId = null;
    _createDefaultTabLine();
  }

  void handleDropZoneAction(String tabId, String sourceGroupId, String dropZonePosition) {
    final tab = getTab(tabId);
    if (tab == null) {
      logger.logWarning('Tab $tabId not found for drop zone action', _logTag);
      return;
    }

    switch (dropZonePosition) {
      case 'left':
        _createGroupAtPosition(tab, sourceGroupId, 'left');
        break;
      case 'right':
        _createGroupAtPosition(tab, sourceGroupId, 'right');
        break;
      case 'bottom':
        _createLineAtPosition(tab, sourceGroupId, 'bottom');
        break;
      case 'center':
        break;
    }
  }

  void _createGroupAtPosition(TabItem tab, String sourceGroupId, String position) {
    // Find source group and line
    TabGroup? sourceGroup;
    TabLine? sourceLine;
    
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        if (group.id == sourceGroupId) {
          sourceGroup = group;
          sourceLine = line;
          break;
        }
      }
      if (sourceGroup != null) break;
    }
    
    if (sourceGroup == null || sourceLine == null) return;

    // Remove tab from source
    final updatedSourceGroup = sourceGroup.removeTab(tab.id);
    
    // Create new group with the tab
    final newGroupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final newGroup = TabGroup(
      id: newGroupId,
      tabs: [tab],
    );

    // Add new group to the line
    final sourceIndex = sourceLine.tabColumns.indexWhere((g) => g.id == sourceGroupId);
    final insertIndex = position == 'left' ? sourceIndex : sourceIndex + 1;
    
    var updatedLine = sourceLine.updateColumn(sourceGroupId, updatedSourceGroup);
    updatedLine = updatedLine.addColumn(newGroup, atIndex: insertIndex);
    
    updateTabLine(sourceLine.id, updatedLine);
    activeGroupId = newGroupId;
  }

  void _createLineAtPosition(TabItem tab, String sourceGroupId, String position) {
    // Find source group and line
    TabGroup? sourceGroup;
    TabLine? sourceLine;
    
    for (final line in tabLines) {
      for (final group in line.tabColumns) {
        if (group.id == sourceGroupId) {
          sourceGroup = group;
          sourceLine = line;
          break;
      }
      }
      if (sourceGroup != null) break;
    }
    
    if (sourceGroup == null || sourceLine == null) return;

    // Now we know both are non-null, so we can use them safely
    final nonNullSourceGroup = sourceGroup;
    final nonNullSourceLine = sourceLine;

    // Remove tab from source
    final updatedSourceGroup = nonNullSourceGroup.removeTab(tab.id);
    final updatedSourceLine = nonNullSourceLine.updateColumn(sourceGroupId, updatedSourceGroup);
    
    // Create new line with new group containing the tab
    final newLineId = 'line_${DateTime.now().millisecondsSinceEpoch}';
    final newGroupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final newGroup = TabGroup(
      id: newGroupId,
      tabs: [tab],
    );
    final newLine = TabLine(
      id: newLineId,
      tabColumns: [newGroup],
    );

    // Add new line
    final sourceLineIndex = tabLines.indexWhere((l) => l.id == nonNullSourceLine.id);
    if (sourceLineIndex == -1) return; // Line not found
    final insertIndex = position == 'bottom' ? sourceLineIndex + 1 : sourceLineIndex;
    
    final updatedLines = List<TabLine>.from(tabLines);
    updatedLines[sourceLineIndex] = updatedSourceLine;
    updatedLines.insert(insertIndex, newLine);
    
    tabLinesNotifier.value = updatedLines;
    activeLineId = newLineId;
    activeGroupId = newGroupId;
  }

  Future<void> clearPersistedState() async {
    try {
    await _persistenceService.clearTabSystemState();
    logger.logInfo('Cleared persisted tab system state', _logTag);
    } catch (e) {
      logger.logError('Failed to clear persisted state: $e', _logTag);
    }
  }

  @override
  void dispose() {
    _saveDebouncer?.cancel();
    tabLinesNotifier.dispose();
    activeLineIdNotifier.dispose();
    activeGroupIdNotifier.dispose();
    layoutOrientationNotifier.dispose();
    panelSizesNotifier.dispose();
    lineSizesNotifier.dispose();
    isDraggingTabNotifier.dispose();
    super.dispose();
  }
} 