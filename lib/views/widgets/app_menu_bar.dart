import 'package:flutter/material.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/tab_system_viewmodel.dart';
import 'package:flipedit/services/tab_content_factory.dart';
import 'package:flipedit/models/tab_item.dart';
import 'package:watch_it/watch_it.dart';

// --- Widget for macOS / Windows ---
class PlatformAppMenuBar extends StatefulWidget {
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;
  final TimelineViewModel timelineVm;
  final Widget child;

  const PlatformAppMenuBar({
    super.key,
    required this.editorVm,
    required this.projectVm,
    required this.timelineVm,
    required this.child,
  });

  @override
  State<PlatformAppMenuBar> createState() => _PlatformAppMenuBarState();
}

class _PlatformAppMenuBarState extends State<PlatformAppMenuBar> {
  Future<void> _handleNewProject(BuildContext context) async {
    await widget.projectVm.createNewProjectWithDialog(context);
  }

  Future<void> _handleOpenProject(BuildContext context) async {
    await widget.projectVm.openProjectDialog(context);
  }

  Future<void> _handleImportMedia(BuildContext context) async {
    await widget.projectVm.importMediaWithUI(context);
  }

  Future<void> _handleUndo() async {
    await widget.timelineVm.undo();
  }

  Future<void> _handleRedo() async {
    await widget.timelineVm.redo();
  }

  void _handleAddVideoTrack() {
    widget.projectVm.addTrackCommand(type: 'video');
  }

  void _handleAddAudioTrack() {
    widget.projectVm.addTrackCommand(type: 'audio');
  }

  void _handleNewTab() {
    // Create a new tab in the tab system
    final tabSystem = GetIt.I<TabSystemViewModel>();
    
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
    final tabSystem = GetIt.I<TabSystemViewModel>();
    
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
    final tabSystem = GetIt.I<TabSystemViewModel>();
    
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
    final tabSystem = GetIt.I<TabSystemViewModel>();
    
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
    final terminalGroup = tabSystem.tabGroups.where((group) => group.id == 'terminal_group').firstOrNull;
    if (terminalGroup != null) {
      tabSystem.addTab(timelineTab, targetGroupId: terminalGroup.id);
    } else {
      tabSystem.addTab(timelineTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.projectVm.isProjectLoadedNotifier,
      builder: (context, isProjectLoaded, _) {
        return PlatformMenuBar(
          menus: [
            PlatformMenu(
              label: 'File',
              menus: [
                PlatformMenuItem(
                  label: 'New Project',
                  onSelected: () => _handleNewProject(context),
                ),
                PlatformMenuItem(
                  label: 'Open Project...',
                  onSelected: () => _handleOpenProject(context),
                ),
                PlatformMenuItem(
                  label: 'Import Media...',
                  onSelected:
                      isProjectLoaded
                          ? () => _handleImportMedia(context)
                          : null,
                ),
              ],
            ),
            PlatformMenu(
              label: 'Edit',
              menus: [
                PlatformMenuItem(
                  label: 'Undo',
                  onSelected: () => _handleUndo(),
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  onSelected: () => _handleRedo(),
                ),
              ],
            ),
            PlatformMenu(
              label: 'Track',
              menus: [
                PlatformMenuItem(
                  label: 'Add Video Track',
                  onSelected:
                      isProjectLoaded ? () => _handleAddVideoTrack() : null,
                ),
                PlatformMenuItem(
                  label: 'Add Audio Track',
                  onSelected:
                      isProjectLoaded ? () => _handleAddAudioTrack() : null,
                ),
              ],
            ),
            PlatformMenu(
              label: 'View',
              menus: [
                PlatformMenuItem(
                  label: 'New Tab',
                  onSelected: () => _handleNewTab(),
                ),
                PlatformMenuItem(
                  label: 'Open Preview',
                  onSelected: () => _handleOpenPreview(),
                ),
                PlatformMenuItem(
                  label: 'Open Inspector',
                  onSelected: () => _handleOpenInspector(),
                ),
                PlatformMenuItem(
                  label: 'Open Timeline',
                  onSelected: () => _handleOpenTimeline(),
                ),
              ],
            ),
          ],
          child: widget.child,
        );
      },
    );
  }
}
