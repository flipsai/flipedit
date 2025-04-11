import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show ReorderableListView;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/inspector/effect_tree.dart';
import 'dart:ui' as ui show Clip;

/// Inspector panel to display and edit properties of selected clips and effects
/// Similar to VS Code's property panel
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({super.key});

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final EditorViewModel editorVm = di<EditorViewModel>();
  final TimelineViewModel timelineVm = di<TimelineViewModel>();

  String? _selectedClipId;
  ClipModel? _selectedClip;

  @override
  void initState() {
    super.initState();
    _selectedClipId = editorVm.selectedClipId;
    _updateSelectedClip();
    editorVm.selectedClipIdNotifier.addListener(_handleSelectedClipChange);
    timelineVm.clipsNotifier.addListener(_updateSelectedClip);
  }

  @override
  void dispose() {
    editorVm.selectedClipIdNotifier.removeListener(_handleSelectedClipChange);
    timelineVm.clipsNotifier.removeListener(_updateSelectedClip);
    super.dispose();
  }

  void _handleSelectedClipChange() {
    if (mounted) {
      setState(() {
        _selectedClipId = editorVm.selectedClipId;
        _updateSelectedClip();
      });
    }
  }

  void _updateSelectedClip() {
    if (_selectedClipId == null) {
      if (mounted) {
        setState(() {
          _selectedClip = null;
        });
      }
      return;
    }
    try {
      ClipModel? foundClip;
      try {
        foundClip = timelineVm.clips.firstWhere(
          (clip) => clip.databaseId?.toString() == _selectedClipId,
        );
      } on StateError {
        foundClip = null;
      }

      if (mounted) {
        setState(() {
          _selectedClip = foundClip;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedClip = null;
        });
      }
      print("Error finding selected clip: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedClip = _selectedClip;

    if (selectedClip == null || selectedClip.databaseId == null) {
      return const Center(child: Text('No clip selected or clip not saved'));
    }

    return ScaffoldPage(
      content: ListView(
        children: [
          Text('Inspector: ${selectedClip.name}', style: FluentTheme.of(context).typography.subtitle),
          const SizedBox(height: 16),
          _buildCommonProperties(context, selectedClip),
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
        Text('Common Properties', style: FluentTheme.of(context).typography.bodyStrong),
        const SizedBox(height: 8),
        InfoLabel(
          label: 'Name:',
          child: Text(clip.name),
        ),
        InfoLabel(
          label: 'Source Path:',
          child: Text(clip.sourcePath),
        ),
        InfoLabel(
          label: 'Duration (ms):',
          child: Text('${clip.durationMs} ms'),
        ),
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
        Text('Type-Specific Properties', style: FluentTheme.of(context).typography.bodyStrong),
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
    return InfoLabel(label: 'Codec:', child: Text(clip.metadata['codec'] ?? 'N/A'));
  }

  Widget _buildAudioProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(label: 'Sample Rate:', child: Text(clip.metadata['sample_rate'] ?? 'N/A'));
  }

  Widget _buildImageProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(label: 'Resolution:', child: Text(clip.metadata['resolution'] ?? 'N/A'));
  }

  Widget _buildTextProperties(BuildContext context, ClipModel clip) {
    return InfoLabel(label: 'Font:', child: Text(clip.metadata['font'] ?? 'N/A'));
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
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: effects.length,
            itemBuilder: (context, index) {
              final effect = effects[index];
              return ListTile(
                key: ValueKey(effect.id),
                title: Text(effect.name),
                subtitle: Text(effect.type.toString().split('.').last),
                trailing: IconButton(
                  icon: const Icon(FluentIcons.delete),
                  onPressed: () {
                    print('Remove effect: ${effect.name}');
                  },
                ),
              );
            },
            onReorder: (oldIndex, newIndex) {
              print('Reorder effects: $oldIndex -> $newIndex');
            },
          ),
        const SizedBox(height: 8),
        Button(
          child: const Text('Add Effect'),
          onPressed: () {
            print('Add Effect button pressed');
          },
        ),
      ],
    );
  }
}
