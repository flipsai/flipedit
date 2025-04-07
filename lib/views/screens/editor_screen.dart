import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:flipedit/views/widgets/panel_system/panel_system.dart';
import 'package:watch_it/watch_it.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorViewModel _editorViewModel;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize the panel layout
    _editorViewModel = di<EditorViewModel>();
    _editorViewModel.initializePanelLayout();
  }

  @override
  Widget build(BuildContext context) {
    // Get panel definitions for the current layout
    final panels = _editorViewModel.getPanelDefinitions();
    
    return ScaffoldPage(
      header: PageHeader(
        title: _ProjectTitle(),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.save),
              label: const Text('Save'),
              onPressed: () {
                di<ProjectViewModel>().saveProject();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.export),
              label: const Text('Export'),
              onPressed: () {
                // Show export dialog
              },
            ),
            // New toggle buttons for layout elements
            _buildTimelineToggle(),
            _buildInspectorToggle(),
          ],
        ),
      ),
      content: material.Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // Left sidebar with extensions (VS Code's activity bar)
            const ExtensionSidebar(),
            
            // Main content area with draggable panels
            Expanded(
              child: PanelGridSystem(
                initialPanels: panels,
                backgroundColor: const Color(0xFFF3F3F3),
                resizeHandleColor: const Color(0xFFDDDDDD),
              ),
            ),
          ],
        ),
      ),
    );
  }

  CommandBarButton _buildTimelineToggle() {
    return CommandBarButton(
      icon: const _TimelineButtonIcon(),
      onPressed: () {
        _editorViewModel.toggleTimeline();
      },
    );
  }

  CommandBarButton _buildInspectorToggle() {
    return CommandBarButton(
      icon: const _InspectorButtonIcon(),
      onPressed: () {
        _editorViewModel.toggleInspector();
      },
    );
  }
}

class _ProjectTitle extends StatelessWidget with WatchItMixin {
  _ProjectTitle({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final projectName = watchPropertyValue((ProjectViewModel vm) => vm.currentProject?.name) ?? 'Untitled Project';
    return Text(projectName);
  }
}

class _TimelineButtonIcon extends StatelessWidget with WatchItMixin {
  const _TimelineButtonIcon({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final showTimeline = watchPropertyValue((EditorViewModel vm) => vm.showTimeline) ?? false;
    return Icon(
      FluentIcons.timeline,
      color: showTimeline ? Colors.white : Colors.grey,
    );
  }
}

class _InspectorButtonIcon extends StatelessWidget with WatchItMixin {
  const _InspectorButtonIcon({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final showInspector = watchPropertyValue((EditorViewModel vm) => vm.showInspector) ?? false;
    return Icon(
      FluentIcons.edit_mirrored,
      color: showInspector ? Colors.white : Colors.grey,
    );
  }
}
