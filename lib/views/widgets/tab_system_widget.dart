import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

import '../../models/tab_item.dart';
import '../../models/tab_group.dart';
import '../../viewmodels/tab_system_viewmodel.dart';
import '../../services/tab_content_factory.dart';
import 'tab_bar_widget.dart';
import 'resizable_split_widget.dart';
import 'tab_drop_zone_overlay.dart';

class TabSystemWidget extends StatefulWidget {
  final Function(String tabId)? onTabSelected;
  final Function(String tabId)? onTabClosed;

  const TabSystemWidget({
    Key? key,
    this.onTabSelected,
    this.onTabClosed,
  }) : super(key: key);

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
        tabSystem.tabGroupsNotifier,
        tabSystem.activeGroupIdNotifier,
        tabSystem.layoutOrientationNotifier,
        tabSystem.isDraggingTabNotifier,
      ]),
      builder: (context, child) {
        final tabGroups = tabSystem.tabGroups;
        final activeGroupId = tabSystem.activeGroupId;
        final layoutOrientation = tabSystem.layoutOrientation;
        final isDraggingTab = tabSystem.isDraggingTab;

        Widget content;
        
        if (tabGroups.isEmpty) {
          content = _buildEmptyState(context);
        } else if (tabGroups.length == 1) {
          content = _buildSingleGroup(context, tabGroups.first, tabSystem);
        } else {
          content = _buildMultipleGroups(context, tabGroups, activeGroupId, layoutOrientation, tabSystem);
        }

        return Stack(
          children: [
            content,
            // Drop zone overlay
            TabDropZoneOverlay(
              isVisible: isDraggingTab,
              layoutOrientation: layoutOrientation,
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
            color: theme.inactiveColor.withOpacity(0.5),
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

  Widget _buildMultipleGroups(
    BuildContext context,
    List<TabGroup> tabGroups,
    String? activeGroupId,
    TabSystemLayout layoutOrientation,
    TabSystemViewModel tabSystem,
  ) {
    // Determine split axis based on layout orientation
    final Axis splitAxis = layoutOrientation == TabSystemLayout.vertical 
        ? Axis.vertical 
        : Axis.horizontal;

    return ResizableSplitWidget(
      axis: splitAxis,
      children: tabGroups.map((group) {
        final isActive = group.id == activeGroupId;
        
        return ResizableSplitItem(
          initialWeight: group.flexSize ?? 1.0,
          minSize: group.minSize,
          maxSize: group.maxSize,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isActive 
                  ? FluentTheme.of(context).accentColor.withOpacity(0.3)
                  : Colors.transparent,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                TabBarWidget(
                  tabGroup: group,
                  onTabSelected: (tabId) {
                    tabSystem.setActiveTab(tabId, inGroupId: group.id);
                    widget.onTabSelected?.call(tabId);
                  },
                  onTabClosed: (tabId) {
                    tabSystem.removeTab(tabId, fromGroupId: group.id);
                    widget.onTabClosed?.call(tabId);
                  },
                  onTabMoved: (tabId, fromIndex, toIndex) {
                    _handleTabMoveWithinGroup(tabSystem, tabId, group.id, fromIndex, toIndex);
                  },
                  onTabMovedBetweenGroups: (tabId, fromGroupId, toGroupId, toIndex) {
                    _handleTabMoveBetweenGroups(tabSystem, tabId, fromGroupId, toGroupId, toIndex);
                  },
                  onTabGroupClosed: tabGroups.length > 1 
                    ? () => tabSystem.removeTabGroup(group.id)
                    : null,
                  onAddTab: (groupId) => _handleAddTab(tabSystem, groupId),
                ),
                Expanded(
                  child: _buildTabContent(context, group),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleTabMoveWithinGroup(
    TabSystemViewModel tabSystem,
    String tabId,
    String groupId,
    int fromIndex,
    int toIndex,
  ) {
    // Get the group
    final groupIndex = tabSystem.tabGroups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = tabSystem.tabGroups[groupIndex];
    
    // Validate indices
    if (fromIndex < 0 || fromIndex >= group.tabs.length ||
        toIndex < 0 || toIndex >= group.tabs.length ||
        fromIndex == toIndex) {
      return;
    }

    // Find the tab
    final tab = group.tabs[fromIndex];
    if (tab.id != tabId) return;

    // Create new tab list with moved tab
    final newTabs = List<TabItem>.from(group.tabs);
    newTabs.removeAt(fromIndex);
    newTabs.insert(toIndex, tab);

    // Update active index
    int newActiveIndex = group.activeIndex;
    if (fromIndex == group.activeIndex) {
      newActiveIndex = toIndex;
    } else if (fromIndex < group.activeIndex && toIndex >= group.activeIndex) {
      newActiveIndex = group.activeIndex - 1;
    } else if (fromIndex > group.activeIndex && toIndex <= group.activeIndex) {
      newActiveIndex = group.activeIndex + 1;
    }

    // Update the group
    final updatedGroups = List<TabGroup>.from(tabSystem.tabGroups);
    updatedGroups[groupIndex] = group.copyWith(
      tabs: newTabs,
      activeIndex: newActiveIndex,
    );
    
    tabSystem.tabGroupsNotifier.value = updatedGroups;
  }

  void _handleTabMoveBetweenGroups(
    TabSystemViewModel tabSystem,
    String tabId,
    String fromGroupId,
    String toGroupId,
    int? toIndex,
  ) {
    final fromGroupIndex = tabSystem.tabGroups.indexWhere((g) => g.id == fromGroupId);
    final toGroupIndex = tabSystem.tabGroups.indexWhere((g) => g.id == toGroupId);
    
    if (fromGroupIndex == -1 || toGroupIndex == -1) return;

    final fromGroup = tabSystem.tabGroups[fromGroupIndex];
    final toGroup = tabSystem.tabGroups[toGroupIndex];
    
    // Find the tab in the source group
    final tabIndex = fromGroup.tabs.indexWhere((tab) => tab.id == tabId);
    if (tabIndex == -1) return;
    
    final tab = fromGroup.tabs[tabIndex];
    
    // Remove from source group
    final newFromTabs = List<TabItem>.from(fromGroup.tabs);
    newFromTabs.removeAt(tabIndex);
    
    // Update source group active index
    int newFromActiveIndex = fromGroup.activeIndex;
    if (tabIndex == fromGroup.activeIndex) {
      if (newFromTabs.isEmpty) {
        newFromActiveIndex = -1;
      } else if (tabIndex >= newFromTabs.length) {
        newFromActiveIndex = newFromTabs.length - 1;
      }
    } else if (tabIndex < fromGroup.activeIndex) {
      newFromActiveIndex = fromGroup.activeIndex - 1;
    }
    
    // Add to target group
    final newToTabs = List<TabItem>.from(toGroup.tabs);
    final insertIndex = toIndex ?? newToTabs.length;
    newToTabs.insert(insertIndex, tab);
    
    // Update target group active index
    int newToActiveIndex = toGroup.activeIndex;
    if (insertIndex <= toGroup.activeIndex && toGroup.tabs.isNotEmpty) {
      newToActiveIndex = toGroup.activeIndex + 1;
    } else if (toGroup.tabs.isEmpty) {
      newToActiveIndex = 0;
    }
    
    // Update both groups
    final updatedGroups = List<TabGroup>.from(tabSystem.tabGroups);
    updatedGroups[fromGroupIndex] = fromGroup.copyWith(
      tabs: newFromTabs,
      activeIndex: newFromActiveIndex,
    );
    updatedGroups[toGroupIndex] = toGroup.copyWith(
      tabs: newToTabs,
      activeIndex: newToActiveIndex,
    );
    
    tabSystem.tabGroupsNotifier.value = updatedGroups;
    tabSystem.activeGroupId = toGroupId;
  }

  void _handleAddTab(TabSystemViewModel tabSystem, String groupId) {
    // Determine what type of tab to create based on the group and existing tabs
    final group = tabSystem.tabGroups.firstWhere((g) => g.id == groupId);
    final existingTabIds = group.tabs.map((t) => t.id).toSet();
    
    TabItem tab;
    
    // Check if this is the terminal group (for timeline tabs)
    if (groupId == 'terminal_group') {
      // Create timeline-related tabs for terminal group
      if (!existingTabIds.contains('timeline')) {
        tab = TabContentFactory.createAudioTab(
          id: 'timeline',
          title: 'Timeline',
          isModified: false,
        );
      } else {
        // Create additional terminal tab
        final String id = 'terminal_${DateTime.now().millisecondsSinceEpoch}';
        tab = TabContentFactory.createTerminalTab(
          id: id,
          title: 'Terminal ${DateTime.now().millisecond}',
          isModified: false,
        );
      }
    } else {
      // For main groups, prioritize creating missing editor panels
      if (!existingTabIds.contains('preview')) {
        tab = TabContentFactory.createVideoTab(
          id: 'preview',
          title: 'Preview',
          isModified: false,
        );
      } else if (!existingTabIds.contains('inspector')) {
        tab = TabContentFactory.createDocumentTab(
          id: 'inspector',
          title: 'Inspector',
          isModified: false,
        );
      } else {
        // Create additional editor-related tabs
        final String id = 'document_${DateTime.now().millisecondsSinceEpoch}';
        tab = TabContentFactory.createDocumentTab(
          id: id,
          title: 'Document ${DateTime.now().millisecond}',
          isModified: false,
        );
      }
    }

    tabSystem.addTab(tab, targetGroupId: groupId);
  }

  Widget _buildTabContent(BuildContext context, TabGroup group) {
    if (group.isEmpty || !group.hasActiveTabs) {
      return _buildEmptyGroupContent(context);
    }

    final activeTab = group.activeTab!;
    
    return Container(
      key: ValueKey(activeTab.id),
      child: activeTab.content,
    );
  }

  Widget _buildEmptyGroupContent(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.add_to_shopping_list,
            size: 32,
            color: theme.inactiveColor.withOpacity(0.5),
          ),
          const SizedBox(height: 8),
          Text(
            'No active tab',
            style: theme.typography.body?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
} 