import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Extension sidebar similar to VS Code's activity bar
class ExtensionSidebar extends StatelessWidget with WatchItMixin {
  const ExtensionSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    // Use watch_it's data binding to observe the selectedExtension property
    final selectedExtension = watchValue((EditorViewModel vm) => vm.selectedExtensionNotifier);
    
    return Container(
      width: 48,
      color: const Color(0xFF2C2C2C),
      child: Column(
        children: [
          // Top section with main extensions
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.folder_open,
                  id: 'media',
                  tooltip: 'Media',
                  isSelected: selectedExtension == 'media',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.video,
                  id: 'composition',
                  tooltip: 'Composition',
                  isSelected: selectedExtension == 'composition',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.broom,
                  id: 'backgroundRemoval',
                  tooltip: 'Background Removal',
                  isSelected: selectedExtension == 'backgroundRemoval',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.refresh,
                  id: 'replace',
                  tooltip: 'Replace',
                  isSelected: selectedExtension == 'replace',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.view,
                  id: 'track',
                  tooltip: 'Track',
                  isSelected: selectedExtension == 'track',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.add,
                  id: 'addFx',
                  tooltip: 'Add FX',
                  isSelected: selectedExtension == 'addFx',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.picture,
                  id: 'generate',
                  tooltip: 'Generate',
                  isSelected: selectedExtension == 'generate',
                ),
                _buildExtensionButton(
                  context: context,
                  icon: FluentIcons.color,
                  id: 'enhance',
                  tooltip: 'Enhance',
                  isSelected: selectedExtension == 'enhance',
                ),
              ],
            ),
          ),
          
          // Bottom section with settings and export
          _buildExtensionButton(
            context: context,
            icon: FluentIcons.export,
            id: 'export',
            tooltip: 'Export',
            isSelected: selectedExtension == 'export',
          ),
          _buildExtensionButton(
            context: context,
            icon: FluentIcons.settings,
            id: 'settings',
            tooltip: 'Settings',
            isSelected: selectedExtension == 'settings',
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionButton({
    required BuildContext context,
    required IconData icon,
    required String id,
    required String tooltip,
    required bool isSelected,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.grey[80],
          size: 20,
        ),
        onPressed: () {
          // Toggle the extension panel - turn off if already selected
          if (isSelected) {
            di<EditorViewModel>().selectedExtension = '';
          } else {
            di<EditorViewModel>().selectedExtension = id;
          }
        },
        style: ButtonStyle(
          padding: WidgetStateProperty.all(const EdgeInsets.all(12)),
          backgroundColor: isSelected 
              ? WidgetStateProperty.all(const Color(0xFF3373F2).withAlpha(51))
              : WidgetStateProperty.all(Colors.transparent),
        ),
      ),
    );
  }
}
