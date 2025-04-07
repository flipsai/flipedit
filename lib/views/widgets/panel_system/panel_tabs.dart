import 'package:flutter/material.dart';
import 'panel_models.dart';

class TabItem {
  final String id;
  final String title;
  final IconData? icon;
  final Widget content;
  final bool closable;
  
  TabItem({
    String? id,
    required this.title,
    this.icon,
    required this.content,
    this.closable = true,
  }) : id = id ?? title.toLowerCase().replaceAll(' ', '_');
}

class PanelTabs extends StatefulWidget {
  final List<TabItem> tabs;
  final int selectedIndex;
  final Function(int)? onTabSelected;
  final Function(TabItem)? onTabClosed;
  final Function(TabItem, DropPosition)? onTabDragged;
  final Color backgroundColor;
  final Color activeTabColor;
  final Color inactiveTabColor;
  final Color textColor;
  
  const PanelTabs({
    Key? key,
    required this.tabs,
    this.selectedIndex = 0,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabDragged,
    this.backgroundColor = const Color(0xFFE7E7E7),
    this.activeTabColor = Colors.white,
    this.inactiveTabColor = const Color(0xFFEBEBEB),
    this.textColor = Colors.black87,
  }) : super(key: key);
  
  @override
  State<PanelTabs> createState() => _PanelTabsState();
}

class _PanelTabsState extends State<PanelTabs> {
  // Tab drag state
  bool _isDragging = false;
  int? _draggingIndex;
  
  @override
  Widget build(BuildContext context) {
    if (widget.tabs.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        // Tab bar
        _buildTabBar(),
        
        // Tab content
        Expanded(
          child: widget.tabs.isNotEmpty
              ? widget.tabs[widget.selectedIndex < widget.tabs.length 
                  ? widget.selectedIndex : 0].content
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
  
  Widget _buildTabBar() {
    return Container(
      height: 34,
      color: widget.backgroundColor,
      child: Row(
        children: [
          // Scrollable tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.tabs.length,
              itemBuilder: (context, index) {
                return _buildTab(index);
              },
            ),
          ),
          
          // Actions (could add buttons for new tabs, etc.)
        ],
      ),
    );
  }
  
  Widget _buildTab(int index) {
    final tab = widget.tabs[index];
    final isActive = index == widget.selectedIndex;
    
    return Draggable<TabItem>(
      data: tab,
      feedback: Material(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: widget.activeTabColor,
          child: Text(
            tab.title,
            style: TextStyle(
              color: widget.textColor,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
      child: DragTarget<TabItem>(
        onWillAccept: (data) => data != null && data.id != tab.id,
        onAccept: (data) {
          // Handle tab reordering or merging
          if (widget.onTabDragged != null) {
            // Determine drop position (center for tab reordering)
            widget.onTabDragged!(data, DropPosition.center);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return InkWell(
            onTap: () {
              if (widget.onTabSelected != null) {
                widget.onTabSelected!(index);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? widget.activeTabColor : widget.inactiveTabColor,
                border: Border(
                  top: BorderSide(
                    color: isActive ? Colors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.icon != null) ...[
                      Icon(tab.icon, size: 16, color: widget.textColor),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      tab.title,
                      style: TextStyle(
                        color: widget.textColor,
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    if (tab.closable) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          if (widget.onTabClosed != null) {
                            widget.onTabClosed!(tab);
                          }
                        },
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: widget.textColor.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
