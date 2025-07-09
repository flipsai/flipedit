import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for background removal functionality
class BackgroundRemovalPanel extends StatelessWidget with WatchItMixin {
  const BackgroundRemovalPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remove Background', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(
            'Select a clip on the timeline to remove its background.',
            style: TextStyle(color: theme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Model', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Select model (ComboBox placeholder)'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Threshold', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Slider(
                min: 0,
                max: 100,
                value: 50,
                onChanged: (value) {
                  // Handle threshold change
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
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
