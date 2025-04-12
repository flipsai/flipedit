import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// Container that displays the content of a selected extension
/// Similar to VS Code's sidebar panels
class ExtensionPanelContainer extends StatefulWidget {
  final String selectedExtension;

  const ExtensionPanelContainer({super.key, required this.selectedExtension});

  @override
  State<ExtensionPanelContainer> createState() => _ExtensionPanelContainerState();
}

class _ExtensionPanelContainerState extends State<ExtensionPanelContainer> {
  late Future<List<ClipModel>> _itemsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItemsForExtension(widget.selectedExtension);
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text;
      });
    });
  }

  @override
  void didUpdateWidget(covariant ExtensionPanelContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedExtension != oldWidget.selectedExtension) {
      setState(() {
        _itemsFuture = _loadItemsForExtension(widget.selectedExtension);
        _searchController.clear();
        _searchTerm = '';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<ClipModel>> _loadItemsForExtension(String extensionType) async {
    print('Loading items for extension: $extensionType');
    await Future.delayed(const Duration(milliseconds: 100));

    switch (extensionType) {
      case 'video':
        return [
          _createDummyClip('Video 1.mp4', ClipType.video, durationFrames: 150),
          _createDummyClip('Tutorial Clip.mov', ClipType.video, durationFrames: 300),
          _createDummyClip('Animation.avi', ClipType.video, durationFrames: 90),
        ];
      case 'audio':
        return [
          _createDummyClip('Music Track.mp3', ClipType.audio, durationFrames: 600),
          _createDummyClip('Voiceover.wav', ClipType.audio, durationFrames: 200),
        ];
      case 'image':
        return [
          _createDummyClip('Background.jpg', ClipType.image, durationFrames: 120),
          _createDummyClip('Logo.png', ClipType.image, durationFrames: 120),
        ];
      case 'text':
        return [
          _createDummyClip('Title Card', ClipType.text, durationFrames: 90),
          _createDummyClip('Lower Third', ClipType.text, durationFrames: 150),
        ];
      case 'effect':
        return [
          _createDummyClip('Blur Effect', ClipType.effect, durationFrames: 0),
          _createDummyClip('Fade In/Out', ClipType.effect, durationFrames: 0),
        ];
      default:
        return [];
    }
  }

  ClipModel _createDummyClip(String name, ClipType type, {int durationFrames = 150}) {
    String dummyPath = '/path/to/${name.replaceAll(' ', '_')}';
    if(type == ClipType.video) dummyPath = 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

    final int durationMs = ClipModel.framesToMs(durationFrames);

    return ClipModel(
      databaseId: null,
      trackId: 0,
      name: name,
      type: type,
      sourcePath: dummyPath,
      startTimeInSourceMs: 0,
      endTimeInSourceMs: durationMs,
      startTimeOnTrackMs: 0,
    );
  }

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextBox(
            controller: _searchController,
            placeholder: 'Search ${widget.selectedExtension}...',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8.0),
              child: Icon(FluentIcons.search, size: 14),
            ),
            suffixMode: OverlayVisibilityMode.editing,
            suffix: IconButton(
              icon: const Icon(FluentIcons.clear, size: 12),
              onPressed: _searchController.clear,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ClipModel>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: ProgressRing());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error loading items: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No items found'));
              }

              final items = snapshot.data!;
              final filteredItems = items.where((item) => item.name.toLowerCase().contains(_searchTerm.toLowerCase())).toList();

              return ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final clip = filteredItems[index];
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

  String _getExtensionTitle() {
    switch (widget.selectedExtension) {
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
        return widget.selectedExtension.toUpperCase();
    }
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
