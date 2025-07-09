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

// --- Widget for Linux / Other ---
class AppMenuBar extends StatefulWidget {
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;
  final TimelineViewModel timelineVm;

  const AppMenuBar({
    super.key,
    required this.editorVm,
    required this.projectVm,
    required this.timelineVm,
  });

  @override
  State<AppMenuBar> createState() => _AppMenuBarState();
}

class _AppMenuBarState extends State<AppMenuBar> {
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
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: widget.projectVm.isProjectLoadedNotifier,
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
            valueListenable: widget.projectVm.isProjectLoadedNotifier,
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
      ),
    );
  }
}
