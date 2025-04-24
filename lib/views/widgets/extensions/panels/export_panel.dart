import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';

/// Panel for exporting projects
class ExportPanel extends StatelessWidget with WatchItMixin {
  const ExportPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final projectVm = di<ProjectViewModel>();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Project',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Format',
            child: ValueListenableBuilder<String?>(
              valueListenable: projectVm.exportFormatNotifier,
              builder: (context, selectedFormat, _) {
                return ComboBox<String>(
                  value: selectedFormat,
                  placeholder: const Text('Select format'),
                  isExpanded: true,
                  items: const [
                    ComboBoxItem<String>(value: 'mp4', child: Text('MP4 (H.264)')),
                    ComboBoxItem<String>(value: 'mov', child: Text('MOV (ProRes)')),
                    ComboBoxItem<String>(value: 'webm', child: Text('WebM (VP9)')),
                    ComboBoxItem<String>(value: 'gif', child: Text('GIF')),
                  ],
                  onChanged: (value) {
                    projectVm.setExportFormat(value);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Resolution',
            child: ValueListenableBuilder<String?>(
              valueListenable: projectVm.exportResolutionNotifier,
              builder: (context, selectedResolution, _) {
                return ComboBox<String>(
                  value: selectedResolution,
                  placeholder: const Text('Select resolution'),
                  isExpanded: true,
                  items: const [
                    ComboBoxItem<String>(
                      value: '1080p',
                      child: Text('1080p (1920x1080)'),
                    ),
                    ComboBoxItem<String>(
                      value: '720p',
                      child: Text('720p (1280x720)'),
                    ),
                    ComboBoxItem<String>(
                      value: '4k',
                      child: Text('4K (3840x2160)'),
                    ),
                    ComboBoxItem<String>(value: 'custom', child: Text('Custom...')),
                  ],
                  onChanged: (value) {
                    projectVm.setExportResolution(value);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Output Location',
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: projectVm.exportPathNotifier,
                    builder: (context, path, _) {
                      return TextBox(
                        placeholder: path,
                        readOnly: true,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  child: const Text('Browse'),
                  onPressed: () async {
                    final newPath = await projectVm.selectExportPath(context);
                    if (newPath != null) {
                      projectVm.exportPathNotifier.value = newPath;
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Export'),
            onPressed: () {
              projectVm.exportProject(context);
            },
          ),
        ],
      ),
    );
  }
}