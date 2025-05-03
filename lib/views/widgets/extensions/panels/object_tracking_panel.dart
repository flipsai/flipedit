import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for object tracking functionality
class ObjectTrackingPanel extends StatelessWidget with WatchItMixin {
  const ObjectTrackingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Object Tracking',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('Track and follow objects across frames.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Tracking Method',
            child: ComboBox<String>(
              placeholder: const Text('Select method'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'point',
                  child: Text('Point Tracking'),
                ),
                ComboBoxItem<String>(
                  value: 'object',
                  child: Text('Object Tracking'),
                ),
                ComboBoxItem<String>(
                  value: 'mask',
                  child: Text('Mask Tracking'),
                ),
              ],
              onChanged: (value) {
                // Handle method selection
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tracked Objects',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[50]),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(child: Text('No objects tracked yet')),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Button(
                child: const Text('Start Tracking'),
                onPressed: () {
                  // Handle start tracking
                },
              ),
              const SizedBox(width: 8),
              Button(
                child: const Icon(FluentIcons.add),
                onPressed: () {
                  // Handle add tracking point
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
