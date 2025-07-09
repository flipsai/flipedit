import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enhancement Type', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ShadSelect<String>(
                placeholder: const Text('Select enhancement'),
                options: const [
                  ShadOption(
                    value: 'upscale',
                    child: Text('Upscale Resolution'),
                  ),
                  ShadOption(
                    value: 'denoise',
                    child: Text('Reduce Noise'),
                  ),
                  ShadOption(
                    value: 'frame',
                    child: Text('Frame Interpolation'),
                  ),
                  ShadOption(
                    value: 'color',
                    child: Text('Color Enhancement'),
                  ),
                ],
                selectedOptionBuilder: (context, value) => Text(value),
                onChanged: (value) {
                  // Handle enhancement selection
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Strength', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ShadSlider(
                min: 0,
                max: 100,
                initialValue: 50,
                onChanged: (value) {
                  // Handle strength change
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          ShadButton(
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
