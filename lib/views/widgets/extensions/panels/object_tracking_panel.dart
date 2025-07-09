import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tracking Method', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ShadSelect<String>(
                placeholder: const Text('Select method'),
                options: const [
                  ShadOption(
                    value: 'point',
                    child: Text('Point Tracking'),
                  ),
                  ShadOption(
                    value: 'object',
                    child: Text('Object Tracking'),
                  ),
                  ShadOption(
                    value: 'mask',
                    child: Text('Mask Tracking'),
                  ),
                ],
                selectedOptionBuilder: (context, value) => Text(value),
                onChanged: (value) {
                  // Handle method selection
                },
              ),
            ],
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
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(child: Text('No objects tracked yet')),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ShadButton(
                child: const Text('Start Tracking'),
                onPressed: () {
                  // Handle start tracking
                },
              ),
              const SizedBox(width: 8),
              ShadButton(
                child: const Icon(LucideIcons.plus),
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
