import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Format', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: projectVm.exportFormatNotifier,
                builder: (context, selectedFormat, _) {
                  return ShadSelect<String>(
                    initialValue: selectedFormat,
                    placeholder: const Text('Select format'),
                    options: const [
                      ShadOption(
                        value: 'mp4',
                        child: Text('MP4 (H.264)'),
                      ),
                      ShadOption(
                        value: 'mov',
                        child: Text('MOV (ProRes)'),
                      ),
                      ShadOption(
                        value: 'webm',
                        child: Text('WebM (VP9)'),
                      ),
                      ShadOption(value: 'gif', child: Text('GIF')),
                    ],
                    selectedOptionBuilder: (context, value) => Text(value),
                    onChanged: (value) {
                      projectVm.setExportFormat(value);
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Resolution', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: projectVm.exportResolutionNotifier,
                builder: (context, selectedResolution, _) {
                  return ShadSelect<String>(
                    initialValue: selectedResolution,
                    placeholder: const Text('Select resolution'),
                    options: const [
                      ShadOption(
                        value: '1080p',
                        child: Text('1080p (1920x1080)'),
                      ),
                      ShadOption(
                        value: '720p',
                        child: Text('720p (1280x720)'),
                      ),
                      ShadOption(
                        value: '4k',
                        child: Text('4K (3840x2160)'),
                      ),
                      ShadOption(
                        value: 'custom',
                        child: Text('Custom...'),
                      ),
                    ],
                    selectedOptionBuilder: (context, value) => Text(value),
                    onChanged: (value) {
                      projectVm.setExportResolution(value);
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Output Location', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: projectVm.exportPathNotifier,
                      builder: (context, path, _) {
                        return ShadInput(
                          controller: TextEditingController(text: path),
                          readOnly: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
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
            ],
          ),
          const SizedBox(height: 24),
          ShadButton(
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
