import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

// --- Action Handlers (Now using ProjectViewModel) ---

// Updated to accept BuildContext and ProjectViewModel
Future<void> _handleNewProject(fluent.BuildContext context, ProjectViewModel projectVm) async {
  final projectNameController = fluent.TextEditingController();

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
        // Use ViewModel command
        final newProjectId = await projectVm.createNewProjectCommand(projectName.trim());
        print("Created new project with ID: $newProjectId");
        // TODO: Optionally load the newly created project using projectVm.loadProjectCommand(newProjectId)
      } catch (e) {
        print("Error creating project: $e");
        // TODO: Show error dialog to user (e.g., using context)
      }
    } else if (projectName != null) {
      // Handle empty name case if needed (e.g., show validation in dialog)
      print("Project name cannot be empty.");
      // TODO: Show validation error to user
    }
  });
}

// Updated to accept BuildContext and ProjectViewModel
Future<void> _handleOpenProject(fluent.BuildContext context, ProjectViewModel projectVm) async {
  List<Project> projects = [];

  try {
    // Get the current list of projects via ViewModel
    projects = await projectVm.getAllProjects();
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
                // Ensure createdAt is not null before formatting
                subtitle: fluent.Text(project.createdAt != null ? 'Created: ${project.createdAt!.toLocal()}' : 'Created: Unknown'),
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
      // Use ViewModel command
      projectVm.loadProjectCommand(selectedProjectId).catchError((e) {
         print("Error loading project $selectedProjectId: $e");
         // TODO: Show error to user
      });
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

           // Get the first track ID or default/error if none
           final int targetTrackId;
           if (timelineVm.currentTrackIds.isNotEmpty) {
              targetTrackId = timelineVm.currentTrackIds.first;
           } else {
              print("Error: No tracks loaded to import media into.");
              // Optionally show a user message
              return; // Don't proceed if no track is available
           }

          // For now, using placeholder values
          // Create ClipModel instead of Clip
          // Needs source start/end times instead of durationFrames
          final dummyClipData = ClipModel(
            databaseId: null, // No ID yet
            trackId: targetTrackId, // Use determined track ID
            name: filePath.split(Platform.pathSeparator).last,
            type: ClipType.video, // TODO: Detect type
            sourcePath: filePath,
            startTimeInSourceMs: 0, // Placeholder
            endTimeInSourceMs: 5000, // Placeholder: 5 seconds
            startTimeOnTrackMs: 0, // Placeholder, set by addClipAtPosition
          );
          // Use addClipAtPosition
          await timelineVm.addClipAtPosition(
             clipData: dummyClipData,
             trackId: targetTrackId, // Use determined track ID
             startTimeInSourceMs: dummyClipData.startTimeInSourceMs,
             endTimeInSourceMs: dummyClipData.endTimeInSourceMs,
             // Let addClipAtPosition handle placement at playhead
          );
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

// Updated to use ProjectViewModel command
void _handleSaveProject(ProjectViewModel projectVm) {
  projectVm.saveProjectCommand().then((_) {
    print("Action: Save Project initiated.");
  }).catchError((e) {
    print("Error saving project: $e");
    // TODO: Show error to user
  });
}

void _handleUndo() {
  print("Action: Undo");
  // TODO: Implement undo logic (likely via a dedicated Undo/Redo Service/ViewModel)
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

// --- New Action Handlers for Tracks (using ProjectViewModel) ---
void _handleAddVideoTrack(ProjectViewModel projectVm) {
  projectVm.addTrackCommand(type: 'video').then((_) {
    print("Action: Add Video Track initiated.");
  }).catchError((e) {
    print("Error adding video track: $e");
    // TODO: Show error to user
  });
}

void _handleAddAudioTrack(ProjectViewModel projectVm) {
  projectVm.addTrackCommand(type: 'audio').then((_) {
    print("Action: Add Audio Track initiated.");
  }).catchError((e) {
    print("Error adding audio track: $e");
    // TODO: Show error to user
  });
}

// --- Widget for macOS / Windows ---
class PlatformAppMenuBar extends fluent.StatelessWidget {
  final bool isInspectorVisible; // Consider moving these to EditorViewModel
  final bool isTimelineVisible;  // Consider moving these to EditorViewModel
  final EditorViewModel editorVm;
  final ProjectViewModel projectVm;
  final TimelineViewModel timelineVm;
  final fluent.Widget child;

  const PlatformAppMenuBar({
    super.key,
    required this.isInspectorVisible,
    required this.isTimelineVisible,
    required this.editorVm,
    required this.projectVm,
    required this.timelineVm,
    required this.child,
  });

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Use ValueListenableBuilder to react to project loaded state
    return ValueListenableBuilder<bool>(
      valueListenable: projectVm.isProjectLoadedNotifier,
      builder: (context, isProjectLoaded, _) {
        return fluent.PlatformMenuBar(
           menus: [
                fluent.PlatformMenu(
                  label: 'File',
                  menus: [
                    fluent.PlatformMenuItem(
                      label: 'New Project',
                      // Pass context and projectVm
                      onSelected: () => _handleNewProject(context, projectVm),
                    ),
                    fluent.PlatformMenuItem(
                      label: 'Open Project...',
                      // Pass context and projectVm
                      onSelected: () => _handleOpenProject(context, projectVm),
                    ),
                    fluent.PlatformMenuItem(
                      label: 'Import Media...',
                      // Enable based on isProjectLoaded from builder
                      onSelected: isProjectLoaded ? () => _handleImportMedia(timelineVm) : null,
                    ),
                    fluent.PlatformMenuItem(
                      label: 'Save Project',
                      // Enable based on isProjectLoaded from builder
                      onSelected: isProjectLoaded ? () => _handleSaveProject(projectVm) : null,
                    ),
                  ],
                ),
                fluent.PlatformMenu(
                  label: 'Edit',
                  menus: [
                    fluent.PlatformMenuItem(
                      label: 'Undo',
                      onSelected: _handleUndo // Assuming Undo/Redo is independent of project
                    ),
                    fluent.PlatformMenuItem(
                      label: 'Redo',
                      onSelected: _handleRedo
                    ),
                  ],
                ),
                fluent.PlatformMenu(
                  label: 'Track',
                  menus: [
                    fluent.PlatformMenuItem(
                      label: 'Add Video Track',
                      // Enable based on isProjectLoaded, pass projectVm
                      onSelected: isProjectLoaded ? () => _handleAddVideoTrack(projectVm) : null,
                    ),
                    fluent.PlatformMenuItem(
                      label: 'Add Audio Track',
                      // Enable based on isProjectLoaded, pass projectVm
                      onSelected: isProjectLoaded ? () => _handleAddAudioTrack(projectVm) : null,
                    ),
                  ],
                ),
                fluent.PlatformMenu(
                  label: 'View',
                  menus: [
                    fluent.PlatformMenuItem(
                      // isInspectorVisible/isTimelineVisible might be better sourced from editorVm directly
                      label: isInspectorVisible ? '✓ Inspector' : '  Inspector',
                      onSelected: () => _handleToggleInspector(editorVm),
                    ),
                    fluent.PlatformMenuItem(
                      label: isTimelineVisible ? '✓ Timeline' : '  Timeline',
                      onSelected: () => _handleToggleTimeline(editorVm),
                    ),
                  ],
                ),
              ],
          child: child,
        );
      }
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
    // Use ValueListenableBuilder to reactively enable/disable menus
    return ValueListenableBuilder<bool>(
      valueListenable: projectVm.isProjectLoadedNotifier,
      builder: (context, isProjectLoaded, _) {
         return fluent.Row(
            mainAxisSize: fluent.MainAxisSize.min,
            children: [
              fluent.DropDownButton(
                title: const fluent.Text('File'),
                items: [
                  fluent.MenuFlyoutItem(text: const fluent.Text('New Project'), onPressed: () => _handleNewProject(context, projectVm)),
                  fluent.MenuFlyoutItem(text: const fluent.Text('Open Project...'), onPressed: () => _handleOpenProject(context, projectVm)),
                  fluent.MenuFlyoutSeparator(),
                  fluent.MenuFlyoutItem(
                    text: const fluent.Text('Import Media...'),
                    // Enable based on isProjectLoaded from builder
                    onPressed: isProjectLoaded ? () => _handleImportMedia(timelineVm) : null,
                  ),
                  fluent.MenuFlyoutItem(
                    text: const fluent.Text('Save Project'),
                    // Enable based on isProjectLoaded from builder
                    onPressed: isProjectLoaded ? () => _handleSaveProject(projectVm) : null,
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
              // --- Track Menu --- Already uses ValueListenableBuilder, just update handlers
              fluent.DropDownButton(
                 title: const fluent.Text('Track'),
                 items: [
                   fluent.MenuFlyoutItem(
                     text: const fluent.Text('Add Video Track'),
                     // Enable based on isProjectLoaded, pass projectVm
                     onPressed: isProjectLoaded ? () => _handleAddVideoTrack(projectVm) : null,
                   ),
                   fluent.MenuFlyoutItem(
                     text: const fluent.Text('Add Audio Track'),
                     // Enable based on isProjectLoaded, pass projectVm
                     onPressed: isProjectLoaded ? () => _handleAddAudioTrack(projectVm) : null,
                   ),
                 ],
               ),
              const fluent.SizedBox(width: 8),
              // View menu uses EditorViewModel state, no changes needed for project loading
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
    );
  }
}

// Removed duplicate AppMenuBar class 