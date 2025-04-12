import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/project_asset.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Panel for displaying project assets in the media tab
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
    // Watch ProjectViewModel for project assets
    final assets = watchValue((ProjectViewModel vm) => vm.projectAssetsNotifier);
    // Watch the notifier to trigger rebuilds
    watch(searchTermNotifier);
    // Get the value *after* watching
    final searchTerm = searchTermNotifier.value;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextBox(
            controller: searchController,
            // Adjust placeholder based on context if needed
            placeholder: 'Search ${selectedExtension == 'media' ? 'Project Media' : selectedExtension}...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(FluentIcons.search, size: 14),
            ),
            suffixMode: OverlayVisibilityMode.editing,
            suffix: IconButton(
              icon: const Icon(FluentIcons.clear, size: 12),
              onPressed: () {
                searchController.clear();
                searchTermNotifier.value = '';
              },
            ),
          ),
        ),
        Expanded(
          // Pass ProjectAsset list
          child: _buildClipsList(context, assets, searchTerm),
        ),
      ],
    );
  }

  // Update method to accept List<ProjectAsset>
  Widget _buildClipsList(
      BuildContext context, List<ProjectAsset> assets, String searchTerm) {
    if (assets.isEmpty) {
      return const Center(child: Text('No media imported yet'));
    }
    final filteredAssets = assets
        .where((asset) =>
            asset.name.toLowerCase().contains(searchTerm.toLowerCase()))
        .toList();

    if (filteredAssets.isEmpty) {
      return Center(
          child: Text(searchTerm.isEmpty
              ? 'No items found'
              : 'No matches found for "$searchTerm"'));
    }
    return ListView.builder(
      itemCount: filteredAssets.length,
      itemBuilder: (context, index) {
        final asset = filteredAssets[index];
        // Pass ProjectAsset to item builder
        return _buildClipListItem(context, asset);
      },
    );
  }

  // Update method to accept ProjectAsset
  Widget _buildClipListItem(BuildContext context, ProjectAsset asset) {
    final theme = FluentTheme.of(context);
    // Use durationMs from ProjectAsset
    final String durationString = asset.type == ClipType.image
        ? 'Image'
        : '${(asset.durationMs / 1000).toStringAsFixed(1)}s'; // Convert ms to s

    // Create a ClipModel *only* for dragging, representing the intent to add
    // This ClipModel won't have a trackId or startTimeOnTrackMs yet.
    final draggableClipData = ClipModel(
      databaseId: null, // No clip instance ID yet
      trackId: -1, // Indicate no track assigned
      name: asset.name,
      type: asset.type,
      sourcePath: asset.sourcePath,
      startTimeInSourceMs: 0, // Start from beginning by default
      endTimeInSourceMs: asset.durationMs, // Use full asset duration
      startTimeOnTrackMs: 0, // Will be set by drop target
    );

    return LongPressDraggable<ClipModel>(
      // Drag ClipModel data
      data: draggableClipData,
      feedback: Opacity(
        opacity: 0.7,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.accentColor.lighter,
            borderRadius: BorderRadius.circular(4),
            boxShadow: kElevationToShadow[4],
          ),
          child: Acrylic(
            child: Text(
              asset.name, // Display asset name
              style: theme.typography.body?.copyWith(color: Colors.black),
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        color: theme.resources.subtleFillColorSecondary,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: ListTile(
          title: Text(asset.name, style: TextStyle(color: theme.resources.textFillColorDisabled)),
          subtitle: Text(durationString, style: TextStyle(color: theme.resources.textFillColorDisabled)),
          leading: Icon(_getIconForClipType(asset.type), color: theme.resources.textFillColorDisabled),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: BoxDecoration(
          color: theme.resources.layerFillColorDefault,
          borderRadius: BorderRadius.circular(4),
        ),
        child: ListTile(
          title: Text(asset.name, style: theme.typography.bodyStrong),
          subtitle: Text(durationString, style: theme.typography.caption),
          leading: Icon(_getIconForClipType(asset.type)),
          onPressed: () {
            // TODO: Define behavior when an asset in the media list is clicked
            // Maybe select it for properties view?
            // For now, let's not link it to EditorViewModel's selectedClipId
            // as that refers to a Clip *instance* on the timeline.
            print("Selected project asset: ${asset.name}");
            // if (asset.databaseId != null) {
            //   di<EditorViewModel>().selectedClipId = asset.databaseId.toString();
            // }
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
        // Effects likely won't be ProjectAssets in this way
        return FluentIcons.settings;
      default:
        return FluentIcons.unknown;
    }
  }
} 