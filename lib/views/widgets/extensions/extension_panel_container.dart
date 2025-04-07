import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';

/// Container that displays the content of a selected extension
/// Similar to VS Code's sidebar panels
class ExtensionPanelContainer extends StatelessWidget {
  final String extensionId;
  
  const ExtensionPanelContainer({
    super.key,
    required this.extensionId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: const Color(0xFFF3F3F3),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _buildContent(),
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
          Expanded(
            child: Text(
              _getExtensionTitle(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.chrome_close, size: 12),
            onPressed: () {
              di<EditorViewModel>().selectExtension('');
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
        return const _MediaExtensionPanel();
      case 'backgroundRemoval':
        return const _BackgroundRemovalPanel();
      case 'track':
        return const _ObjectTrackingPanel();
      case 'generate':
        return const _GeneratePanel();
      case 'enhance':
        return const _EnhancePanel();
      case 'export':
        return const _ExportPanel();
      default:
        return Center(
          child: Text('$extensionId panel content'),
        );
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

class _MediaExtensionPanel extends StatelessWidget {
  const _MediaExtensionPanel();

  @override
  Widget build(BuildContext context) {
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
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              _buildMediaItem(
                title: 'Video 1.mp4',
                duration: '00:03:24',
                icon: FluentIcons.video,
              ),
              _buildMediaItem(
                title: 'Audio 1.mp3',
                duration: '00:02:30',
                icon: FluentIcons.music_in_collection,
              ),
              _buildMediaItem(
                title: 'Image 1.jpg',
                duration: '',
                icon: FluentIcons.photo2,
              ),
            ],
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
            onPressed: () {
              // Handle import
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaItem({
    required String title,
    required String duration,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontSize: 12)),
        subtitle: duration.isNotEmpty 
            ? Text(duration, style: const TextStyle(fontSize: 11)) 
            : null,
        onPressed: () {
          // Handle media item selection
        },
      ),
    );
  }
}

class _BackgroundRemovalPanel extends StatelessWidget {
  const _BackgroundRemovalPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remove Background',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text('Select a clip on the timeline to remove its background.'),
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
              border: Border.all(color: Colors.grey[50]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Text('No objects tracked yet'),
            ),
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
                ComboBoxItem<String>(
                  value: 'image',
                  child: Text('Image'),
                ),
                ComboBoxItem<String>(
                  value: 'video',
                  child: Text('Video'),
                ),
                ComboBoxItem<String>(
                  value: 'audio',
                  child: Text('Audio'),
                ),
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
          const Text(
            'Enhance',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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
                ComboBoxItem<String>(
                  value: 'mp4',
                  child: Text('MP4 (H.264)'),
                ),
                ComboBoxItem<String>(
                  value: 'mov',
                  child: Text('MOV (ProRes)'),
                ),
                ComboBoxItem<String>(
                  value: 'webm',
                  child: Text('WebM (VP9)'),
                ),
                ComboBoxItem<String>(
                  value: 'gif',
                  child: Text('GIF'),
                ),
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
                ComboBoxItem<String>(
                  value: 'custom',
                  child: Text('Custom...'),
                ),
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
