import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:watch_it/watch_it.dart' hide di;

class EditorScreen extends StatelessWidget with WatchItMixin {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final projectViewModel = di<ProjectViewModel>();
    final projectName = watchPropertyValue((ProjectViewModel vm) => vm.currentProject?.name ?? 'Untitled Project');
    
    final editorViewModel = di<EditorViewModel>();
    final selectedExtension = watchPropertyValue((EditorViewModel vm) => vm.selectedExtension);
    final showTimeline = watchPropertyValue((EditorViewModel vm) => vm.showTimeline);
    final showInspector = watchPropertyValue((EditorViewModel vm) => vm.showInspector);
    
    return NavigationView(
      appBar: NavigationAppBar(
        title: Text(projectName),
        actions: Row(
          children: [
            Button(
              child: const Text('Save'),
              onPressed: () {
                projectViewModel.saveProject();
              },
            ),
            const SizedBox(width: 8),
            Button(
              child: const Text('Export'),
              onPressed: () {
                // Show export dialog
              },
            ),
          ],
        ),
      ),
      pane: NavigationPane(
        selected: 0,
        header: const SizedBox(height: 10),
        displayMode: PaneDisplayMode.compact,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.edit),
            title: const Text('Editor'),
            body: Row(
              children: [
                // Left sidebar with extensions (similar to VS Code's activity bar)
                const ExtensionSidebar(),
                
                // Extension panel when an extension is selected
                if (selectedExtension.isNotEmpty)
                  ExtensionPanelContainer(extensionId: selectedExtension),
                
                // Main editor area
                Expanded(
                  child: Column(
                    children: [
                      // Preview area - always visible
                      Expanded(
                        flex: 3,
                        child: Container(
                          color: Colors.black,
                          child: const Center(
                            child: Text(
                              'Preview',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      
                      // Timeline panel - can be toggled
                      if (showTimeline)
                        const Expanded(
                          flex: 1,
                          child: Timeline(),
                        ),
                    ],
                  ),
                ),
                
                // Right sidebar with inspector
                if (showInspector)
                  const SizedBox(
                    width: 300,
                    child: InspectorPanel(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
