import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Extension sidebar similar to VS Code's activity bar
class ExtensionSidebar extends StatelessWidget with WatchItMixin {
  const ExtensionSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    // Use watch_it's data binding to observe the selectedExtension property
    final selectedExtension = watchValue(
      (EditorViewModel vm) => vm.selectedExtensionNotifier,
    );

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
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.folderOpen,
                  id: 'media',
                  tooltip: 'Media',
                  isSelected: selectedExtension == 'media',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.video,
                  id: 'composition',
                  tooltip: 'Composition',
                  isSelected: selectedExtension == 'composition',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.brush,
                  id: 'backgroundRemoval',
                  tooltip: 'Background Removal',
                  isSelected: selectedExtension == 'backgroundRemoval',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.refreshCw,
                  id: 'replace',
                  tooltip: 'Replace',
                  isSelected: selectedExtension == 'replace',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.eye,
                  id: 'track',
                  tooltip: 'Track',
                  isSelected: selectedExtension == 'track',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.plus,
                  id: 'addFx',
                  tooltip: 'Add FX',
                  isSelected: selectedExtension == 'addFx',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.image,
                  id: 'generate',
                  tooltip: 'Generate',
                  isSelected: selectedExtension == 'generate',
                ),
                _buildExtensionElevatedButton(
                  context: context,
                  icon: LucideIcons.palette,
                  id: 'enhance',
                  tooltip: 'Enhance',
                  isSelected: selectedExtension == 'enhance',
                ),
              ],
            ),
          ),

          // Bottom section with settings and export
          _buildExtensionElevatedButton(
            context: context,
            icon: LucideIcons.download,
            id: 'export',
            tooltip: 'Export',
            isSelected: selectedExtension == 'export',
          ),
          _buildExtensionElevatedButton(
            context: context,
            icon: LucideIcons.settings,
            id: 'settings',
            tooltip: 'Settings',
            isSelected: selectedExtension == 'settings',
          ),
        ],
      ),
    );
  }

  Widget _buildExtensionElevatedButton({
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
          backgroundColor:
              isSelected
                  ? WidgetStateProperty.all(
                    const Color(0xFF3373F2).withAlpha(51),
                  )
                  : WidgetStateProperty.all(Colors.transparent),
        ),
      ),
    );
  }
}
