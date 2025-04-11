import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:uuid/uuid.dart';
import 'package:watch_it/watch_it.dart';

// --- Action Handlers (Shared Logic) ---

void _handleNewProject() {
  print("Action: New Project");
  // TODO: Implement new project logic
}

void _handleOpenProject() {
  print("Action: Open Project");
  // TODO: Implement open project logic
}

// Updated to use TimelineViewModel
Future<void> _handleImportMedia(TimelineViewModel timelineVm) async {
   try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video, // Or FileType.media for audio/images too
        allowMultiple: false, // Adjust if multiple imports are needed
      );
      if (result != null && result.files.isNotEmpty) {
        String? filePath = result.files.single.path;
        if (filePath != null) {
          // TODO: Get actual duration and potentially other metadata
          // For now, using placeholder values
          const uuid = Uuid();
          final newClip = Clip(
            id: uuid.v4(), 
            name: filePath.split(Platform.pathSeparator).last, // Use filename as name
            type: ClipType.video, // TODO: Detect type based on file extension
            filePath: filePath, 
            startFrame: timelineVm.currentFrame, // Add at current playhead position
            durationFrames: 150, // Placeholder: 5 seconds at 30fps
            trackIndex: 0, // Placeholder: Add to first video track
          );
          timelineVm.addClip(newClip);
        } else {
          print("File path is null after picking.");
        }
      } else {
        print("File picking cancelled or no file selected.");
      }
    } catch (e) {
      print("Error picking file: $e");
      // TODO: Show user-friendly error message
    }
}

void _handleSaveProject(ProjectViewModel projectVm) {
  projectVm.saveProject();
  print("Action: Save Project");
}

void _handleUndo() {
  print("Action: Undo");
  // TODO: Implement undo logic
}

void _handleRedo() {
  print("Action: Redo");
  // TODO: Implement redo logic
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
  final TimelineViewModel timelineVm; // Add TimelineViewModel
  final fluent.Widget child; 

  const PlatformAppMenuBar({
    super.key,
    required this.isInspectorVisible,
    required this.isTimelineVisible,
    required this.editorVm,
    required this.projectVm,
    required this.timelineVm, // Add timelineVm
    required this.child,
  });

  @override
  fluent.Widget build(fluent.BuildContext context) {
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
                  onSelected: () => _handleImportMedia(timelineVm), // Pass timelineVm
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
      child: child, 
    );
  }
}


// --- Widget for Linux / Other ---
class FluentAppMenuBar extends fluent.StatelessWidget {
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;
  final TimelineViewModel timelineVm; 

  const FluentAppMenuBar({
    super.key,
    required this.editorVm,
    required this.projectVm,
    required this.timelineVm, 
  });

  @override
  fluent.Widget build(fluent.BuildContext context) {
     return fluent.Row(
        mainAxisSize: fluent.MainAxisSize.min,
        children: [
          fluent.DropDownButton(
            title: const fluent.Text('File'),
            items: [
              fluent.MenuFlyoutItem(text: const fluent.Text('New Project'), onPressed: _handleNewProject),
              fluent.MenuFlyoutItem(text: const fluent.Text('Open Project...'), onPressed: _handleOpenProject),
              fluent.MenuFlyoutItem(text: const fluent.Text('Import Media...'), onPressed: () => _handleImportMedia(timelineVm)),
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
          ValueListenableBuilder<bool>(
            valueListenable: editorVm.isInspectorVisibleNotifier,
            builder: (context, isInspectorVisible, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: editorVm.isTimelineVisibleNotifier,
                builder: (context, isTimelineVisible, _) {
                  return fluent.DropDownButton(
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
                  );
                },
              );
            },
          ),
        ]
      );
  }
}

// Removed duplicate AppMenuBar class 