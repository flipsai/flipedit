import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';

import '../../models/tab_item.dart';
import '../../models/tab_group.dart';
import '../../viewmodels/tab_system_viewmodel.dart';

class TabBarWidget extends StatelessWidget with WatchItMixin {
  final TabGroup tabGroup;
  final Function(String tabId)? onTabSelected;
  final Function(String tabId)? onTabClosed;
  final Function(String tabId, int fromIndex, int toIndex)? onTabMoved;
  final Function(String tabId, String fromGroupId, String toGroupId, int? toIndex)? onTabMovedBetweenGroups;
  final Function()? onTabGroupClosed;
  final Function(String groupId)? onAddTab;

  const TabBarWidget({
    Key? key,
    required this.tabGroup,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabMoved,
    this.onTabMovedBetweenGroups,
    this.onTabGroupClosed,
    this.onAddTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return DragTarget<TabDragData>(
      onWillAccept: (data) => data != null,
      onAccept: (data) {
        if (data.sourceGroupId != tabGroup.id) {
          // Moving tab from another group to this group
          onTabMovedBetweenGroups?.call(
            data.tabId,
            data.sourceGroupId,
            tabGroup.id,
            tabGroup.tabs.length, // Add to end
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final bool isDropTarget = candidateData.isNotEmpty;
        
        return Container(
          height: 32,
          decoration: BoxDecoration(
            color: theme.inactiveBackgroundColor,
            border: Border(
              bottom: BorderSide(
                color: theme.resources.cardStrokeColorDefault,
                width: 1,
              ),
              top: isDropTarget ? BorderSide(
                color: theme.accentColor,
                width: 2,
              ) : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTabList(context, theme),
              ),
              _buildTabGroupActions(context, theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabList(BuildContext context, FluentThemeData theme) {
    if (tabGroup.tabs.isEmpty) {
      return DragTarget<TabDragData>(
        onWillAccept: (data) => data != null && data.sourceGroupId != tabGroup.id,
        onAccept: (data) {
          onTabMovedBetweenGroups?.call(
            data.tabId,
            data.sourceGroupId,
            tabGroup.id,
            0,
          );
        },
        builder: (context, candidateData, rejectedData) {
          final bool isDropTarget = candidateData.isNotEmpty;
          
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDropTarget 
                ? theme.accentColor.withOpacity(0.1) 
                : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isDropTarget 
                ? Border.all(color: theme.accentColor, width: 1)
                : null,
            ),
            child: Text(
              isDropTarget ? 'Drop tab here' : 'No tabs open',
              style: theme.typography.caption?.copyWith(
                color: isDropTarget ? theme.accentColor : theme.inactiveColor,
                fontWeight: isDropTarget ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          );
        },
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabGroup.tabs.asMap().entries.map((entry) {
            final index = entry.key;
            final tab = entry.value;
            final isActive = index == tabGroup.activeIndex;
            
            return _TabWidget(
              key: ValueKey('${tabGroup.id}_${tab.id}'),
              tab: tab,
              tabIndex: index,
              groupId: tabGroup.id,
              isActive: isActive,
              onTap: () => onTabSelected?.call(tab.id),
              onClose: tab.isClosable ? () => onTabClosed?.call(tab.id) : null,
              onTabMoved: onTabMoved,
              onTabMovedBetweenGroups: onTabMovedBetweenGroups,
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTabGroupActions(BuildContext context, FluentThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            FluentIcons.add,
            size: 14,
            color: theme.inactiveColor,
          ),
          onPressed: onAddTab != null ? () => onAddTab!(tabGroup.id) : null,
        ),
        if (onTabGroupClosed != null)
          IconButton(
            icon: Icon(
              FluentIcons.chrome_close,
              size: 12,
              color: theme.inactiveColor,
            ),
            onPressed: onTabGroupClosed,
          ),
      ],
    );
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

class _TabWidget extends StatefulWidget {
  final TabItem tab;
  final int tabIndex;
  final String groupId;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final Function(String tabId, int fromIndex, int toIndex)? onTabMoved;
  final Function(String tabId, String fromGroupId, String toGroupId, int? toIndex)? onTabMovedBetweenGroups;

  const _TabWidget({
    Key? key,
    required this.tab,
    required this.tabIndex,
    required this.groupId,
    required this.isActive,
    this.onTap,
    this.onClose,
    this.onTabMoved,
    this.onTabMovedBetweenGroups,
  }) : super(key: key);

  @override
  State<_TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends State<_TabWidget> {
  bool _isHovered = false;
  bool _isDragging = false;
  bool _isDragTarget = false;
  bool _dropOnRight = false; // Track if dropping on right side of tab
  double? _tabWidth;
  final GlobalKey _tabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Measure tab width after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTabWidth();
    });
  }

  void _measureTabWidth() {
    final RenderBox? renderBox = _tabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      setState(() {
        _tabWidth = renderBox.size.width;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final tabSystem = di<TabSystemViewModel>();
    
    final backgroundColor = _getBackgroundColor(theme);
    final textColor = _getTextColor(theme);
    final borderColor = widget.isActive ? theme.accentColor : Colors.transparent;

    return Draggable<TabDragData>(
      data: TabDragData(
        tabId: widget.tab.id,
        sourceIndex: widget.tabIndex,
        sourceGroupId: widget.groupId,
      ),
      feedback: _buildDragFeedback(context, theme),
      childWhenDragging: _buildPlaceholder(context, theme),
      onDragStarted: () {
        setState(() => _isDragging = true);
        tabSystem.isDraggingTab = true;
        _measureTabWidth(); // Ensure we have the current width before dragging
      },
      onDragEnd: (details) {
        setState(() => _isDragging = false);
        tabSystem.isDraggingTab = false;
      },
      child: DragTarget<TabDragData>(
        onWillAccept: (data) {
          if (data == null) return false;
          // Don't accept drops on self
          if (data.tabId == widget.tab.id) return false;
          return true;
        },
        onAccept: (data) {
          if (data.sourceGroupId == widget.groupId) {
            // Moving within same group
            int targetIndex = widget.tabIndex;
            if (_dropOnRight) {
              targetIndex += 1; // Insert after this tab
            }
            // Adjust for moving from earlier position to later position
            if (data.sourceIndex < targetIndex) {
              targetIndex -= 1;
            }
            if (data.sourceIndex != targetIndex) {
              widget.onTabMoved?.call(data.tabId, data.sourceIndex, targetIndex);
            }
          } else {
            // Moving between groups
            int targetIndex = widget.tabIndex;
            if (_dropOnRight) {
              targetIndex += 1; // Insert after this tab
            }
            widget.onTabMovedBetweenGroups?.call(
              data.tabId,
              data.sourceGroupId,
              widget.groupId,
              targetIndex,
            );
          }
          setState(() {
            _isDragTarget = false;
            _dropOnRight = false;
          });
        },
        onLeave: (data) {
          setState(() {
            _isDragTarget = false;
            _dropOnRight = false;
          });
        },
        onMove: (details) {
          setState(() {
            _isDragTarget = true;
            // Determine if dragging over left or right half of tab
            final RenderBox? renderBox = _tabKey.currentContext?.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final localPosition = renderBox.globalToLocal(details.offset);
              final tabWidth = renderBox.size.width;
              _dropOnRight = localPosition.dx > tabWidth / 2;
            }
          });
        },
        builder: (context, candidateData, rejectedData) {
          final bool isDropTarget = candidateData.isNotEmpty && 
              candidateData.first?.tabId != widget.tab.id;
          
          return Stack(
            children: [
              MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: GestureDetector(
                  onTap: widget.onTap,
                  onSecondaryTap: () => _showContextMenu(context),
                  child: Container(
                    key: _tabKey,
                    constraints: const BoxConstraints(
                      minWidth: 80,
                      maxWidth: 200,
                    ),
                    height: 32,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: borderColor,
                          width: 2,
                        ),
                        right: BorderSide(
                          color: theme.resources.cardStrokeColorDefault.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: _buildTabContent(context, theme, textColor),
                  ),
                ),
              ),
              // Insertion indicator
              if (isDropTarget)
                Positioned(
                  left: _dropOnRight ? null : 0,
                  right: _dropOnRight ? 0 : null,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: theme.accentColor,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, FluentThemeData theme, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.tab.icon != null) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: widget.tab.icon,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              widget.tab.title,
              style: theme.typography.body?.copyWith(
                color: textColor,
                fontSize: 12,
                fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.tab.isModified) ...[
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: theme.accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
          if (widget.onClose != null && (_isHovered || widget.isActive)) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: _isHovered ? theme.menuColor.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  FluentIcons.chrome_close,
                  size: 10,
                  color: textColor.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDragFeedback(BuildContext context, FluentThemeData theme) {
    return material.Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(
          minWidth: 80,
          maxWidth: 200,
        ),
        height: 32,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.accentColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _buildTabContent(context, theme, theme.typography.body?.color ?? Colors.black),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, FluentThemeData theme) {
    final double width = _tabWidth ?? 80.0; // Use measured width or default to 80
    
    return Container(
      width: width,
      height: 32,
      decoration: BoxDecoration(
        color: theme.inactiveBackgroundColor.withOpacity(0.3),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault.withOpacity(0.5),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Container(
          width: width * 0.5, // Scale the placeholder line based on tab width
          height: 2,
          decoration: BoxDecoration(
            color: theme.accentColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor(FluentThemeData theme) {
    if (_isDragging) {
      return theme.inactiveBackgroundColor.withOpacity(0.5);
    }
    if (widget.isActive) {
      return theme.cardColor;
    }
    if (_isHovered) {
      return theme.menuColor.withOpacity(0.05);
    }
    return theme.inactiveBackgroundColor;
  }

  Color _getTextColor(FluentThemeData theme) {
    if (widget.isActive) {
      return theme.typography.body?.color ?? Colors.black;
    }
    return theme.inactiveColor;
  }

  void _showContextMenu(BuildContext context) {
    // TODO: Implement context menu
    // This would show options like "Close", "Close Others", "Close All", etc.
  }
} 