import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generation Type', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ShadSelect<String>(
                placeholder: const Text('Select type'),
                options: const [
                  ShadOption(value: 'image', child: Text('Image')),
                  ShadOption(value: 'video', child: Text('Video')),
                  ShadOption(value: 'audio', child: Text('Audio')),
                ],
                selectedOptionBuilder: (context, value) => Text(value),
                onChanged: (value) {
                  // Handle type selection
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Prompt', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ShadInput(
                controller: TextEditingController(),
                placeholder: const Text('Describe what you want to generate...'),
                maxLines: 5,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ComfyUI Workflow', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: TextEditingController(text: 'No workflow selected'),
                      readOnly: true,
                      placeholder: const Text('No workflow selected'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    child: const Text('Browse'),
                    onPressed: () {
                      // Handle browse workflow
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          ShadButton(
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
