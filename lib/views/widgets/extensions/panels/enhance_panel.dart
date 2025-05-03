import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for enhancing media quality
class EnhancePanel extends StatelessWidget with WatchItMixin {
  const EnhancePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enhance', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Improve quality of selected media.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Enhancement Type',
            child: ComboBox<String>(
              placeholder: const Text('Select enhancement'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'upscale',
                  child: Text('Upscale Resolution'),
                ),
                ComboBoxItem<String>(
                  value: 'denoise',
                  child: Text('Reduce Noise'),
                ),
                ComboBoxItem<String>(
                  value: 'frame',
                  child: Text('Frame Interpolation'),
                ),
                ComboBoxItem<String>(
                  value: 'color',
                  child: Text('Color Enhancement'),
                ),
              ],
              onChanged: (value) {
                // Handle enhancement selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Strength',
            child: Slider(
              min: 0,
              max: 100,
              value: 50,
              onChanged: (value) {
                // Handle strength change
              },
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Apply Enhancement'),
            onPressed: () {
              // Handle apply action
            },
          ),
        ],
      ),
    );
  }
}
