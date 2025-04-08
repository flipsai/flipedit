import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/effect_type.dart';
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
    // Use watch_it's data binding to observe the selectedClipId property
    final selectedClipId = watchValue((EditorViewModel vm) => vm.selectedClipIdNotifier);
    
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
    // Use watchValue to observe the clips property
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    
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
            const SizedBox(height: 4),
            Text(
              'Type: ${selectedClip.type.toString().split('.').last}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            
            // Basic properties section
            _buildSection(
              title: 'Basic Properties',
              children: [
                _buildTextField(
                  label: 'Name',
                  value: selectedClip.name,
                  onChanged: (value) {
                    // Update clip name
                  },
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  label: 'Start Frame',
                  value: selectedClip.startFrame.toString(),
                  onChanged: (value) {
                    // Update start frame
                  },
                ),
                const SizedBox(height: 8),
                _buildTextField(
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
            _buildTypeSpecificProperties(selectedClip),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
  
  Widget _buildTextField({
    required String label,
    required String value,
    required Function(String) onChanged,
  }) {
    final controller = TextEditingController(text: value);
    
    // Add listener to controller to handle changes
    controller.addListener(() {
      onChanged(controller.text);
    });
    
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(
          child: TextBox(
            placeholder: label,
            controller: controller,
          ),
        ),
      ],
    );
  }
  
  Widget _buildEffectsTree(Clip clip) {
    // In a real app, this would show the actual effects
    // For now, just show some dummy effects
    final dummyEffects = [
      Effect(
        id: '1', 
        name: 'Blur', 
        type: EffectType.filter, 
        parameters: {'radius': 5.0},
        startFrame: 0,
        durationFrames: 10,
      ),
      Effect(
        id: '2', 
        name: 'Color Correction', 
        type: EffectType.colorCorrection, 
        parameters: {
          'brightness': 1.2,
          'contrast': 1.1,
          'saturation': 1.0,
        },
        startFrame: 0,
        durationFrames: 10,
      ),
    ];
    
    return EffectTree(
      effects: dummyEffects,
      onEffectSelected: (effect) {
        // Handle effect selection
      },
    );
  }
  
  Widget _buildTypeSpecificProperties(Clip clip) {
    switch (clip.type) {
      case ClipType.video:
        return _buildSection(
          title: 'Video Properties',
          children: [
            _buildTextField(
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
                  child: Text(
                    'Volume',
                    style: TextStyle(fontSize: 12),
                  ),
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
          title: 'Audio Properties',
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 100,
                  child: Text(
                    'Volume',
                    style: TextStyle(fontSize: 12),
                  ),
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
