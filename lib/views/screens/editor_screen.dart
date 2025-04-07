import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:watch_it/watch_it.dart';

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
    
    return ScaffoldPage(
      header: PageHeader(
        title: Text(projectName),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.save),
              label: const Text('Save'),
              onPressed: () {
                projectViewModel.saveProject();
              },
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.export),
              label: const Text('Export'),
              onPressed: () {
                // Show export dialog
              },
            ),
          ],
        ),
      ),
      content: Row(
        children: [
          // Left sidebar with extensions (VS Code's activity bar)
          const ExtensionSidebar(),
          
          // Extension panel when an extension is selected (VS Code's primary sidebar)
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
          
          // Right sidebar with inspector (VS Code's secondary sidebar)
          if (showInspector)
            const SizedBox(
              width: 300,
              child: InspectorPanel(),
            ),
        ],
      ),
    );
  }
}
