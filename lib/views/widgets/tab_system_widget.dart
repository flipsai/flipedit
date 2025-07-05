import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

import '../../models/tab_line.dart';
import '../../models/tab_group.dart';
import '../../viewmodels/tab_system_viewmodel.dart';
import 'tab_bar_widget.dart';
import 'tab_line_widget.dart';
import 'resizable_split_widget.dart';
import 'tab_drop_zone_overlay.dart';

class TabSystemWidget extends StatefulWidget {
  final Function(String tabId)? onTabSelected;
  final Function(String tabId)? onTabClosed;

  const TabSystemWidget({
    super.key,
    this.onTabSelected,
    this.onTabClosed,
  });

  @override
  State<TabSystemWidget> createState() => _TabSystemWidgetState();
}

class _TabSystemWidgetState extends State<TabSystemWidget> {
  DropZonePosition? _hoveredZone;

  @override
  Widget build(BuildContext context) {
    final tabSystem = di<TabSystemViewModel>();
    
    return ListenableBuilder(
      listenable: Listenable.merge([
        tabSystem.tabLinesNotifier,
        tabSystem.activeLineIdNotifier,
        tabSystem.activeGroupIdNotifier,
        tabSystem.isDraggingTabNotifier,
      ]),
      builder: (context, child) {
        final tabLines = tabSystem.tabLines;
        final isDraggingTab = tabSystem.isDraggingTab;

        Widget content;
        
        if (tabLines.isEmpty) {
          content = _buildEmptyState(context);
        } else if (tabLines.length == 1 && tabLines.first.tabColumns.length == 1) {
          content = _buildSingleGroup(context, tabLines.first.tabColumns.first, tabSystem);
        } else {
          content = _buildMultipleLines(context, tabLines, tabSystem);
        }

        return Stack(
          children: [
            content,
            // Drop zone overlay (if needed for legacy compatibility)
            if (isDraggingTab)
              TabDropZoneOverlay(
                isVisible: isDraggingTab,
                layoutOrientation: tabSystem.layoutOrientation,
                hoveredZone: _hoveredZone,
                onDropZoneHovered: (position) {
                  setState(() {
                    _hoveredZone = position;
                  });
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.document,
            size: 64,
            color: theme.inactiveColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No tabs open',
            style: theme.typography.title?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new tab to get started',
            style: theme.typography.body?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleGroup(BuildContext context, TabGroup group, TabSystemViewModel tabSystem) {
    return Column(
      children: [
        TabBarWidget(
          tabGroup: group,
          onTabSelected: (tabId) {
            tabSystem.setActiveTab(tabId);
            widget.onTabSelected?.call(tabId);
          },
          onTabClosed: (tabId) {
            tabSystem.removeTab(tabId);
            widget.onTabClosed?.call(tabId);
          },
          onTabMoved: (tabId, fromIndex, toIndex) {
            _handleTabMoveWithinGroup(tabSystem, tabId, group.id, fromIndex, toIndex);
          },
          onTabMovedBetweenGroups: (tabId, fromGroupId, toGroupId, toIndex) {
            _handleTabMoveBetweenGroups(tabSystem, tabId, fromGroupId, toGroupId, toIndex);
          },
          onAddTab: (groupId) => _handleAddTab(tabSystem, groupId),
        ),
        Expanded(
          child: _buildTabContent(context, group),
        ),
      ],
    );
  }

  Widget _buildMultipleLines(
    BuildContext context,
    List<TabLine> tabLines,
    TabSystemViewModel tabSystem,
  ) {
    if (tabLines.length == 1) {
      // Single line - no dividers needed
      return TabLineWidget(
        tabLine: tabLines.first,
        isLast: true,
        onTabSelected: widget.onTabSelected,
        onTabClosed: widget.onTabClosed,
      );
    }
    
    // Multiple lines - use resizable split widget with vertical axis
    return ResizableSplitWidget(
      axis: Axis.vertical,
      children: tabLines.asMap().entries.map((entry) {
        final index = entry.key;
        final tabLine = entry.value;
        final isLast = index == tabLines.length - 1;
        
        return ResizableSplitItem(
          child: TabLineWidget(
            tabLine: tabLine,
            isLast: isLast,
            onTabSelected: widget.onTabSelected,
            onTabClosed: widget.onTabClosed,
          ),
          initialWeight: tabSystem.lineSizes[tabLine.id] ?? 1.0,
        );
      }).toList(),
      onWeightsChanged: (weights) {
        // Save line sizes when they change
        final lineIds = tabLines.map((line) => line.id).toList();
        tabSystem.updateLineSizes(lineIds, weights);
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

  void _handleTabMoveWithinGroup(
    TabSystemViewModel tabSystem,
    String tabId,
    String groupId,
    int fromIndex,
    int toIndex,
  ) {
    // Find the group and update it
    for (final line in tabSystem.tabLines) {
      for (final group in line.tabColumns) {
        if (group.id == groupId) {
          final updatedGroup = group.moveTab(fromIndex, toIndex);
          final updatedLine = line.updateColumn(groupId, updatedGroup);
          tabSystem.updateTabLine(line.id, updatedLine);
          return;
        }
      }
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
} 