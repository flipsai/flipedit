import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/undo_redo_service.dart';

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
          content: SizedBox(
            height: 50,
            child: TextBox(
              controller: projectNameController,
              placeholder: 'Enter project name',
            ),
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
        final newProjectId = await projectVm.createNewProject(
          projectName.trim(),
        );
        logInfo(_logTag, "Created new project with ID: $newProjectId");
        // TODO: Optionally load the newly created project using projectVm.loadProject(newProjectId)
        // Load the newly created project
        await projectVm.loadProject(newProjectId);
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
  List<ProjectMetadata> projects = [];

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
                subtitle: Text('Created: ${project.createdAt.toLocal()}'
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
      projectVm.loadProject(selectedProjectId).catchError((e) {
        logError(_logTag, "Error loading project $selectedProjectId: $e");
        // TODO: Show error to user
      });
    }
  });
}

// Updated to use ProjectViewModel command directly
Future<void> _handleImportMedia(
  BuildContext context,
  ProjectViewModel projectVm, // Already using ProjectViewModel
) async {
  // Remove instantiation of MediaImportService
  final loadingOverlay = _showLoadingOverlay( // Use local helper
    context, 
    'Selecting file...'
  );
  
  try {
    // Use the ViewModel command to import media
    final importSuccess = await projectVm.importMedia(context);
    
    // Remove loading overlay
    loadingOverlay.remove();
    
    // Show success/failure notification (Use local helper)
    if (importSuccess) {
      _showNotification( // Use local helper
        context,
        'Media imported successfully',
        severity: InfoBarSeverity.success
      );
    } else {
      _showNotification( // Use local helper
        context,
        'Failed to import media or cancelled',
        severity: InfoBarSeverity.warning // Use warning for cancellation
      );
    }
  } catch (e) {
    // Remove loading overlay if an error occurs
    loadingOverlay.remove();
    
    _showNotification( // Use local helper
      context,
      'Error importing media: ${e.toString()}',
      severity: InfoBarSeverity.error
    );
    
    logError(_logTag, "Unexpected error in import flow: $e");
  }
}

Future<void> _handleUndo(TimelineViewModel timelineVm) async {
  logInfo(_logTag, "Action: Undo");
  try {
    await di<UndoRedoService>().undo();
    logInfo(_logTag, "Undo completed.");
    // Refresh timeline clips after undo
    await timelineVm.refreshClips();
  } catch (e) {
    logError(_logTag, "Error during undo: $e");
  }
}

Future<void> _handleRedo(TimelineViewModel timelineVm) async {
  logInfo(_logTag, "Action: Redo");
  try {
    await di<UndoRedoService>().redo();
    logInfo(_logTag, "Redo completed.");
    // Refresh timeline clips after redo
    await timelineVm.refreshClips();
  } catch (e) {
    logError(_logTag, "Error during redo: $e");
  }
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
  @override
  Widget build(BuildContext context) {
    final bool isProjectLoaded = widget.projectVm.isProjectLoadedNotifier.value;
    final bool isInspectorVisible = widget.editorVm.isInspectorVisibleNotifier.value;
    final bool isTimelineVisible = widget.editorVm.isTimelineVisibleNotifier.value;
    final bool isPreviewVisible = widget.editorVm.isPreviewVisibleNotifier.value;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'File',
          menus: [
            PlatformMenuItem(
              label: 'New Project',
              onSelected: () => _handleNewProject(context, widget.projectVm),
            ),
            PlatformMenuItem(
              label: 'Open Project...',
              onSelected: () => _handleOpenProject(context, widget.projectVm),
            ),
            PlatformMenuItem(
              label: 'Import Media...',
              onSelected: isProjectLoaded ? () => _handleImportMedia(context, widget.projectVm) : null,
            )
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItem(
              label: 'Undo',
              onSelected: () => _handleUndo(widget.timelineVm),
            ),
            PlatformMenuItem(
              label: 'Redo',
              onSelected: () => _handleRedo(widget.timelineVm),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Track',
          menus: [
            PlatformMenuItem(
              label: 'Add Video Track',
              onSelected: isProjectLoaded ? () => _handleAddVideoTrack(widget.projectVm) : null,
            ),
            PlatformMenuItem(
              label: 'Add Audio Track',
              onSelected: isProjectLoaded ? () => _handleAddAudioTrack(widget.projectVm) : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItem(
              label: isInspectorVisible ? '✓ Inspector' : '  Inspector',
              onSelected: () => widget.editorVm.toggleInspector(),
            ),
            PlatformMenuItem(
              label: isTimelineVisible ? '✓ Timeline' : '  Timeline',
              onSelected: () => widget.editorVm.toggleTimeline(),
            ),
            PlatformMenuItem(
              label: isPreviewVisible ? '✓ Preview' : '  Preview',
              onSelected: () => widget.editorVm.togglePreview(),
            ),
          ],
        ),
      ],
      child: widget.child,
    );
  }
}

// --- Widget for Linux / Other ---
class FluentAppMenuBar extends StatefulWidget {
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
  State<FluentAppMenuBar> createState() => _FluentAppMenuBarState();
}

class _FluentAppMenuBarState extends State<FluentAppMenuBar> {
  @override
  Widget build(BuildContext context) {
    final bool isProjectLoaded = widget.projectVm.isProjectLoadedNotifier.value;
    final bool isInspectorVisible = widget.editorVm.isInspectorVisibleNotifier.value;
    final bool isTimelineVisible = widget.editorVm.isTimelineVisibleNotifier.value;
    final bool isPreviewVisible = widget.editorVm.isPreviewVisibleNotifier.value;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, right: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropDownButton(
            title: const Text('File'),
            items: [
              MenuFlyoutItem(
                text: const Text('New Project'),
                onPressed: () => _handleNewProject(context, widget.projectVm),
              ),
              MenuFlyoutItem(
                text: const Text('Open Project...'),
                onPressed: () => _handleOpenProject(context, widget.projectVm),
              ),
              MenuFlyoutItem(
                text: const Text('Import Media...'),
                onPressed: isProjectLoaded ? () => _handleImportMedia(context, widget.projectVm) : null,
              )
            ],
          ),
          const SizedBox(width: 8),
          DropDownButton(
            title: const Text('Edit'),
            items: [
              MenuFlyoutItem(
                text: const Text('Undo'),
                onPressed: () => _handleUndo(widget.timelineVm),
              ),
              MenuFlyoutItem(
                text: const Text('Redo'),
                onPressed: () => _handleRedo(widget.timelineVm),
              ),
            ],
          ),
          const SizedBox(width: 8),
          DropDownButton(
            title: const Text('Track'),
            items: [
              MenuFlyoutItem(
                text: const Text('Add Video Track'),
                onPressed: isProjectLoaded ? () => _handleAddVideoTrack(widget.projectVm) : null,
              ),
              MenuFlyoutItem(
                text: const Text('Add Audio Track'),
                onPressed: isProjectLoaded ? () => _handleAddAudioTrack(widget.projectVm) : null,
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
                onPressed: () => widget.editorVm.toggleInspector(),
              ),
              MenuFlyoutItem(
                leading:
                    isTimelineVisible ? const Icon(FluentIcons.check_mark) : null,
                text: const Text('Timeline'),
                onPressed: () => widget.editorVm.toggleTimeline(),
              ),
              MenuFlyoutItem(
                leading:
                    isPreviewVisible ? const Icon(FluentIcons.check_mark) : null,
                text: const Text('Preview'),
                onPressed: () => widget.editorVm.togglePreview(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Add helper methods here (or move to a common UI utils file)
// Shows a loading indicator overlay
OverlayEntry _showLoadingOverlay(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (context) => Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluentTheme.of(context).resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ProgressRing(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    ),
  );
  
  overlay.insert(entry);
  return entry;
}

// Shows a notification message
void _showNotification(
  BuildContext context, 
  String message, 
  {InfoBarSeverity severity = InfoBarSeverity.info}
) {
  displayInfoBar(context, builder: (context, close) {
    return InfoBar(
      title: Text(message),
      severity: severity,
      onClose: close,
    );
  });
}
