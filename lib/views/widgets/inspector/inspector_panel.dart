import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/inspector/effect_tree.dart';
import 'package:watch_it/watch_it.dart';

/// Inspector panel to display and edit properties of selected clips and effects
/// Similar to VS Code's property panel
class InspectorPanel extends StatelessWidget with WatchItMixin {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it's data binding to observe the selectedClipId property
    final selectedClipId = watchValue(
      (EditorViewModel vm) => vm.selectedClipIdNotifier,
    );

    return Container(
      color: theme.resources.controlFillColorDefault,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          if (selectedClipId != null)
            Expanded(
              child: _buildSelectedClipInspector(context, selectedClipId),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  'Select a clip to view properties',
                  style: TextStyle(
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.resources.subtleFillColorTertiary,
      child: Row(
        children: [
          Text(
            'PROPERTIES',
            style: theme.typography.caption?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              FluentIcons.chrome_close,
              size: 12,
              color: theme.resources.textFillColorSecondary,
            ),
            onPressed: () {
              di<EditorViewModel>().toggleInspector();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedClipInspector(BuildContext context, String clipId) {
    // Use watchValue to observe the clips property
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);

    final selectedClip = clips.firstWhere(
      (clip) => clip.id == clipId,
      orElse:
          () => Clip(
            id: '',
            name: '',
            type: ClipType.video,
            filePath: '',
            startFrame: 0,
            durationFrames: 0,
            trackIndex: 0,
          ),
    );

    if (selectedClip.id.isEmpty) {
      return const Center(child: Text('Clip not found'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedClip.name,
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const SizedBox(height: 4),
            Text(
              'Type: ${selectedClip.type.toString().split('.').last}',
              style: FluentTheme.of(context).typography.caption?.copyWith(
                color: FluentTheme.of(context).resources.textFillColorSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Basic properties section
            _buildSection(
              context: context,
              title: 'Basic Properties',
              children: [
                _buildTextField(
                  context: context,
                  label: 'Name',
                  value: selectedClip.name,
                  onChanged: (value) {
                    // Update clip name
                  },
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  context: context,
                  label: 'Start Frame',
                  value: selectedClip.startFrame.toString(),
                  onChanged: (value) {
                    // Update start frame
                  },
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  context: context,
                  label: 'Duration (frames)',
                  value: selectedClip.durationFrames.toString(),
                  onChanged: (value) {
                    // Update duration
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Effects section
            _buildSection(
              context: context,
              title: 'Effects',
              children: [
                _buildEffectsTree(selectedClip),
                const SizedBox(height: 8),
                Button(
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.add, size: 12),
                      SizedBox(width: 4),
                      Text('Add Effect'),
                    ],
                  ),
                  onPressed: () {
                    // Show add effect dialog
                  },
                ),
              ],
            ),

            // Type-specific properties
            const SizedBox(height: 16),
            _buildTypeSpecificProperties(context, selectedClip),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: FluentTheme.of(context).typography.bodyStrong),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    final theme = FluentTheme.of(context);
    final controller = TextEditingController(text: value);

    // Add listener to controller to handle changes
    controller.addListener(() {
      onChanged(controller.text);
    });

    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: theme.typography.body)),
        Expanded(child: TextBox(placeholder: label, controller: controller)),
      ],
    );
  }

  Widget _buildEffectsTree(Clip clip) {
    final effects = clip.effects;

    return EffectTree(
      effects: effects,
      onEffectSelected: (effect) {
        // Handle effect selection
      },
    );
  }

  Widget _buildTypeSpecificProperties(BuildContext context, Clip clip) {
    switch (clip.type) {
      case ClipType.video:
        return _buildSection(
          context: context,
          title: 'Video Properties',
          children: [
            _buildTextField(
              context: context,
              label: 'Playback Speed',
              value: '1.0',
              onChanged: (value) {
                // Update playback speed
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(
                  width: 100,
                  child: Text('Volume', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: 0.8,
                    onChanged: (value) {
                      // Update volume
                    },
                  ),
                ),
              ],
            ),
          ],
        );

      case ClipType.audio:
        return _buildSection(
          context: context,
          title: 'Audio Properties',
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 100,
                  child: Text('Volume', style: TextStyle(fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: 0.8,
                    onChanged: (value) {
                      // Update volume
                    },
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return Container();
    }
  }
}
