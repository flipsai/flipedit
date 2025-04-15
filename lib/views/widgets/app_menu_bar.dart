import 'package:fluent_ui/fluent_ui.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

// --- Action Handlers (Now using ProjectViewModel) ---
const _logTag = 'AppMenuBarActions'; // Define tag for top-level functions

// Updated to accept BuildContext and ProjectViewModel
Future<void> _handleNewProject(
  BuildContext context,
  ProjectViewModel projectVm,
) async {
  final projectNameController = TextEditingController();

  await showDialog<String>(
    context: context,
    builder:
        (context) => ContentDialog(
          title: const Text('New Project'),
          content: TextBox(
            controller: projectNameController,
            placeholder: 'Enter project name',
          ),
          actions: [
            Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            FilledButton(
              child: const Text('Create'),
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
        final newProjectId = await projectVm.createNewProjectCommand(
          projectName.trim(),
        );
        logInfo(_logTag, "Created new project with ID: $newProjectId");
        // TODO: Optionally load the newly created project using projectVm.loadProjectCommand(newProjectId)
        // Load the newly created project
        await projectVm.loadProjectCommand(newProjectId);
        logInfo(_logTag, "Loaded newly created project ID: $newProjectId");
      } catch (e) {
        logError(_logTag, "Error creating or loading project: $e");
        // TODO: Show error dialog to user (e.g., using context)
      }
    } else if (projectName != null) {
      // Handle empty name case if needed (e.g., show validation in dialog)
      logWarning(_logTag, "Project name cannot be empty.");
      // TODO: Show validation error to user
    }
  });
}

// Updated to accept BuildContext and ProjectViewModel
Future<void> _handleOpenProject(
  BuildContext context,
  ProjectViewModel projectVm,
) async {
  List<Project> projects = [];

  try {
    // Get the current list of projects via ViewModel
    projects = await projectVm.getAllProjects();
  } catch (e) {
    logError(_logTag, "Error fetching projects: $e");
    // TODO: Show error dialog
    return;
  }

  if (projects.isEmpty) {
    await showDialog(
      context: context,
      builder:
          (context) => ContentDialog(
            title: const Text('Open Project'),
            content: const Text('No projects found. Create one first?'),
            actions: [
              Button(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
    return;
  }

  await showDialog<int>(
    context: context,
    builder: (context) {
      return ContentDialog(
        title: const Text('Open Project'),
        // Constrain the height to avoid overly large dialogs
        content: SizedBox(
          height: 300,
          width: 300, // Give it a reasonable width too
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return ListTile.selectable(
                title: Text(project.name),
                // Ensure createdAt is not null before formatting
                subtitle: Text(
                  project.createdAt != null
                      ? 'Created: ${project.createdAt!.toLocal()}'
                      : 'Created: Unknown',
                ),
                selected: false, // Selection handled by tapping
                onPressed: () {
                  Navigator.of(context).pop(project.id);
                },
              );
            },
          ),
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  ).then((selectedProjectId) {
    if (selectedProjectId != null) {
      logInfo(_logTag, "Attempting to load project ID: $selectedProjectId");
      // Use ViewModel command
      projectVm.loadProjectCommand(selectedProjectId).catchError((e) {
        logError(_logTag, "Error loading project $selectedProjectId: $e");
        // TODO: Show error to user
      });
    }
  });
}

// Updated to use ProjectViewModel for importing assets
Future<void> _handleImportMedia(
  ProjectViewModel projectVm, // Change to ProjectViewModel
) async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video, // Or FileType.media for audio/images too
      allowMultiple: false, // Adjust if multiple imports are needed
    );
    if (result != null && result.files.isNotEmpty) {
      String? filePath = result.files.single.path;
      if (filePath != null) {
        // Use the new ProjectViewModel command
        await projectVm.importMediaAssetCommand(filePath);
        logInfo(_logTag, "Imported media: $filePath");
        // No longer adding directly to timeline here
      } else {
        logWarning(_logTag, "File path is null after picking.");
      }
    } else {
      logInfo(_logTag, "File picking cancelled or no file selected.");
    }
  } catch (e) {
    logError(_logTag, "Error picking file or importing asset: $e");
    // TODO: Show user-friendly error message (using context if available/needed)
  }
}

// Updated to use ProjectViewModel command
void _handleSaveProject(ProjectViewModel projectVm) {
  projectVm
      .saveProjectCommand()
      .then((_) {
        logInfo(_logTag, "Action: Save Project initiated.");
      })
      .catchError((e) {
        logError(_logTag, "Error saving project: $e");
        // TODO: Show error to user
      });
}

void _handleUndo() {
  logInfo(_logTag, "Action: Undo");
  // TODO: Implement undo logic (likely via a dedicated Undo/Redo Service/ViewModel)
}

void _handleRedo() {
  logInfo(_logTag, "Action: Redo");
  // TODO: Implement redo logic
}

// --- New Action Handlers for Tracks (using ProjectViewModel) ---
void _handleAddVideoTrack(ProjectViewModel projectVm) {
  projectVm
      .addTrackCommand(type: 'video')
      .then((_) {
        logInfo(_logTag, "Action: Add Video Track initiated.");
      })
      .catchError((e) {
        logError(_logTag, "Error adding video track: $e");
        // TODO: Show error to user
      });
}

void _handleAddAudioTrack(ProjectViewModel projectVm) {
  projectVm
      .addTrackCommand(type: 'audio')
      .then((_) {
        logInfo(_logTag, "Action: Add Audio Track initiated.");
      })
      .catchError((e) {
        logError(_logTag, "Error adding audio track: $e");
        // TODO: Show error to user
      });
}

// --- Widget for macOS / Windows ---
class PlatformAppMenuBar extends StatelessWidget with WatchItMixin {
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
  Widget build(BuildContext context) {
    // Use watchValue instead of ValueListenableBuilder
    final bool isProjectLoaded = watchValue(
      (ProjectViewModel x) => x.isProjectLoadedNotifier,
    );
    final bool isInspectorVisible = watchValue(
      (EditorViewModel x) => x.isInspectorVisibleNotifier,
    );
    final bool isTimelineVisible = watchValue(
      (EditorViewModel x) => x.isTimelineVisibleNotifier,
    );
    final bool isPreviewVisible = watchValue(
      (EditorViewModel x) => x.isPreviewVisibleNotifier,
    );

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Project',
              onSelected: () => _handleNewProject(context, projectVm),
            ),
            PlatformMenuItem(
              label: 'Open Project...',
              onSelected: () => _handleOpenProject(context, projectVm),
            ),
            PlatformMenuItem(
              label: 'Import Media...',
              onSelected: isProjectLoaded ? () => _handleImportMedia(projectVm) : null,
            ),
            PlatformMenuItem(
              label: 'Save Project',
              onSelected:
                  isProjectLoaded ? () => _handleSaveProject(projectVm) : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(label: 'Undo', onSelected: _handleUndo),
            PlatformMenuItem(label: 'Redo', onSelected: _handleRedo),
          ],
        ),
        PlatformMenu(
          label: 'Track',
          menus: [
            PlatformMenuItem(
              label: 'Add Video Track',
              onSelected:
                  isProjectLoaded
                      ? () => _handleAddVideoTrack(projectVm)
                      : null,
            ),
            PlatformMenuItem(
              label: 'Add Audio Track',
              onSelected:
                  isProjectLoaded
                      ? () => _handleAddAudioTrack(projectVm)
                      : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: isInspectorVisible ? '✓ Inspector' : '  Inspector',
              onSelected: () => editorVm.toggleInspector(),
            ),
            PlatformMenuItem(
              label: isTimelineVisible ? '✓ Timeline' : '  Timeline',
              onSelected: () => editorVm.toggleTimeline(),
            ),
            PlatformMenuItem(
              label: isPreviewVisible ? '✓ Preview' : '  Preview',
              onSelected: () => editorVm.togglePreview(),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

// --- Widget for Linux / Other ---
class FluentAppMenuBar extends StatelessWidget with WatchItMixin {
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
  Widget build(BuildContext context) {
    // Use watchValue instead of ValueListenableBuilder
    final bool isProjectLoaded = watchValue(
      (ProjectViewModel x) => x.isProjectLoadedNotifier,
    );
    final bool isInspectorVisible = watchValue(
      (EditorViewModel x) => x.isInspectorVisibleNotifier,
    );
    final bool isTimelineVisible = watchValue(
      (EditorViewModel x) => x.isTimelineVisibleNotifier,
    );
    final bool isPreviewVisible = watchValue(
      (EditorViewModel x) => x.isPreviewVisibleNotifier,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropDownButton(
          title: const Text('File'),
          items: [
            MenuFlyoutItem(
              text: const Text('New Project'),
              onPressed: () => _handleNewProject(context, projectVm),
            ),
            MenuFlyoutItem(
              text: const Text('Open Project...'),
              onPressed: () => _handleOpenProject(context, projectVm),
            ),
            MenuFlyoutItem(
              text: const Text('Import Media...'),
              onPressed: isProjectLoaded ? () => _handleImportMedia(projectVm) : null,
            ),
            MenuFlyoutItem(
              text: const Text('Save Project'),
              onPressed:
                  isProjectLoaded ? () => _handleSaveProject(projectVm) : null,
            ),
          ],
        ),
        const SizedBox(width: 8),
        DropDownButton(
          title: const Text('Edit'),
          items: [
            MenuFlyoutItem(text: const Text('Undo'), onPressed: _handleUndo),
            MenuFlyoutItem(text: const Text('Redo'), onPressed: _handleRedo),
          ],
        ),
        const SizedBox(width: 8),
        DropDownButton(
          title: const Text('Track'),
          items: [
            MenuFlyoutItem(
              text: const Text('Add Video Track'),
              onPressed:
                  isProjectLoaded
                      ? () => _handleAddVideoTrack(projectVm)
                      : null,
            ),
            MenuFlyoutItem(
              text: const Text('Add Audio Track'),
              onPressed:
                  isProjectLoaded
                      ? () => _handleAddAudioTrack(projectVm)
                      : null,
            ),
          ],
        ),
        const SizedBox(width: 8),
        DropDownButton(
          title: const Text('View'),
          items: [
            MenuFlyoutItem(
              leading:
                  isInspectorVisible
                      ? const Icon(FluentIcons.check_mark)
                      : null,
              text: const Text('Inspector'),
              onPressed: () => editorVm.toggleInspector(),
            ),
            MenuFlyoutItem(
              leading:
                  isTimelineVisible ? const Icon(FluentIcons.check_mark) : null,
              text: const Text('Timeline'),
              onPressed: () => editorVm.toggleTimeline(),
            ),
            MenuFlyoutItem(
              leading:
                  isPreviewVisible ? const Icon(FluentIcons.check_mark) : null,
              text: const Text('Preview'),
              onPressed: () => editorVm.togglePreview(),
            ),
          ],
        ),
      ],
    );
  }
}
