import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/project_asset.dart' as model;
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/services/media_import_service.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'dart:developer' as developer;
import 'package:flutter/material.dart' as material;

const _logTag = 'ClipsListPanel';

/// Panel for displaying project assets in the media tab
class MediasListPanel extends StatelessWidget with WatchItMixin {
  final String selectedExtension;
  final TextEditingController searchController;
  final ValueNotifier<String> searchTermNotifier;

  const MediasListPanel({
    super.key,
    required this.selectedExtension,
    required this.searchController,
    required this.searchTermNotifier,
  });

  @override
  Widget build(BuildContext context) {
    // Watch ProjectViewModel for project assets
    final assets = watchValue((ProjectViewModel vm) => vm.projectAssetsNotifier);
    final projectVm = di<ProjectViewModel>();
    final mediaImportService = MediaImportService(projectVm);
    
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
                      searchTermNotifier.value = '';
                    },
                  )
                : null,
            onChanged: (value) {
              searchTermNotifier.value = value;
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
                          // Show loading indicator
                          final loadingOverlay = MediaImportService.showLoadingOverlay(
                            context, 
                            'Selecting file...'
                          );
                          
                          try {
                            // Use the service to import media
                            final importSuccess = await mediaImportService.importMediaFromFilePicker(context);
                            
                            // Remove loading overlay
                            loadingOverlay.remove();
                            
                            // Show success/failure notification
                            if (importSuccess) {
                              MediaImportService.showNotification(
                                context,
                                'Media imported successfully',
                                severity: InfoBarSeverity.success
                              );
                            } else {
                              MediaImportService.showNotification(
                                context,
                                'Failed to import media',
                                severity: InfoBarSeverity.error
                              );
                            }
                          } catch (e) {
                            // Remove loading overlay if an error occurs
                            loadingOverlay.remove();
                            
                            MediaImportService.showNotification(
                              context,
                              'Error importing media: ${e.toString()}',
                              severity: InfoBarSeverity.error
                            );
                            
                            logError(_logTag, "Unexpected error in import flow: $e");
                          }
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
  
  // Display a progress ring indicator
  OverlayEntry displayProgressRing(BuildContext context) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProgressRing(),
              SizedBox(height: 16),
              Text('Selecting file...'),
            ],
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
    return entry;
  }
  
  // Display a progress dialog
  OverlayEntry displayProgressDialog(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProgressRing(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
    return entry;
  }
  
  // Show a snackbar message
  void showSnackbar(BuildContext context, String message, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: Text(message),
        severity: severity,
        onClose: close,
      );
    });
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