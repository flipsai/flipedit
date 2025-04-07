import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/inspector/effect_tree.dart';
import 'package:watch_it/watch_it.dart' hide di;

/// Inspector panel to display and edit properties of selected clips and effects
/// Similar to VS Code's property panel
class InspectorPanel extends StatelessWidget with WatchItMixin {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedClipId = watchPropertyValue((EditorViewModel vm) => vm.selectedClipId);
    
    return Container(
      color: const Color(0xFFF3F3F3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          if (selectedClipId != null)
            Expanded(child: _buildSelectedClipInspector(selectedClipId))
          else
            const Expanded(
              child: Center(
                child: Text(
                  'Select a clip to view properties',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFECECEC),
      child: Row(
        children: [
          const Text(
            'PROPERTIES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(FluentIcons.chrome_close, size: 12),
            onPressed: () {
              di<EditorViewModel>().toggleInspector();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedClipInspector(String clipId) {
    final timelineViewModel = di<TimelineViewModel>();
    final clips = timelineViewModel.clips;
    
    final selectedClip = clips.firstWhere(
      (clip) => clip.id == clipId,
      orElse: () => Clip(
        id: '',
        name: '',
        type: ClipType.video,
        filePath: '',
        startFrame: 0,
        durationFrames: 0,
      ),
    );
    
    if (selectedClip.id.isEmpty) {
      return const Center(
        child: Text('Clip not found'),
      );
    }
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedClip.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Type: ${selectedClip.type.displayName}',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            
            // Clip properties section
            const Text(
              'Clip Properties',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildPropertyRow(
              label: 'Start Frame',
              value: selectedClip.startFrame.toString(),
              onChanged: (value) {
                // Handle property change
                final newValue = int.tryParse(value);
                if (newValue != null) {
                  final updatedClip = selectedClip.copyWith(startFrame: newValue);
                  timelineViewModel.updateClip(clipId, updatedClip);
                }
              },
            ),
            _buildPropertyRow(
              label: 'Duration (frames)',
              value: selectedClip.durationFrames.toString(),
              onChanged: (value) {
                // Handle property change
                final newValue = int.tryParse(value);
                if (newValue != null) {
                  final updatedClip = selectedClip.copyWith(durationFrames: newValue);
                  timelineViewModel.updateClip(clipId, updatedClip);
                }
              },
            ),
            
            // Media properties section
            const SizedBox(height: 16),
            const Text(
              'Media Properties',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildPropertyRow(
              label: 'File',
              value: selectedClip.filePath,
              readOnly: true,
            ),
            
            // Effects section
            const SizedBox(height: 16),
            const Text(
              'Effects',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Effect tree
            EffectTree(
              effects: selectedClip.effects,
              onEffectSelected: (Effect effect) {
                // Handle effect selection
              },
            ),
            
            // Add effect button
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
      ),
    );
  }

  Widget _buildPropertyRow({
    required String label,
    required String value,
    bool readOnly = false,
    Function(String)? onChanged,
  }) {
    final controller = TextEditingController(text: value);
    if (onChanged != null) {
      controller.addListener(() {
        onChanged(controller.text);
      });
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: TextBox(
              placeholder: label,
              controller: controller,
              readOnly: readOnly,
            ),
          ),
        ],
      ),
    );
  }
}
