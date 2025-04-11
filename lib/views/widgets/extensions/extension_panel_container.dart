import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/screens/settings_screen.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/material.dart' show Material, pointerDragAnchorStrategy;

/// Container that displays the content of a selected extension
/// Similar to VS Code's sidebar panels
class ExtensionPanelContainer extends StatelessWidget {
  final String extensionId;

  const ExtensionPanelContainer({super.key, required this.extensionId});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      width: 300,
      color: theme.resources.controlFillColorDefault,
      child: Column(
        children: [_buildHeader(context), Expanded(child: _buildContent())],
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
          Expanded(
            child: Text(
              _getExtensionTitle(),
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              FluentIcons.chrome_close,
              size: 12,
              color: theme.resources.textFillColorSecondary,
            ),
            onPressed: () {
              di<EditorViewModel>().selectedExtension = '';
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // This would be more dynamic in a real app, loading the appropriate extension UI
    switch (extensionId) {
      case 'media':
        return _MediaExtensionPanel();
      case 'backgroundRemoval':
        return _BackgroundRemovalPanel();
      case 'track':
        return _ObjectTrackingPanel();
      case 'generate':
        return _GeneratePanel();
      case 'enhance':
        return _EnhancePanel();
      case 'export':
        return _ExportPanel();
      case 'settings':
        return const SettingsScreen();
      default:
        return Center(child: Text('$extensionId panel content'));
    }
  }

  String _getExtensionTitle() {
    switch (extensionId) {
      case 'media':
        return 'MEDIA';
      case 'composition':
        return 'COMPOSITION';
      case 'backgroundRemoval':
        return 'BACKGROUND REMOVAL';
      case 'replace':
        return 'REPLACE';
      case 'track':
        return 'OBJECT TRACKING';
      case 'addFx':
        return 'ADD FX';
      case 'generate':
        return 'GENERATE';
      case 'enhance':
        return 'ENHANCE';
      case 'export':
        return 'EXPORT';
      case 'settings':
        return 'SETTINGS';
      default:
        return extensionId.toUpperCase();
    }
  }
}

// Make _MediaExtensionPanel reactive using WatchItBuilder
class _MediaExtensionPanel extends WatchingWidget {
  const _MediaExtensionPanel();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Access the view model and watch the project media list
    final projectMedia = watchValue((EditorViewModel vm) => vm.projectMediaNotifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextBox(
            placeholder: 'Search media...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(FluentIcons.search, size: 16),
            ),
            // TODO: Implement search filtering
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Text(
            'Drag media items to add them to the timeline',
            style: theme.typography.caption?.copyWith(
              color: theme.resources.textFillColorSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: projectMedia.length,
            itemBuilder: (context, index) {
              final clip = projectMedia[index];
              return _buildMediaItem(
                context: context,
                clip: clip, // Pass the actual clip
                // Remove static title, duration, icon
              );
            },
            // Old static ListView:
            // children: <Widget>[
            //   _buildMediaItem(
            //     context: context,
            //     title: 'Video 1.mp4',
            //     duration: '00:03:24',
            //     icon: FluentIcons.video,
            //   ),
            //   _buildMediaItem(
            //     context: context,
            //     title: 'Audio 1.mp3',
            //     duration: '00:02:30',
            //     icon: FluentIcons.music_in_collection,
            //   ),
            //   _buildMediaItem(
            //     context: context,
            //     title: 'Image 1.jpg',
            //     duration: '',
            //     icon: FluentIcons.photo2,
            //   ),
            // ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: FilledButton(
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.add, size: 12),
                SizedBox(width: 4),
                Text('Import Media'),
              ],
            ),
            onPressed: () async {
              // Handle import
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.media, // Allow video, audio, images
                allowMultiple: true,
              );

              if (result != null) {
                final editorViewModel = di<EditorViewModel>();
                for (var file in result.files) {
                  if (file.path != null) {
                    final clip = _createClipFromFile(file);
                    if (clip != null) {
                      // TODO: Add clip to project media pool instead of directly to timeline
                      editorViewModel.addClip(clip);
                    }
                  }
                }
              }
            },
          ),
        ),
      ],
    );
  }

  // Updated _buildMediaItem to accept a Clip object
  Widget _buildMediaItem({
    required BuildContext context,
    required Clip clip, // Now takes a Clip object
    // Removed title, duration, icon parameters
  }) {
    final theme = FluentTheme.of(context);
    // Determine icon based on clip type
    IconData icon;
    switch (clip.type) {
      case ClipType.video:
        icon = FluentIcons.video;
        break;
      case ClipType.audio:
        icon = FluentIcons.music_in_collection;
        break;
      case ClipType.image:
        icon = FluentIcons.photo2;
        break;
      default:
        icon = FluentIcons.unknown; // Default case
    }

    // TODO: Format duration properly based on clip.durationFrames and project FPS
    final String durationString = clip.type == ClipType.image
        ? '' // Images don't have a duration in the same way
        : '${(clip.durationFrames / 30).toStringAsFixed(1)}s'; // Placeholder duration display (assuming 30fps)

    // Create a copy of the clip for dragging to avoid modifying the original in the pool
    final draggableClip = clip.copyWith(); 

    return Draggable<Clip>(
      // Data is the clip to be dragged
      data: draggableClip,
      // Center the feedback at the cursor position
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // What is shown when dragging
      feedback: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(4.0),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.accentColor.light,
            borderRadius: BorderRadius.circular(4.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                clip.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      // What is shown at the original position during dragging
      childWhenDragging: Container(
        margin: const EdgeInsets.only(bottom: 4.0),
        decoration: BoxDecoration(
          color: theme.resources.subtleFillColorSecondary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(4.0),
          border: Border.all(color: theme.accentColor.lightest, width: 1),
        ),
        child: ListTile(
          leading: Icon(icon, color: theme.resources.textFillColorSecondary),
          title: Text(
            clip.name,
            style: theme.typography.body?.copyWith(
              color: theme.resources.textFillColorSecondary,
            ),
          ),
          subtitle:
              durationString.isNotEmpty
                  ? Text(
                    durationString,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  )
                  : null,
        ),
      ),
      // Set cursor to 'grabbing' when dragging starts
      onDragStarted: () {},
      // The container that stays in place when dragging
      child: Container(
        margin: const EdgeInsets.only(bottom: 4.0),
        decoration: BoxDecoration(
          color: theme.resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: ListTile(
          leading: Icon(icon, color: theme.resources.textFillColorPrimary),
          title: Text(clip.name, style: theme.typography.body), // Use clip name
          subtitle:
              durationString.isNotEmpty
                  ? Text(durationString, style: theme.typography.caption) // Use calculated duration string
                  : null,
          trailing: Icon(
            FluentIcons.move,
            size: 16,
            color: theme.resources.textFillColorSecondary,
          ),
          onPressed: () {
            // Handle media item selection (e.g., select in preview or show properties)
            di<EditorViewModel>().selectedClipId = clip.id;
          },
        ),
      ),
    );
  }

  // Helper function to determine ClipType from file extension
  ClipType? _getClipTypeFromPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(extension)) {
      return ClipType.video;
    } else if (['mp3', 'wav', 'aac', 'flac', 'ogg'].contains(extension)) {
      return ClipType.audio;
    } else if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
      return ClipType.image;
    }
    return null; // Unknown type
  }

  // Helper function to create a Clip object from a PlatformFile
  Clip? _createClipFromFile(PlatformFile file) {
    if (file.path == null) return null;

    final clipType = _getClipTypeFromPath(file.path!);
    if (clipType == null) return null; // Skip unknown file types

    // TODO: Get actual duration for video/audio files
    // This requires a media processing library (e.g., ffmpeg_kit_flutter)
    final int durationFrames = clipType == ClipType.image
        ? 90 // Default duration for images (e.g., 3 seconds at 30fps)
        : 150; // Placeholder duration for video/audio

    final int trackIndex = clipType == ClipType.audio ? 1 : 0; // Default track

    return Clip(
      id: DateTime.now().millisecondsSinceEpoch.toString() + file.name, // Basic unique ID
      name: file.name,
      type: clipType,
      filePath: file.path!,
      startFrame: 0,
      durationFrames: durationFrames,
      trackIndex: trackIndex,
    );
  }
}

class _BackgroundRemovalPanel extends StatelessWidget {
  const _BackgroundRemovalPanel();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remove Background', style: theme.typography.bodyStrong),
          const SizedBox(height: 16),
          Text(
            'Select a clip on the timeline to remove its background.',
            style: theme.typography.body,
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Model',
            child: ComboBox<String>(
              placeholder: const Text('Select model'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'basic',
                  child: Text('Basic (Fast)'),
                ),
                ComboBoxItem<String>(
                  value: 'advanced',
                  child: Text('Advanced (High Quality)'),
                ),
                ComboBoxItem<String>(
                  value: 'custom',
                  child: Text('Custom ComfyUI Workflow'),
                ),
              ],
              onChanged: (value) {
                // Handle model selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Threshold',
            child: Slider(
              min: 0,
              max: 100,
              value: 50,
              onChanged: (value) {
                // Handle threshold change
              },
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Apply'),
            onPressed: () {
              // Handle apply action
            },
          ),
        ],
      ),
    );
  }
}

class _ObjectTrackingPanel extends StatelessWidget {
  const _ObjectTrackingPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Object Tracking',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('Track and follow objects across frames.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Tracking Method',
            child: ComboBox<String>(
              placeholder: const Text('Select method'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'point',
                  child: Text('Point Tracking'),
                ),
                ComboBoxItem<String>(
                  value: 'object',
                  child: Text('Object Tracking'),
                ),
                ComboBoxItem<String>(
                  value: 'mask',
                  child: Text('Mask Tracking'),
                ),
              ],
              onChanged: (value) {
                // Handle method selection
              },
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tracked Objects',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey[50]),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(child: Text('No objects tracked yet')),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Button(
                child: const Text('Start Tracking'),
                onPressed: () {
                  // Handle start tracking
                },
              ),
              const SizedBox(width: 8),
              Button(
                child: const Icon(FluentIcons.add),
                onPressed: () {
                  // Handle add tracking point
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratePanel extends StatelessWidget {
  const _GeneratePanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Generate Content',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('Create new content using AI.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Generation Type',
            child: ComboBox<String>(
              placeholder: const Text('Select type'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(value: 'image', child: Text('Image')),
                ComboBoxItem<String>(value: 'video', child: Text('Video')),
                ComboBoxItem<String>(value: 'audio', child: Text('Audio')),
              ],
              onChanged: (value) {
                // Handle type selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Prompt',
            child: TextBox(
              placeholder: 'Describe what you want to generate...',
              maxLines: 5,
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'ComfyUI Workflow',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    placeholder: 'No workflow selected',
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  child: const Text('Browse'),
                  onPressed: () {
                    // Handle browse workflow
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Generate'),
            onPressed: () {
              // Handle generate action
            },
          ),
        ],
      ),
    );
  }
}

class _EnhancePanel extends StatelessWidget {
  const _EnhancePanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enhance', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Improve quality of selected media.'),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Enhancement Type',
            child: ComboBox<String>(
              placeholder: const Text('Select enhancement'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: 'upscale',
                  child: Text('Upscale Resolution'),
                ),
                ComboBoxItem<String>(
                  value: 'denoise',
                  child: Text('Reduce Noise'),
                ),
                ComboBoxItem<String>(
                  value: 'frame',
                  child: Text('Frame Interpolation'),
                ),
                ComboBoxItem<String>(
                  value: 'color',
                  child: Text('Color Enhancement'),
                ),
              ],
              onChanged: (value) {
                // Handle enhancement selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Strength',
            child: Slider(
              min: 0,
              max: 100,
              value: 50,
              onChanged: (value) {
                // Handle strength change
              },
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Apply Enhancement'),
            onPressed: () {
              // Handle apply action
            },
          ),
        ],
      ),
    );
  }
}

class _ExportPanel extends StatelessWidget {
  const _ExportPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Project',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Format',
            child: ComboBox<String>(
              placeholder: const Text('Select format'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(value: 'mp4', child: Text('MP4 (H.264)')),
                ComboBoxItem<String>(value: 'mov', child: Text('MOV (ProRes)')),
                ComboBoxItem<String>(value: 'webm', child: Text('WebM (VP9)')),
                ComboBoxItem<String>(value: 'gif', child: Text('GIF')),
              ],
              onChanged: (value) {
                // Handle format selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Resolution',
            child: ComboBox<String>(
              placeholder: const Text('Select resolution'),
              isExpanded: true,
              items: const [
                ComboBoxItem<String>(
                  value: '1080p',
                  child: Text('1080p (1920x1080)'),
                ),
                ComboBoxItem<String>(
                  value: '720p',
                  child: Text('720p (1280x720)'),
                ),
                ComboBoxItem<String>(
                  value: '4k',
                  child: Text('4K (3840x2160)'),
                ),
                ComboBoxItem<String>(value: 'custom', child: Text('Custom...')),
              ],
              onChanged: (value) {
                // Handle resolution selection
              },
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Output Location',
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    placeholder: 'Select output folder...',
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  child: const Text('Browse'),
                  onPressed: () {
                    // Handle browse location
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Button(
            child: const Text('Export'),
            onPressed: () {
              // Handle export action
            },
          ),
        ],
      ),
    );
  }
}
