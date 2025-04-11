import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:uuid/uuid.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/project_service.dart';

// --- Action Handlers (Shared Logic) ---

// Updated to accept BuildContext and use ProjectService
Future<void> _handleNewProject(fluent.BuildContext context) async {
  final projectNameController = material.TextEditingController();
  final projectService = di<ProjectService>();

  await fluent.showDialog<String>(
    context: context,
    builder: (context) => fluent.ContentDialog(
      title: const fluent.Text('New Project'),
      content: fluent.TextBox(
        controller: projectNameController,
        placeholder: 'Enter project name',
      ),
      actions: [
        fluent.Button(
          child: const fluent.Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        fluent.FilledButton(
          child: const fluent.Text('Create'),
          onPressed: () {
            Navigator.of(context).pop(projectNameController.text);
          },
        ),
      ],
    ),
  ).then((projectName) async {
    if (projectName != null && projectName.trim().isNotEmpty) {
      try {
        final newProjectId = await projectService.createNewProject(name: projectName.trim());
        print("Created new project with ID: $newProjectId");
        // TODO: Optionally load the newly created project
      } catch (e) {
        print("Error creating project: $e");
        // TODO: Show error dialog to user
      }
    } else if (projectName != null) {
      // Handle empty name case if needed (e.g., show validation in dialog)
      print("Project name cannot be empty.");
    }
  });
}

// Updated to accept BuildContext and show a project list dialog
Future<void> _handleOpenProject(fluent.BuildContext context) async {
  final projectService = di<ProjectService>();
  List<Project> projects = [];

  try {
    // Get the current list of projects once
    projects = await projectService.watchAllProjects().first;
  } catch (e) {
    print("Error fetching projects: $e");
    // TODO: Show error dialog
    return;
  }

  if (projects.isEmpty) {
    await fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const fluent.Text('Open Project'),
        content: const fluent.Text('No projects found. Create one first?'),
        actions: [
          fluent.Button(
            child: const fluent.Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    return;
  }

  await fluent.showDialog<int>(
    context: context,
    builder: (context) {
      return fluent.ContentDialog(
        title: const fluent.Text('Open Project'),
        // Constrain the height to avoid overly large dialogs
        content: SizedBox(
          height: 300,
          width: 300, // Give it a reasonable width too
          child: fluent.ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return fluent.ListTile.selectable(
                title: fluent.Text(project.name),
                subtitle: fluent.Text('Created: ${project.createdAt.toLocal()}'),
                selected: false, // Selection handled by tapping
                onPressed: () {
                  Navigator.of(context).pop(project.id);
                },
              );
            },
          ),
        ),
        actions: [
          fluent.Button(
            child: const fluent.Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  ).then((selectedProjectId) {
    if (selectedProjectId != null) {
      print("Attempting to load project ID: $selectedProjectId");
      projectService.loadProject(selectedProjectId);
    }
  });
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

// --- New Action Handlers for Tracks ---
void _handleAddVideoTrack() {
  final projectService = di<ProjectService>();
  final currentProject = projectService.currentProjectNotifier.value;
  if (currentProject != null) {
    projectService.addTrack(type: 'video');
  } else {
    // TODO: Show message - cannot add track without open project
    print("Cannot add video track: No project loaded.");
  }
}

void _handleAddAudioTrack() {
  final projectService = di<ProjectService>();
  final currentProject = projectService.currentProjectNotifier.value;
  if (currentProject != null) {
    projectService.addTrack(type: 'audio');
  } else {
    // TODO: Show message - cannot add track without open project
    print("Cannot add audio track: No project loaded.");
  }
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
    // Get project service to check if a project is loaded
    final projectService = di<ProjectService>();
    final isProjectLoaded = projectService.currentProjectNotifier.value != null;

    return material.PlatformMenuBar(
       menus: [
            material.PlatformMenu(
              label: 'File',
              menus: [
                material.PlatformMenuItem(
                  label: 'New Project',
                  onSelected: () => _handleNewProject(context),
                ),
                material.PlatformMenuItem(
                  label: 'Open Project...',
                  onSelected: () => _handleOpenProject(context),
                ),
                material.PlatformMenuItem(
                  label: 'Import Media...',
                  onSelected: isProjectLoaded ? () => _handleImportMedia(timelineVm) : null,
                ),
                material.PlatformMenuItem(
                  label: 'Save Project',
                  onSelected: isProjectLoaded ? () => _handleSaveProject(projectVm) : null,
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
              label: 'Track',
              menus: [
                material.PlatformMenuItem(
                  label: 'Add Video Track',
                  onSelected: isProjectLoaded ? _handleAddVideoTrack : null,
                ),
                material.PlatformMenuItem(
                  label: 'Add Audio Track',
                  onSelected: isProjectLoaded ? _handleAddAudioTrack : null,
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
    // Get project service to check if a project is loaded
    // Use ValueListenableBuilder to reactively enable/disable menus
    final projectService = di<ProjectService>();

     return fluent.Row(
        mainAxisSize: fluent.MainAxisSize.min,
        children: [
          fluent.DropDownButton(
            title: const fluent.Text('File'),
            items: [
              fluent.MenuFlyoutItem(text: const fluent.Text('New Project'), onPressed: () => _handleNewProject(context)),
              fluent.MenuFlyoutItem(text: const fluent.Text('Open Project...'), onPressed: () => _handleOpenProject(context)),
              fluent.MenuFlyoutSeparator(),
              fluent.MenuFlyoutItem(
                text: const fluent.Text('Import Media...'),
                onPressed: () {
                  if (projectService.currentProjectNotifier.value != null) {
                     _handleImportMedia(timelineVm);
                  }
                }
              ),
              fluent.MenuFlyoutItem(
                text: const fluent.Text('Save Project'),
                onPressed: () {
                  if (projectService.currentProjectNotifier.value != null) {
                    _handleSaveProject(projectVm);
                  }
                }
              ),
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
          // --- Track Menu (using ValueListenableBuilder for enabling) ---
          ValueListenableBuilder<Project?>(
             valueListenable: projectService.currentProjectNotifier,
             builder: (context, currentProject, _) {
               final enabled = currentProject != null;
               return fluent.DropDownButton(
                 title: const fluent.Text('Track'),
                 items: [
                   fluent.MenuFlyoutItem(
                     text: const fluent.Text('Add Video Track'),
                     onPressed: enabled ? _handleAddVideoTrack : null,
                   ),
                   fluent.MenuFlyoutItem(
                     text: const fluent.Text('Add Audio Track'),
                     onPressed: enabled ? _handleAddAudioTrack : null,
                   ),
                 ],
               );
            }
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