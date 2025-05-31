import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

import '../../models/tab_line.dart';
import '../../models/tab_group.dart';
import '../../viewmodels/tab_system_viewmodel.dart';
import 'tab_bar_widget.dart';
import 'resizable_split_widget.dart';

class TabLineWidget extends StatefulWidget {
  final TabLine tabLine;
  final bool isLast;
  final Function(String tabId)? onTabSelected;
  final Function(String tabId)? onTabClosed;

  const TabLineWidget({
    super.key,
    required this.tabLine,
    this.isLast = false,
    this.onTabSelected,
    this.onTabClosed,
  });

  @override
  State<TabLineWidget> createState() => _TabLineWidgetState();
}

class _TabLineWidgetState extends State<TabLineWidget> {
  @override
  Widget build(BuildContext context) {
    final tabSystem = di<TabSystemViewModel>();
    
    return Column(
      children: [
        Expanded(
          child: _buildColumnsWithDividers(context, tabSystem),
        ),
        
        // Bottom drag target for new tab line (only show when dragging)
        if (widget.isLast) _buildLineDragTarget(context),
      ],
    );
  }

  Widget _buildColumnsWithDividers(BuildContext context, TabSystemViewModel tabSystem) {
    if (widget.tabLine.tabColumns.isEmpty) {
      return Container();
    }
    
    if (widget.tabLine.tabColumns.length == 1) {
      // Single column - no dividers needed
      return _buildTabColumn(context, widget.tabLine.tabColumns.first, tabSystem);
    }
    
    // Multiple columns - use resizable split widget
    return ResizableSplitWidget(
      axis: Axis.horizontal,
      children: widget.tabLine.tabColumns.map((column) {
        return ResizableSplitItem(
          child: _buildTabColumn(context, column, tabSystem),
          initialWeight: tabSystem.panelSizes[column.id] ?? 1.0,
        );
      }).toList(),
      onWeightsChanged: (weights) {
        // Save column sizes when they change
        final columnIds = widget.tabLine.tabColumns.map((col) => col.id).toList();
        tabSystem.updateColumnSizes(widget.tabLine.id, columnIds, weights);
      },
    );
  }

  Widget _buildTabColumn(BuildContext context, TabGroup column, TabSystemViewModel tabSystem) {
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (details) {
        return details.data.sourceGroupId != column.id;
      },
      onAcceptWithDetails: (details) {
        _handleCreateNewColumn(tabSystem, details.data, 'center', column.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        
        return Container(
          decoration: BoxDecoration(
            border: isHovering
              ? Border.all(color: FluentTheme.of(context).accentColor, width: 2)
              : null,
          ),
          child: Column(
            children: [
              TabBarWidget(
                tabGroup: column,
                onTabSelected: (tabId) {
                  tabSystem.setActiveTab(tabId);
                  widget.onTabSelected?.call(tabId);
                },
                onTabClosed: (tabId) {
                  tabSystem.removeTab(tabId);
                  widget.onTabClosed?.call(tabId);
                },
                onTabMoved: (tabId, fromIndex, toIndex) {
                  _handleTabMoveWithinGroup(tabSystem, tabId, column.id, fromIndex, toIndex);
                },
                onTabMovedBetweenGroups: (tabId, fromGroupId, toGroupId, toIndex) {
                  _handleTabMoveBetweenGroups(tabSystem, tabId, fromGroupId, toGroupId, toIndex);
                },
                onTabGroupClosed: widget.tabLine.tabColumns.length > 1 
                  ? () => tabSystem.removeTabGroup(column.id)
                  : null,
                onAddTab: (groupId) => _handleAddTab(tabSystem, groupId),
              ),
              Expanded(
                child: _buildTabContent(context, column),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabContent(BuildContext context, TabGroup group) {
    if (group.isEmpty || !group.hasActiveTabs) {
      return Container(
        alignment: Alignment.center,
        child: Text(
          'No active tab',
          style: FluentTheme.of(context).typography.body?.copyWith(
            color: FluentTheme.of(context).inactiveColor,
          ),
        ),
      );
    }
    
    return group.activeTab!.content;
  }

  Widget _buildLineDragTarget(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tabSystem = di<TabSystemViewModel>();
    
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        _handleCreateNewLine(tabSystem, details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        
        if (!isHovering) {
          // When not hovering, show minimal space
          return const SizedBox(height: 8);
        }
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.accentColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.accentColor, width: 2),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  FluentIcons.add,
                  size: 14,
                  color: theme.accentColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'Drop here to create new tab line',
                  style: theme.typography.caption?.copyWith(
                    color: theme.accentColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleTabMoveWithinGroup(
    TabSystemViewModel tabSystem,
    String tabId,
    String groupId,
    int fromIndex,
    int toIndex,
  ) {
    // Find the group and update it
    TabGroup? targetGroup;
    TabLine? targetLine;
    
    for (final line in tabSystem.tabLines) {
      for (final group in line.tabColumns) {
        if (group.id == groupId) {
          targetGroup = group;
          targetLine = line;
          break;
        }
      }
      if (targetGroup != null) break;
    }
    
    if (targetGroup != null && targetLine != null) {
      final updatedGroup = targetGroup.moveTab(fromIndex, toIndex);
      final updatedLine = targetLine.updateColumn(groupId, updatedGroup);
      tabSystem.updateTabLine(targetLine.id, updatedLine);
    }
  }

  void _handleTabMoveBetweenGroups(
    TabSystemViewModel tabSystem,
    String tabId,
    String fromGroupId,
    String toGroupId,
    int? toIndex,
  ) {
    final tab = tabSystem.getTab(tabId);
    if (tab == null) return;
    
    // Remove from source group (this will automatically clean up empty groups)
    tabSystem.removeTab(tabId);
    
    // Add to target group
    tabSystem.addTab(tab, targetGroupId: toGroupId, atIndex: toIndex);
  }

  void _handleAddTab(TabSystemViewModel tabSystem, String groupId) {
    // This would typically open a dialog or create a default tab
    // For now, we'll just activate the group
    tabSystem.activeGroupId = groupId;
  }

  void _handleCreateNewColumn(
    TabSystemViewModel tabSystem,
    TabDragData data,
    String position,
    String nearColumnId,
  ) {
    final tab = tabSystem.getTab(data.tabId);
    if (tab == null) return;
    
    // Remove tab from source (this will automatically clean up empty groups)
    tabSystem.removeTab(data.tabId);
    
    // Find the line containing the near column
    TabLine? targetLine;
    int columnIndex = -1;
    
    for (final line in tabSystem.tabLines) {
      for (int i = 0; i < line.tabColumns.length; i++) {
        if (line.tabColumns[i].id == nearColumnId) {
          targetLine = line;
          columnIndex = i;
          break;
        }
      }
      if (targetLine != null) break;
    }
    
    if (targetLine == null || columnIndex == -1) return;
    
    // Create new group with the tab
    final newGroupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final newGroup = TabGroup(
      id: newGroupId,
      tabs: [tab],
    );
    
    // Insert the new column after the target column
    final insertIndex = columnIndex + 1;
    final updatedLine = targetLine.addColumn(newGroup, atIndex: insertIndex);
    tabSystem.updateTabLine(targetLine.id, updatedLine);
    
    tabSystem.activeGroupId = newGroupId;
  }

  void _handleCreateNewLine(TabSystemViewModel tabSystem, TabDragData data) {
    final tab = tabSystem.getTab(data.tabId);
    if (tab == null) return;
    
    // Remove tab from source (this will automatically clean up empty groups)
    tabSystem.removeTab(data.tabId);
    
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
    
    // Add the new line at the end
    final updatedLines = List<TabLine>.from(tabSystem.tabLines);
    updatedLines.add(newLine);
    tabSystem.tabLinesNotifier.value = updatedLines;
    
    tabSystem.activeLineId = newLineId;
    tabSystem.activeGroupId = newGroupId;
  }
}

class TabDragData {
  final String tabId;
  final int sourceIndex;
  final String sourceGroupId;

  const TabDragData({
    required this.tabId,
    required this.sourceIndex,
    required this.sourceGroupId,
  });
} 