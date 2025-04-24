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
  await projectVm.createNewProjectWithDialog(context);
}

// Updated to accept BuildContext and ProjectViewModel
Future<void> _handleOpenProject(
  BuildContext context,
  ProjectViewModel projectVm,
) async {
  await projectVm.openProjectDialog(context);
}

// Updated to use ProjectViewModel command directly
Future<void> _handleImportMedia(
  BuildContext context,
  ProjectViewModel projectVm,
) async {
  await projectVm.importMediaWithUI(context);
}

Future<void> _handleUndo(TimelineViewModel timelineVm) async {
  await timelineVm.undo();
}

Future<void> _handleRedo(TimelineViewModel timelineVm) async {
  await timelineVm.redo();
}

// --- New Action Handlers for Tracks (using ProjectViewModel) ---
void _handleAddVideoTrack(ProjectViewModel projectVm) {
  projectVm.addTrackCommand(type: 'video');
}

void _handleAddAudioTrack(ProjectViewModel projectVm) {
  projectVm.addTrackCommand(type: 'audio');
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
              label: 'Inspector', // Always show label without checkmark
              onSelected: () => widget.editorVm.toggleInspector(),
            ),
            PlatformMenuItem(
              label: 'Timeline', // Always show label without checkmark
              onSelected: () => widget.editorVm.toggleTimeline(),
            ),
            PlatformMenuItem(
              label: 'Preview', // Always show label without checkmark
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
    // No need to read notifiers here directly, ValueListenableBuilder will handle it.
    final bool isProjectLoaded = widget.projectVm.isProjectLoadedNotifier.value; // Keep for non-View menus

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
          // Wrap the entire DropDownButton with ValueListenableBuilders
          ValueListenableBuilder<bool>(
            valueListenable: widget.editorVm.isInspectorVisibleNotifier,
            builder: (context, isInspectorVisible, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.editorVm.isTimelineVisibleNotifier,
                builder: (context, isTimelineVisible, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: widget.editorVm.isPreviewVisibleNotifier,
                    builder: (context, isPreviewVisible, _) {
                      // Build the DropDownButton inside the innermost builder
                      return DropDownButton(
                        title: const Text('View'),
                        items: [
                          MenuFlyoutItem(
                            leading: isInspectorVisible
                                ? const Icon(FluentIcons.check_mark)
                                : null,
                            text: const Text('Inspector'),
                            onPressed: () => widget.editorVm.toggleInspector(),
                          ),
                          MenuFlyoutItem(
                            leading: isTimelineVisible
                                ? const Icon(FluentIcons.check_mark)
                                : null,
                            text: const Text('Timeline'),
                            onPressed: () => widget.editorVm.toggleTimeline(),
                          ),
                          MenuFlyoutItem(
                            leading: isPreviewVisible
                                ? const Icon(FluentIcons.check_mark)
                                : null,
                            text: const Text('Preview'),
                            onPressed: () => widget.editorVm.togglePreview(),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

