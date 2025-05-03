import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for background removal functionality
class BackgroundRemovalPanel extends StatelessWidget with WatchItMixin {
  const BackgroundRemovalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remove Background', style: theme.typography.bodyStrong),
          const SizedBox(height: 16),
          Text(
            'Select a clip on the timeline to remove its background.',
            style: theme.typography.body,
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Model',
            child: ComboBox<String>(
              placeholder: const Text('Select model'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'basic',
                  child: Text('Basic (Fast)'),
                ),
                ComboBoxItem<String>(
                  value: 'advanced',
                  child: Text('Advanced (High Quality)'),
                ),
                ComboBoxItem<String>(
                  value: 'custom',
                  child: Text('Custom ComfyUI Workflow'),
                ),
              ],
              onChanged: (value) {
                // Handle model selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Threshold',
            child: Slider(
              min: 0,
              max: 100,
              value: 50,
              onChanged: (value) {
                // Handle threshold change
              },
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Apply'),
            onPressed: () {
              // Handle apply action
            },
          ),
        ],
      ),
    );
  }
}
