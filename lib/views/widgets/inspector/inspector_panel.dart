import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'dart:ui' show Rect;

/// Inspector panel using WatchItMixin for reactive updates
class InspectorPanel extends StatelessWidget with WatchItMixin {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the selected clip ID
    final selectedClipId = watchValue(
      (EditorViewModel vm) => vm.selectedClipIdNotifier,
    );
    // Watch the list of clips to find the selected one
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);

    ClipModel? selectedClip;
    if (selectedClipId != null) {
      try {
        // Use firstWhere without orElse, catch StateError if not found
        selectedClip = clips.firstWhere(
          (clip) => clip.databaseId?.toString() == selectedClipId,
        );
      } on StateError {
        // Not found exception - expected if ID doesn't match any clip
        selectedClip = null;
      } catch (e) {
        // Catch any other potential errors during search
        logError(
          runtimeType.toString(),
          "Error finding selected clip in build: $e",
        );
        selectedClip = null;
      }
    }

    // Display message if no clip is selected or found
    if (selectedClip == null || selectedClip.databaseId == null) {
      return const Center(
        child: Text('No clip selected or clip data unavailable'),
      );
    }

    // Build the UI using the found selectedClip
    return ScaffoldPage(
      padding: const EdgeInsets.all(12), // Add some padding
      content: ListView(
        children: [
          Text(
            'Inspector: ${selectedClip.name}',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          const SizedBox(height: 16),
          _buildCommonProperties(context, selectedClip),
          const SizedBox(height: 16),
          _buildTypeSpecificProperties(context, selectedClip),
          const SizedBox(height: 16),
          _buildPositionAndSizeSection(context, selectedClip),
          const SizedBox(height: 16),
          _buildEffectsSection(context, selectedClip),
        ],
      ),
    );
  }

  Widget _buildCommonProperties(BuildContext context, ClipModel clip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Common Properties',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 8),
        InfoLabel(label: 'Name:', child: Text(clip.name)),
        InfoLabel(
          label: 'Source Path:',
          child: Text(clip.sourcePath, overflow: TextOverflow.ellipsis),
        ),
        InfoLabel(
          label: 'Duration (Track ms):',
          child: Text('${clip.durationOnTrackMs} ms'),
        ), // Use durationOnTrackMs
        InfoLabel(
          label: 'Duration (Frames):',
          child: Text('${clip.durationFrames} frames'),
        ),
        InfoLabel(
          label: 'Start Time (Track):',
          child: Text('${clip.startTimeOnTrackMs} ms'),
        ),
        InfoLabel(
          label: 'Trim Start (Source):',
          child: Text('${clip.startTimeInSourceMs} ms'),
        ),
        InfoLabel(
          label: 'Trim End (Source):',
          child: Text('${clip.endTimeInSourceMs} ms'),
        ),
      ],
    );
  }

  Widget _buildTypeSpecificProperties(BuildContext context, ClipModel clip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type-Specific Properties',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 8),
        switch (clip.type) {
          ClipType.video => _buildVideoProperties(context, clip),
          ClipType.audio => _buildAudioProperties(context, clip),
          ClipType.image => _buildImageProperties(context, clip),
          ClipType.text => _buildTextProperties(context, clip),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  Widget _buildVideoProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(
      label: 'Codec:',
      child: Text(clip.metadata['codec'] ?? 'N/A'),
    );
  }

  Widget _buildAudioProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(
      label: 'Sample Rate:',
      child: Text(clip.metadata['sample_rate'] ?? 'N/A'),
    );
  }

  Widget _buildImageProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(
      label: 'Resolution:',
      child: Text(clip.metadata['resolution'] ?? 'N/A'),
    );
  }

  Widget _buildTextProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(
      label: 'Font:',
      child: Text(clip.metadata['font'] ?? 'N/A'),
    );
  }

  Widget _buildPositionAndSizeSection(BuildContext context, ClipModel clip) {
    final timelineVm = di<TimelineViewModel>();
    
    // Get current rect values from the clip, or use defaults
    final Rect currentRect = clip.previewRect ?? 
        const Rect.fromLTWH(0, 0, 1280, 720);
    
    // Create controllers with initial values from currentRect
    final xController = TextEditingController(text: currentRect.left.toStringAsFixed(0));
    final yController = TextEditingController(text: currentRect.top.toStringAsFixed(0));
    final widthController = TextEditingController(text: currentRect.width.toStringAsFixed(0));
    final heightController = TextEditingController(text: currentRect.height.toStringAsFixed(0));

    // Feedback for update success/failure
    final ValueNotifier<String?> feedbackNotifier = ValueNotifier(null);

    // Function to update the preview rect when any value changes
    void updatePreviewRect() {
      try {
        final double x = double.parse(xController.text);
        final double y = double.parse(yController.text);
        final double width = double.parse(widthController.text);
        final double height = double.parse(heightController.text);
        
        // Create a new rect with the updated values
        final newRect = Rect.fromLTWH(x, y, width, height);
        
        // Only update if values have actually changed
        if (newRect != currentRect) {
          timelineVm.updateClipPreviewRect(clip.databaseId!, newRect)
            .then((_) {
              // Success feedback
              feedbackNotifier.value = 'Updated position and size';
              Future.delayed(const Duration(seconds: 2), () {
                if (feedbackNotifier.value == 'Updated position and size') {
                  feedbackNotifier.value = null;
                }
              });
            })
            .catchError((e) {
              // Error feedback
              feedbackNotifier.value = 'Error: $e';
              Future.delayed(const Duration(seconds: 3), () {
                if (feedbackNotifier.value?.startsWith('Error:') ?? false) {
                  feedbackNotifier.value = null;
                }
              });
            });
        }
      } catch (e) {
        logError(
          runtimeType.toString(),
          "Error updating preview rect: $e", 
        );
        // Show error feedback in UI
        feedbackNotifier.value = 'Error: Invalid number format';
        Future.delayed(const Duration(seconds: 3), () {
          feedbackNotifier.value = null;
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Position and Size',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 8),
        InfoBar(
          title: const Text('These values control how the clip appears in the preview.'),
          severity: InfoBarSeverity.info,
        ),
        const SizedBox(height: 8),
        
        // Show feedback if available
        ValueListenableBuilder<String?>(
          valueListenable: feedbackNotifier,
          builder: (context, feedback, _) {
            if (feedback == null) return const SizedBox.shrink();
            
            final isError = feedback.startsWith('Error:');
            return InfoBar(
              title: Text(feedback),
              severity: isError ? InfoBarSeverity.error : InfoBarSeverity.success,
            );
          },
        ),
        
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: 'X Position:',
                child: NumberBox(
                  value: currentRect.left,
                  onChanged: (value) {
                    if (value != null) {
                      xController.text = value.toStringAsFixed(0);
                      updatePreviewRect();
                    }
                  },
                  mode: SpinButtonPlacementMode.inline,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoLabel(
                label: 'Y Position:',
                child: NumberBox(
                  value: currentRect.top,
                  onChanged: (value) {
                    if (value != null) {
                      yController.text = value.toStringAsFixed(0);
                      updatePreviewRect();
                    }
                  },
                  mode: SpinButtonPlacementMode.inline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: 'Width:',
                child: NumberBox(
                  value: currentRect.width,
                  onChanged: (value) {
                    if (value != null) {
                      widthController.text = value.toStringAsFixed(0);
                      updatePreviewRect();
                    }
                  },
                  mode: SpinButtonPlacementMode.inline,
                  min: 1, // Prevent negative or zero width
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoLabel(
                label: 'Height:',
                child: NumberBox(
                  value: currentRect.height,
                  onChanged: (value) {
                    if (value != null) {
                      heightController.text = value.toStringAsFixed(0);
                      updatePreviewRect();
                    }
                  },
                  mode: SpinButtonPlacementMode.inline,
                  min: 1, // Prevent negative or zero height
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Button(
          child: const Text('Reset to Default'),
          onPressed: () {
            // Default full canvas at center (assuming 1280x720 canvas)
            const defaultRect = Rect.fromLTWH(0, 0, 1280, 720);
            xController.text = defaultRect.left.toStringAsFixed(0);
            yController.text = defaultRect.top.toStringAsFixed(0);
            widthController.text = defaultRect.width.toStringAsFixed(0);
            heightController.text = defaultRect.height.toStringAsFixed(0);
            timelineVm.updateClipPreviewRect(clip.databaseId!, defaultRect);
          },
        ),
      ],
    );
  }

  Widget _buildEffectsSection(BuildContext context, ClipModel clip) {
    final effects = clip.effects;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Effects', style: FluentTheme.of(context).typography.bodyStrong),
        const SizedBox(height: 8),
        if (effects.isEmpty)
          const Text('No effects applied.')
        else
          // Note: ReorderableListView might need state management if complex interactions are added
          // For simple display and delete, this is okay in StatelessWidget
          ListView.builder(
            // Using ListView.builder instead of Reorderable for simplicity here
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: effects.length,
            itemBuilder: (context, index) {
              final effect = effects[index];
              return ListTile(
                key: ValueKey(effect.id), // Ensure effects have unique IDs
                title: Text(effect.name),
                subtitle: Text(effect.type.toString().split('.').last),
                trailing: IconButton(
                  icon: const Icon(FluentIcons.delete), // Consider styling
                  onPressed: () {
                    // TODO: Implement effect removal via ViewModel
                    logInfo(
                      runtimeType.toString(),
                      'Remove effect: ${effect.name} (ID: ${effect.id})',
                    );
                    // Example: timelineVm.removeEffectFromClip(clip.databaseId!, effect.id);
                  },
                ),
              );
            },
            // onReorder callback removed as we switched to ListView.builder
          ),
        const SizedBox(height: 8),
        Button(
          child: const Text('Add Effect'),
          onPressed: () {
            // TODO: Implement add effect functionality (e.g., show a dialog)
            logInfo(
              runtimeType.toString(),
              'Add Effect button pressed for clip: ${clip.databaseId}',
            );
          },
        ),
      ],
    );
  }
}
