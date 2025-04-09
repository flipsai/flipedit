import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:file_picker/file_picker.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';

// --- Action Handlers (Shared Logic) ---

void _handleNewProject() {
  print("Action: New Project");
}

void _handleOpenProject() {
  print("Action: Open Project");
}

Future<void> _handleImportMedia(EditorViewModel editorVm) async {
   try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        String? filePath = result.files.single.path;
        if (filePath != null) {
          editorVm.addVideo(filePath);
        } else {
          print("File path is null after picking.");
        }
      } else {
        print("File picking cancelled or no file selected.");
      }
    } catch (e) {
      print("Error picking file: $e");
    }
}

void _handleSaveProject(ProjectViewModel projectVm) {
  projectVm.saveProject();
  print("Action: Save Project");
}

void _handleUndo() {
  print("Action: Undo");
}

void _handleRedo() {
  print("Action: Redo");
}

void _handleToggleInspector(EditorViewModel editorVm) {
  editorVm.toggleInspector();
}

void _handleToggleTimeline(EditorViewModel editorVm) {
   editorVm.toggleTimeline();
}


// --- Widget for macOS / Windows ---
class PlatformAppMenuBar extends fluent.StatelessWidget {
  final bool isInspectorVisible;
  final bool isTimelineVisible;
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;
  final fluent.Widget child; // Main content goes here

  const PlatformAppMenuBar({
    super.key,
    required this.isInspectorVisible,
    required this.isTimelineVisible,
    required this.editorVm,
    required this.projectVm,
    required this.child,
  });

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Use material. prefix for PlatformMenuBar and its items
    return material.PlatformMenuBar(
       menus: [
            material.PlatformMenu(
              label: 'File',
              menus: [
                material.PlatformMenuItem(
                  label: 'New Project',
                  onSelected: _handleNewProject,
                ),
                material.PlatformMenuItem(
                  label: 'Open Project...',
                  onSelected: _handleOpenProject,
                ),
                material.PlatformMenuItem(
                  label: 'Import Media...',
                  onSelected: () => _handleImportMedia(editorVm),
                ),
                material.PlatformMenuItem(
                  label: 'Save Project',
                  onSelected: () => _handleSaveProject(projectVm),
                ),
              ],
            ),
            material.PlatformMenu(
              label: 'Edit',
              menus: [
                material.PlatformMenuItem(
                  label: 'Undo',
                  onSelected: _handleUndo
                ),
                material.PlatformMenuItem(
                  label: 'Redo',
                  onSelected: _handleRedo
                ),
              ],
            ),
            material.PlatformMenu(
              label: 'View',
              menus: [
                material.PlatformMenuItem(
                  label: isInspectorVisible ? '✓ Inspector' : '  Inspector',
                  onSelected: () => _handleToggleInspector(editorVm),
                ),
                material.PlatformMenuItem(
                  label: isTimelineVisible ? '✓ Timeline' : '  Timeline',
                  onSelected: () => _handleToggleTimeline(editorVm),
                ),
              ],
            ),
          ],
      child: child, // Pass the main content to the PlatformMenuBar
    );
  }
}


// --- Widget for Linux / Other ---
class FluentAppMenuBar extends fluent.StatelessWidget {
  final bool isInspectorVisible;
  final bool isTimelineVisible;
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;

  const FluentAppMenuBar({
    super.key,
    required this.isInspectorVisible,
    required this.isTimelineVisible,
    required this.editorVm,
    required this.projectVm,
  });

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Builds the Row of DropDownButtons
     return fluent.Row(
        mainAxisSize: fluent.MainAxisSize.min,
        children: [
          fluent.DropDownButton(
            title: const fluent.Text('File'),
            items: [
              fluent.MenuFlyoutItem(text: const fluent.Text('New Project'), onPressed: _handleNewProject),
              fluent.MenuFlyoutItem(text: const fluent.Text('Open Project...'), onPressed: _handleOpenProject),
              fluent.MenuFlyoutItem(text: const fluent.Text('Import Media...'), onPressed: () => _handleImportMedia(editorVm)),
              fluent.MenuFlyoutSeparator(),
              fluent.MenuFlyoutItem(text: const fluent.Text('Save Project'), onPressed: () => _handleSaveProject(projectVm)),
            ],
          ),
          const fluent.SizedBox(width: 8),
          fluent.DropDownButton(
            title: const fluent.Text('Edit'),
            items: [
               fluent.MenuFlyoutItem(text: const fluent.Text('Undo'), onPressed: _handleUndo),
               fluent.MenuFlyoutItem(text: const fluent.Text('Redo'), onPressed: _handleRedo),
            ]
          ),
          const fluent.SizedBox(width: 8),
          fluent.DropDownButton(
            title: const fluent.Text('View'),
            items: [
               fluent.MenuFlyoutItem(
                 leading: isInspectorVisible ? const fluent.Icon(fluent.FluentIcons.check_mark) : null,
                 text: const fluent.Text('Inspector'),
                 onPressed: () => _handleToggleInspector(editorVm),
               ),
               fluent.MenuFlyoutItem(
                 leading: isTimelineVisible ? const fluent.Icon(fluent.FluentIcons.check_mark) : null,
                 text: const fluent.Text('Timeline'),
                 onPressed: () => _handleToggleTimeline(editorVm),
               ),
            ]
          ),
        ]
      );
  }
} 