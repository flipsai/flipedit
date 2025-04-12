import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/foundation.dart';

/// Panel for displaying clips in the media and composition tabs
class ClipsListPanel extends StatelessWidget with WatchItMixin {
  final String selectedExtension;
  final TextEditingController searchController;
  final ValueNotifier<String> searchTermNotifier;

  const ClipsListPanel({
    super.key, 
    required this.selectedExtension,
    required this.searchController,
    required this.searchTermNotifier,
  });

  @override
  Widget build(BuildContext context) {
    // Watch the clips from the TimelineViewModel
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final searchTerm = searchTermNotifier.value;
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextBox(
            controller: searchController,
            placeholder: 'Search $selectedExtension...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(FluentIcons.search, size: 14),
            ),
            suffixMode: OverlayVisibilityMode.editing,
            suffix: IconButton(
              icon: const Icon(FluentIcons.clear, size: 12),
              onPressed: searchController.clear,
            ),
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (clips.isEmpty) {
                return const Center(child: Text('No items found'));
              }

              // Filter clips based on search term
              final filteredClips = clips.where(
                (clip) => clip.name.toLowerCase().contains(searchTerm.toLowerCase())
              ).toList();

              if (filteredClips.isEmpty) {
                return const Center(child: Text('No matches found'));
              }

              return ListView.builder(
                itemCount: filteredClips.length,
                itemBuilder: (context, index) {
                  final clip = filteredClips[index];
                  return _buildClipListItem(context, clip);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClipListItem(BuildContext context, ClipModel clip) {
    final theme = FluentTheme.of(context);
    final timelineViewModel = di<TimelineViewModel>();

    final String durationString = clip.type == ClipType.image
        ? 'Image (Default Duration)'
        : '${(clip.durationFrames / 30).toStringAsFixed(1)}s';

    final draggableClip = clip.copyWith();

    return LongPressDraggable<ClipModel>(
      data: draggableClip,
      feedback: Acrylic(
        elevation: 4.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.accentColor.lighter,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            clip.name,
            style: theme.typography.body?.copyWith(color: theme.activeColor),
          ),
        ),
      ),
      childWhenDragging: Container(
        color: theme.resources.subtleFillColorSecondary,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: ListTile(
          title: Text(clip.name, style: TextStyle(color: theme.resources.textFillColorDisabled)),
          subtitle: Text(durationString, style: TextStyle(color: theme.resources.textFillColorDisabled)),
          leading: Icon(_getIconForClipType(clip.type), color: theme.resources.textFillColorDisabled),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: BoxDecoration(
          color: theme.resources.layerFillColorDefault,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListTile(
          title: Text(clip.name, style: theme.typography.bodyStrong),
          subtitle: Text(durationString, style: theme.typography.caption),
          leading: Icon(_getIconForClipType(clip.type)),
          onPressed: () {
            di<EditorViewModel>().selectedClipId = clip.databaseId?.toString();
          },
        ),
      ),
    );
  }

  IconData _getIconForClipType(ClipType type) {
    switch (type) {
      case ClipType.video:
        return FluentIcons.video;
      case ClipType.audio:
        return FluentIcons.volume3;
      case ClipType.image:
        return FluentIcons.photo2;
      case ClipType.text:
        return FluentIcons.font;
      case ClipType.effect:
        return FluentIcons.settings;
      default:
        return FluentIcons.unknown;
    }
  }
} 