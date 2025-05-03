import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart'
    show Flip; // Import for Flip enum

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
          // Add preview transform controls
          _buildPreviewTransform(context, selectedClip),
          const SizedBox(height: 16),
          _buildTypeSpecificProperties(context, selectedClip),
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

  Widget _buildPreviewTransform(BuildContext context, ClipModel clip) {
    final timelineViewModel = di<TimelineViewModel>();
    final previewRect =
        clip.previewRect ?? const Rect.fromLTWH(100, 100, 320, 180);
    final previewFlip = clip.previewFlip;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview Transform',
          style: FluentTheme.of(context).typography.bodyStrong,
        ),
        const SizedBox(height: 8),

        // Position controls
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: 'X Position:',
                child: NumberBox<double>(
                  value: previewRect.left,
                  min: 0,
                  max: 1200, // Reasonable max for 1280px preview width
                  onChanged: (value) {
                    if (value != null) {
                      timelineViewModel.updateClipPreviewRect(
                        clip.databaseId!,
                        Rect.fromLTWH(
                          value,
                          previewRect.top,
                          previewRect.width,
                          previewRect.height,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoLabel(
                label: 'Y Position:',
                child: NumberBox<double>(
                  value: previewRect.top,
                  min: 0,
                  max: 650, // Reasonable max for 720px preview height
                  onChanged: (value) {
                    if (value != null) {
                      timelineViewModel.updateClipPreviewRect(
                        clip.databaseId!,
                        Rect.fromLTWH(
                          previewRect.left,
                          value,
                          previewRect.width,
                          previewRect.height,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Size controls
        Row(
          children: [
            Expanded(
              child: InfoLabel(
                label: 'Width:',
                child: NumberBox<double>(
                  value: previewRect.width,
                  min: 10,
                  max: 1280,
                  onChanged: (value) {
                    if (value != null) {
                      timelineViewModel.updateClipPreviewRect(
                        clip.databaseId!,
                        Rect.fromLTWH(
                          previewRect.left,
                          previewRect.top,
                          value,
                          previewRect.height,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InfoLabel(
                label: 'Height:',
                child: NumberBox<double>(
                  value: previewRect.height,
                  min: 10,
                  max: 720,
                  onChanged: (value) {
                    if (value != null) {
                      timelineViewModel.updateClipPreviewRect(
                        clip.databaseId!,
                        Rect.fromLTWH(
                          previewRect.left,
                          previewRect.top,
                          previewRect.width,
                          value,
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Preset sizes for common aspect ratios
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Button(
              onPressed: () {
                timelineViewModel.updateClipPreviewRect(
                  clip.databaseId!,
                  Rect.fromLTWH(
                    previewRect.left,
                    previewRect.top,
                    320,
                    180, // 16:9
                  ),
                );
              },
              child: const Text('16:9'),
            ),
            Button(
              onPressed: () {
                timelineViewModel.updateClipPreviewRect(
                  clip.databaseId!,
                  Rect.fromLTWH(
                    previewRect.left,
                    previewRect.top,
                    240,
                    240, // 1:1
                  ),
                );
              },
              child: const Text('1:1'),
            ),
            Button(
              onPressed: () {
                timelineViewModel.updateClipPreviewRect(
                  clip.databaseId!,
                  Rect.fromLTWH(
                    previewRect.left,
                    previewRect.top,
                    270,
                    360, // 3:4
                  ),
                );
              },
              child: const Text('3:4'),
            ),
            Button(
              onPressed: () {
                timelineViewModel.updateClipPreviewRect(
                  clip.databaseId!,
                  Rect.fromLTWH(
                    previewRect.left,
                    previewRect.top,
                    360,
                    270, // 4:3
                  ),
                );
              },
              child: const Text('4:3'),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Flip controls
        InfoLabel(
          label: 'Flip:',
          child: ComboBox<Flip>(
            value: previewFlip,
            items: [
              ComboBoxItem<Flip>(value: Flip.none, child: const Text('None')),
              ComboBoxItem<Flip>(
                value: Flip.horizontal,
                child: const Text('Horizontal'),
              ),
              ComboBoxItem<Flip>(
                value: Flip.vertical,
                child: const Text('Vertical'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                timelineViewModel.updateClipPreviewFlip(
                  clip.databaseId!,
                  value,
                );
              }
            },
          ),
        ),

        const SizedBox(height: 12),

        // Center button
        Button(
          onPressed: () {
            // Center the clip in the preview (1280x720)
            final left = (1280 - previewRect.width) / 2;
            final top = (720 - previewRect.height) / 2;
            timelineViewModel.updateClipPreviewRect(
              clip.databaseId!,
              Rect.fromLTWH(left, top, previewRect.width, previewRect.height),
            );
          },
          child: const Text('Center in Preview'),
        ),
      ],
    );
  }
}
