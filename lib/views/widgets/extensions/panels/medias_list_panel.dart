import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
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

  // Track tap position for context menu
  static Offset _tapPosition = Offset.zero;

  const MediasListPanel({super.key, required this.selectedExtension});

  @override
  Widget build(BuildContext context) {
    // Watch ProjectViewModel for project assets and search term
    final assets = watchValue(
      (ProjectViewModel vm) => vm.projectAssetsNotifier,
    );
    final searchTerm = watchValue(
      (ProjectViewModel vm) => vm.searchTermNotifier,
    );
    final projectVm = di<ProjectViewModel>();

    // Create a new controller each build, initialized with current search term
    final searchController = TextEditingController(text: searchTerm);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              const Icon(LucideIcons.search),
              const SizedBox(width: 8),
              Expanded(
                child: ShadInput(
                  controller: searchController,
                  placeholder: const Text('Search media...'),
                  onChanged: (value) {
                    projectVm.setSearchTerm(value);
                  },
                ),
              ),
              if (searchTerm.isNotEmpty)
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () {
                    searchController.clear();
                    projectVm.setSearchTerm('');
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child:
              assets.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('No media imported yet'),
                        const SizedBox(height: 10),
                        ElevatedButton(
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
    BuildContext context,
    List<model.ProjectAsset> assets,
    String searchTerm,
  ) {
    if (assets.isEmpty) {
      return const Center(child: Text('No media imported yet'));
    }
    final filteredAssets =
        assets
            .where(
              (asset) =>
                  asset.name.toLowerCase().contains(searchTerm.toLowerCase()),
            )
            .toList();

    if (filteredAssets.isEmpty) {
      return Center(
        child: Text(
          searchTerm.isEmpty
              ? 'No items found'
              : 'No matches found for "$searchTerm"',
        ),
      );
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
    final theme = ShadTheme.of(context);

    // Use durationMs from model.ProjectAsset
    final String durationString =
        asset.type == ClipType.image
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
      endTimeOnTrackMs:
          sourceDuration, // Required: Temporary value matching source duration
    );

    // Create the item widget content
    final itemContent = Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        borderRadius: BorderRadius.circular(4),
      ),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          _storePosition(details);
        },
        onSecondaryTap:
            asset.databaseId != null
                ? () {
                  _showMediaContextMenu(context, asset);
                }
                : null,
        child: ListTile(
          title: Text(asset.name, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.foreground)),
          subtitle: Text(durationString, style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground)),
          leading: Icon(_getIconForClipType(asset.type)),
          onTap: () {
            // TODO: Define behavior when an asset in the media list is clicked
            // Maybe select it for properties view?
            // For now, let's not link it to EditorViewModel's selectedClipId
            // as that refers to a Clip *instance* on the timeline.
            logInfo(_logTag, "Selected project asset: ${asset.name}");
          },
        ),
      ),
    );

    return Draggable<ClipModel>(
      // Drag ClipModel data
      data: draggableClipData,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Add onDragStarted callback to debug drag events
      onDragStarted: () {
        developer.log(
          '🟢 Drag started for asset: ${asset.name}',
          name: 'MediasListPanel',
        );
      },
      // Add onDragEnd callback to debug drag events
      onDragEnd: (details) {
        developer.log(
          '🛑 Drag ended with velocity: ${details.velocity}',
          name: 'MediasListPanel',
        );
        developer.log(
          '🛑 Was it accepted: ${details.wasAccepted}',
          name: 'MediasListPanel',
        );
      },
      onDragCompleted: () {
        developer.log(
          '✅ Drag completed successfully for: ${asset.name}',
          name: 'MediasListPanel',
        );
      },
      onDraggableCanceled: (velocity, offset) {
        developer.log(
          '❌ Drag canceled at offset: $offset',
          name: 'MediasListPanel',
        );
      },
      maxSimultaneousDrags: 1,
      affinity: Axis.horizontal,
      hitTestBehavior: HitTestBehavior.translucent,
      feedback: material.Material(
        elevation: 4.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            asset.name, // Display asset name
            style: TextStyle(color: theme.colorScheme.foreground),
          ),
        ),
      ),
      childWhenDragging: Container(
        color: theme.colorScheme.muted,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: ListTile(
          title: Text(
            asset.name,
            style: TextStyle(color: theme.colorScheme.mutedForeground),
          ),
          subtitle: Text(
            durationString,
            style: TextStyle(color: theme.colorScheme.mutedForeground),
          ),
          leading: Icon(
            _getIconForClipType(asset.type),
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
      child: itemContent,
    );
  }

  void _showMediaContextMenu(BuildContext context, model.ProjectAsset asset) {
    final theme = ShadTheme.of(context);

    // Get the current position of the mouse cursor
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = material.RelativeRect.fromRect(
      _tapPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    material.showMenu(
      context: context,
      position: position,
      items: [
        material.PopupMenuItem(
          child: Row(
            children: [
              Icon(
                LucideIcons.trash,
                color: theme.colorScheme.foreground,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Delete',
                style: TextStyle(color: theme.colorScheme.foreground),
              ),
            ],
          ),
          onTap: () async {
            // Show confirmation dialog
            Future.delayed(const Duration(milliseconds: 50), () async {
              await showDialog(
                context: context,
                builder:
                    (context) => AlertDialog(
                      title: const Text('Delete Media'),
                      content: Text(
                        'Are you sure you want to delete "${asset.name}"?\n\nThis will also remove any clips using this media from the timeline.',
                      ),
                      actions: [
                        ShadButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        ShadButton(
                          backgroundColor: Colors.red,
                          child: const Text('Delete'),
                          onPressed: () async {
                            Navigator.pop(context);
                            if (asset.databaseId != null) {
                              // Delete the asset using the project service
                              final projectVm = di<ProjectViewModel>();
                              final success = await projectVm
                                  .deleteAssetCommand(asset.databaseId!);
                              if (success) {
                                _showNotification(
                                  context,
                                  'Media and associated timeline clips have been deleted',
                                  isSuccess: true,
                                );
                              } else {
                                _showNotification(
                                  context,
                                  'Failed to delete media',
                                  isSuccess: false,
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
              );
            });
          },
        ),
      ],
    );
  }

  void _showNotification(
    BuildContext context,
    String message, {
    bool isSuccess = true,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Update the tap position when the user right-clicks
  void _storePosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  IconData _getIconForClipType(ClipType type) {
    switch (type) {
      case ClipType.video:
        return LucideIcons.video;
      case ClipType.audio:
        return LucideIcons.volume2;
      case ClipType.image:
        return LucideIcons.image;
      case ClipType.text:
        return LucideIcons.type;
      case ClipType.effect:
        // Effects likely won't be ProjectAssets in this way
        return LucideIcons.settings;
    }
  }
}
