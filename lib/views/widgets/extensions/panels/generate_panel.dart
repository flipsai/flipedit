import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for AI content generation
class GeneratePanel extends StatelessWidget with WatchItMixin {
  const GeneratePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Generate Content',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('Create new content using AI.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Generation Type',
            child: ComboBox<String>(
              placeholder: const Text('Select type'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(value: 'image', child: Text('Image')),
                ComboBoxItem<String>(value: 'video', child: Text('Video')),
                ComboBoxItem<String>(value: 'audio', child: Text('Audio')),
              ],
              onChanged: (value) {
                // Handle type selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Prompt',
            child: TextBox(
              placeholder: 'Describe what you want to generate...',
              maxLines: 5,
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'ComfyUI Workflow',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    placeholder: 'No workflow selected',
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  child: const Text('Browse'),
                  onPressed: () {
                    // Handle browse workflow
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Generate'),
            onPressed: () {
              // Handle generate action
            },
          ),
        ],
      ),
    );
  }
} 