import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';

import '../../models/tab_item.dart';
import '../../models/tab_group.dart';
import '../../viewmodels/tab_system_viewmodel.dart';
import '../../viewmodels/project_viewmodel.dart';
import '../../viewmodels/timeline_viewmodel.dart';
import '../../services/tab_content_factory.dart';

class TabBarWidget extends StatelessWidget with WatchItMixin {
  final TabGroup tabGroup;
  final Function(String tabId)? onTabSelected;
  final Function(String tabId)? onTabClosed;
  final Function(String tabId, int fromIndex, int toIndex)? onTabMoved;
  final Function(String tabId, String fromGroupId, String toGroupId, int? toIndex)? onTabMovedBetweenGroups;
  final Function()? onTabGroupClosed;
  final Function(String groupId)? onAddTab;
  final bool isPrimary;

  const TabBarWidget({
    super.key,
    required this.tabGroup,
    this.onTabSelected,
    this.onTabClosed,
    this.onTabMoved,
    this.onTabMovedBetweenGroups,
    this.onTabGroupClosed,
    this.onAddTab,
    this.isPrimary = false,
  });

  Future<void> _handleNewProject(BuildContext context) async {
    await di<ProjectViewModel>().createNewProjectWithDialog(context);
  }

  Future<void> _handleOpenProject(BuildContext context) async {
    await di<ProjectViewModel>().openProjectDialog(context);
  }

  Future<void> _handleImportMedia(BuildContext context) async {
    await di<ProjectViewModel>().importMediaWithUI(context);
  }

  Future<void> _handleUndo() async {
    await di<TimelineViewModel>().undo();
  }

  Future<void> _handleRedo() async {
    await di<TimelineViewModel>().redo();
  }

  void _handleAddVideoTrack() {
    di<ProjectViewModel>().addTrackCommand(type: 'video');
  }

  void _handleAddAudioTrack() {
    di<ProjectViewModel>().addTrackCommand(type: 'audio');
  }

  void _handleNewTab() {
    // Create a new tab in the tab system
    final tabSystem = di<TabSystemViewModel>();

    // Check what essential tabs are missing across all groups
    final allTabs = tabSystem.getAllTabs();
    final existingTabIds = allTabs.map((t) => t.id).toSet();

    TabItem newTab;

    if (!existingTabIds.contains('preview')) {
      newTab = TabContentFactory.createVideoTab(
        id: 'preview',
        title: 'Preview',
        isModified: false,
      );
    } else if (!existingTabIds.contains('inspector')) {
      newTab = TabContentFactory.createDocumentTab(
        id: 'inspector',
        title: 'Inspector',
        isModified: false,
      );
    } else if (!existingTabIds.contains('timeline')) {
      newTab = TabContentFactory.createAudioTab(
        id: 'timeline',
        title: 'Timeline',
        isModified: false,
      );
    } else {
      // Create additional document tab if all essential tabs exist
      newTab = TabContentFactory.createDocumentTab(
        id: 'document_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Document ${DateTime.now().millisecond}',
        isModified: false,
      );
    }

    tabSystem.addTab(newTab);
  }

  void _handleOpenPreview() {
    final tabSystem = di<TabSystemViewModel>();

    // Check if preview tab already exists
    final existingTab = tabSystem.getTab('preview');
    if (existingTab != null) {
      // If it exists, just activate it
      tabSystem.setActiveTab('preview');
      return;
    }

    // Create new preview tab
    final previewTab = TabContentFactory.createVideoTab(
      id: 'preview',
      title: 'Preview',
      isModified: false,
    );

    tabSystem.addTab(previewTab);
  }

  void _handleOpenInspector() {
    final tabSystem = di<TabSystemViewModel>();

    // Check if inspector tab already exists
    final existingTab = tabSystem.getTab('inspector');
    if (existingTab != null) {
      // If it exists, just activate it
      tabSystem.setActiveTab('inspector');
      return;
    }

    // Create new inspector tab
    final inspectorTab = TabContentFactory.createDocumentTab(
      id: 'inspector',
      title: 'Inspector',
      isModified: false,
    );

    tabSystem.addTab(inspectorTab);
  }

  void _handleOpenTimeline() {
    final tabSystem = di<TabSystemViewModel>();

    // Check if timeline tab already exists
    final existingTab = tabSystem.getTab('timeline');
    if (existingTab != null) {
      // If it exists, just activate it
      tabSystem.setActiveTab('timeline');
      return;
    }

    // Create new timeline tab
    final timelineTab = TabContentFactory.createAudioTab(
      id: 'timeline',
      title: 'Timeline',
      isModified: false,
    );

    // Try to add to terminal group if it exists, otherwise active group
    final terminalGroup =
        tabSystem.tabGroups.where((group) => group.id == 'terminal_group').firstOrNull;
    if (terminalGroup != null) {
      tabSystem.addTab(timelineTab, targetGroupId: terminalGroup.id);
    } else {
      tabSystem.addTab(timelineTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    
    return DragTarget<TabDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data.sourceGroupId != tabGroup.id) {
          return true;
        }
        return false;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
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
            color: theme.colorScheme.background,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.border,
                width: 1,
              ),
              top: isDropTarget ? BorderSide(
                color: theme.colorScheme.primary,
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

  Widget _buildTabList(BuildContext context, ShadThemeData theme) {
    if (tabGroup.tabs.isEmpty) {
      return DragTarget<TabDragData>(
        onWillAcceptWithDetails: (details) {
          final data = details.data;
          if (data.sourceGroupId != tabGroup.id) {
            return true;
          }
          return false;
        },
        onAcceptWithDetails: (details) {
          final data = details.data;
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
                ? theme.colorScheme.primary.withValues(alpha: 0.1) 
                : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: isDropTarget 
                ? Border.all(color: theme.colorScheme.primary, width: 1)
                : null,
            ),
            child: Text(
              isDropTarget ? 'Drop tab here' : 'No tabs open',
              style: TextStyle(
                color: isDropTarget ? theme.colorScheme.primary : theme.colorScheme.mutedForeground,
                fontWeight: isDropTarget ? FontWeight.w500 : FontWeight.normal,
                fontSize: 12,
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

  Widget _buildTabGroupActions(BuildContext context, ShadThemeData theme) {
    final projectVm = di<ProjectViewModel>();
    final timelineVm = di<TimelineViewModel>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPrimary) ...[
          ValueListenableBuilder<bool>(
            valueListenable: projectVm.isProjectLoadedNotifier,
            builder: (context, isProjectLoaded, _) {
              return PopupMenuButton<String>(
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('File'),
                ),
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'new_project',
                    child: Text('New Project'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'open_project',
                    child: Text('Open Project...'),
                  ),
                  PopupMenuItem<String>(
                    value: 'import_media',
                    enabled: isProjectLoaded,
                    child: const Text('Import Media...'),
                  ),
                ],
                onSelected: (String value) {
                  switch (value) {
                    case 'new_project':
                      _handleNewProject(context);
                      break;
                    case 'open_project':
                      _handleOpenProject(context);
                      break;
                    case 'import_media':
                      _handleImportMedia(context);
                      break;
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Edit'),
            ),
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'undo',
                child: Text('Undo'),
              ),
              const PopupMenuItem<String>(
                value: 'redo',
                child: Text('Redo'),
              ),
            ],
            onSelected: (String value) {
              switch (value) {
                case 'undo':
                  _handleUndo();
                  break;
                case 'redo':
                  _handleRedo();
                  break;
              }
            },
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: projectVm.isProjectLoadedNotifier,
            builder: (context, isProjectLoaded, _) {
              return PopupMenuButton<String>(
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Track'),
                ),
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'add_video_track',
                    enabled: isProjectLoaded,
                    child: const Text('Add Video Track'),
                  ),
                  PopupMenuItem<String>(
                    value: 'add_audio_track',
                    enabled: isProjectLoaded,
                    child: const Text('Add Audio Track'),
                  ),
                ],
                onSelected: (String value) {
                  switch (value) {
                    case 'add_video_track':
                      _handleAddVideoTrack();
                      break;
                    case 'add_audio_track':
                      _handleAddAudioTrack();
                      break;
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('View'),
            ),
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'new_tab',
                child: Text('New Tab'),
              ),
              const PopupMenuItem<String>(
                value: 'open_preview',
                child: Text('Open Preview'),
              ),
              const PopupMenuItem<String>(
                value: 'open_inspector',
                child: Text('Open Inspector'),
              ),
              const PopupMenuItem<String>(
                value: 'open_timeline',
                child: Text('Open Timeline'),
              ),
            ],
            onSelected: (String value) {
              switch (value) {
                case 'new_tab':
                  _handleNewTab();
                  break;
                case 'open_preview':
                  _handleOpenPreview();
                  break;
                case 'open_inspector':
                  _handleOpenInspector();
                  break;
                case 'open_timeline':
                  _handleOpenTimeline();
                  break;
              }
            },
          ),
        ],
        IconButton(
          icon: Icon(
            LucideIcons.plus,
            size: 14,
            color: theme.colorScheme.mutedForeground,
          ),
          onPressed: onAddTab != null ? () => onAddTab!(tabGroup.id) : null,
        ),
        if (onTabGroupClosed != null)
          IconButton(
            icon: Icon(
              LucideIcons.x,
              size: 12,
              color: theme.colorScheme.mutedForeground,
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
    super.key,
    required this.tab,
    required this.tabIndex,
    required this.groupId,
    required this.isActive,
    this.onTap,
    this.onClose,
    this.onTabMoved,
    this.onTabMovedBetweenGroups,
  });

  @override
  State<_TabWidget> createState() => _TabWidgetState();
}

class _TabWidgetState extends State<_TabWidget> {
  bool _isHovered = false;
  bool _isDragging = false;
  bool _dropOnRight = false;
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
    final theme = ShadTheme.of(context);
    final tabSystem = di<TabSystemViewModel>();
    
    final backgroundColor = _getBackgroundColor(theme);
    final textColor = _getTextColor(theme);
    final borderColor = widget.isActive ? theme.colorScheme.primary : Colors.transparent;

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
        onWillAcceptWithDetails: (details) {
          final data = details.data;
          // Don't accept drops on self
          if (data.tabId == widget.tab.id) return false; 
          return true;
        },
        onAcceptWithDetails: (details) {
          final data = details.data;
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
            _dropOnRight = false;
          });
        },
        onLeave: (data) {
          setState(() {
            _dropOnRight = false;
          });
        },
        onMove: (details) {
          setState(() {
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
                          color: theme.colorScheme.border.withValues(alpha: 0.3),
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
                      color: theme.colorScheme.primary,
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

  Widget _buildTabContent(BuildContext context, ShadThemeData theme, Color textColor) {
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
              style: TextStyle(
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
                color: theme.colorScheme.primary,
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
                  color: _isHovered ? theme.colorScheme.muted.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(
                  LucideIcons.x,
                  size: 10,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDragFeedback(BuildContext context, ShadThemeData theme) {
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
          color: theme.colorScheme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _buildTabContent(context, theme, theme.colorScheme.foreground),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, ShadThemeData theme) {
    final double width = _tabWidth ?? 80.0; // Use measured width or default to 80
    
    return Container(
      width: width,
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.background.withValues(alpha: 0.3),
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Container(
          width: width * 0.5, // Scale the placeholder line based on tab width
          height: 2,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor(ShadThemeData theme) {
    if (_isDragging) {
      return theme.colorScheme.background.withValues(alpha: 0.5);
    }
    if (widget.isActive) {
      return theme.colorScheme.card;
    }
    if (_isHovered) {
      return theme.colorScheme.muted.withValues(alpha: 0.05);
    }
    return theme.colorScheme.background;
  }

  Color _getTextColor(ShadThemeData theme) {
    if (widget.isActive) {
      return theme.colorScheme.foreground;
    }
    return theme.colorScheme.mutedForeground;
  }

  void _showContextMenu(BuildContext context) {
    // TODO: Implement context menu
    // This would show options like "Close", "Close Others", "Close All", etc.
  }
} 