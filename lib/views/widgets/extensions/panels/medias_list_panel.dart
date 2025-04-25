import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart' as material;

const _logTag = 'ClipsListPanel';

/// Panel for displaying project assets in the media tab
class MediasListPanel extends StatelessWidget with WatchItMixin {
  final String selectedExtension;

  const MediasListPanel({
    super.key,
    required this.selectedExtension,
  });

  @override
  Widget build(BuildContext context) {
    // Watch ProjectViewModel for project assets and search term
    final assets = watchValue((ProjectViewModel vm) => vm.projectAssetsNotifier);
    final searchTerm = watchValue((ProjectViewModel vm) => vm.searchTermNotifier);
    final projectVm = di<ProjectViewModel>();

    // Create a new controller each build, initialized with current search term
    final searchController = TextEditingController(text: searchTerm);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextBox(
            controller: searchController,
            placeholder: 'Search media...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(FluentIcons.search),
            ),
            suffix: searchTerm.isNotEmpty
                ? IconButton(
                    icon: const Icon(FluentIcons.clear),
                    onPressed: () {
                      searchController.clear();
                      projectVm.setSearchTerm('');
                    },
                  )
                : null,
            onChanged: (value) {
              projectVm.setSearchTerm(value);
            },
          ),
        ),
        Expanded(
          child: assets.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No media imported yet'),
                      const SizedBox(height: 10),
                      Button(
                        child: const Text('Import Media'),
                        onPressed: () async {
                          await projectVm.importMediaWithUI(context);
                        },
                      ),
                    ],
                  ),
                )
              : _buildClipsList(context, assets, searchTerm),
        ),
      ],
    );
  }
  

  // Update method to accept List<model.ProjectAsset>
  Widget _buildClipsList(
      BuildContext context, List<model.ProjectAsset> assets, String searchTerm) {
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
        // Pass model.ProjectAsset to item builder
        return _buildClipListItem(context, asset);
      },
    );
  }

  // Update method to accept model.ProjectAsset
  Widget _buildClipListItem(BuildContext context, model.ProjectAsset asset) {
    final theme = FluentTheme.of(context);
    // Use durationMs from model.ProjectAsset
    final String durationString = asset.type == ClipType.image
        ? 'Image'
        : '${(asset.durationMs / 1000).toStringAsFixed(1)}s'; // Convert ms to s

    // Create a ClipModel *only* for dragging, representing the intent to add
    // This ClipModel won't have a trackId or startTimeOnTrackMs yet.
    // Create a ClipModel *only* for dragging, representing the intent to add.
    // This ClipModel needs all required fields, even if track times are temporary.
    final sourceDuration = asset.durationMs;
    final draggableClipData = ClipModel(
      databaseId: null, // No clip instance ID yet
      trackId: -1, // Indicate no track assigned
      name: asset.name,
      type: asset.type,
      sourcePath: asset.sourcePath,
      sourceDurationMs: sourceDuration, // Required: use asset's duration
      startTimeInSourceMs: 0, // Start from beginning by default
      endTimeInSourceMs: sourceDuration, // Use full asset duration
      startTimeOnTrackMs: 0, // Temporary value for drag data
      endTimeOnTrackMs: sourceDuration, // Required: Temporary value matching source duration
    );

    return Draggable<ClipModel>(
      // Drag ClipModel data
      data: draggableClipData,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Add onDragStarted callback to debug drag events
      onDragStarted: () {
        developer.log('🟢 Drag started for asset: ${asset.name}', name: 'MediasListPanel');
      },
      // Add onDragEnd callback to debug drag events
      onDragEnd: (details) {
        developer.log('🛑 Drag ended with velocity: ${details.velocity}', name: 'MediasListPanel');
        developer.log('🛑 Was it accepted: ${details.wasAccepted}', name: 'MediasListPanel');
      },
      onDragCompleted: () {
        developer.log('✅ Drag completed successfully for: ${asset.name}', name: 'MediasListPanel');
      },
      onDraggableCanceled: (velocity, offset) {
        developer.log('❌ Drag canceled at offset: $offset', name: 'MediasListPanel');
      },
      maxSimultaneousDrags: 1,
      affinity: Axis.horizontal,
      hitTestBehavior: HitTestBehavior.translucent,
      feedback: material.Material(
        elevation: 4.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.accentColor.lighter,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            asset.name, // Display asset name
            style: theme.typography.body?.copyWith(color: Colors.black),
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
            logInfo(_logTag, "Selected project asset: ${asset.name}");
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
    }
  }
} 