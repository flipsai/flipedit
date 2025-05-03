import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';

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
                  label: 'Inspector',
                  onSelected: () => widget.editorVm.toggleInspector(),
                ),
                PlatformMenuItem(
                  label: 'Timeline',
                  onSelected: () => widget.editorVm.toggleTimeline(),
                ),
                PlatformMenuItem(
                  label: 'Preview',
                  onSelected: () => widget.editorVm.togglePreview(),
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
              return DropDownButton(
                title: const Text('File'),
                items: [
                  MenuFlyoutItem(
                    text: const Text('New Project'),
                    onPressed: () => _handleNewProject(context),
                  ),
                  MenuFlyoutItem(
                    text: const Text('Open Project...'),
                    onPressed: () => _handleOpenProject(context),
                  ),
                  MenuFlyoutItem(
                    text: const Text('Import Media...'),
                    onPressed:
                        isProjectLoaded
                            ? () => _handleImportMedia(context)
                            : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          DropDownButton(
            title: const Text('Edit'),
            items: [
              MenuFlyoutItem(
                text: const Text('Undo'),
                onPressed: () => _handleUndo(),
              ),
              MenuFlyoutItem(
                text: const Text('Redo'),
                onPressed: () => _handleRedo(),
              ),
            ],
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: widget.projectVm.isProjectLoadedNotifier,
            builder: (context, isProjectLoaded, _) {
              return DropDownButton(
                title: const Text('Track'),
                items: [
                  MenuFlyoutItem(
                    text: const Text('Add Video Track'),
                    onPressed:
                        isProjectLoaded ? () => _handleAddVideoTrack() : null,
                  ),
                  MenuFlyoutItem(
                    text: const Text('Add Audio Track'),
                    onPressed:
                        isProjectLoaded ? () => _handleAddAudioTrack() : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: widget.editorVm.isInspectorVisibleNotifier,
            builder: (context, isInspectorVisible, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.editorVm.isTimelineVisibleNotifier,
                builder: (context, isTimelineVisible, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: widget.editorVm.isPreviewVisibleNotifier,
                    builder: (context, isPreviewVisible, _) {
                      return DropDownButton(
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
                                isTimelineVisible
                                    ? const Icon(FluentIcons.check_mark)
                                    : null,
                            text: const Text('Timeline'),
                            onPressed: () => widget.editorVm.toggleTimeline(),
                          ),
                          MenuFlyoutItem(
                            leading:
                                isPreviewVisible
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
