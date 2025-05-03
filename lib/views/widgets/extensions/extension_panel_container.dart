import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/panels/panels.dart';
import 'package:watch_it/watch_it.dart';

/// Container that displays the content of a selected extension
/// Similar to VS Code's sidebar panels
class ExtensionPanelContainer extends StatelessWidget with WatchItMixin {
  final String selectedExtension;
  final TextEditingController _searchController = TextEditingController();

  ExtensionPanelContainer({super.key, required this.selectedExtension}) {
    _searchController.addListener(() {
      // No longer managing search term locally
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      width: 300,
      color: theme.resources.controlFillColorDefault,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildContent(context)),
        ],
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

  Widget _buildContent(BuildContext context) {
    // Show different content based on the selected extension
    switch (selectedExtension) {
      case 'backgroundRemoval':
        return const BackgroundRemovalPanel();
      case 'track':
        return const ObjectTrackingPanel();
      case 'generate':
        return const GeneratePanel();
      case 'enhance':
        return const EnhancePanel();
      case 'export':
        return const ExportPanel();
      case 'settings':
        return const ProjectSettingsPanel();
      case 'media':
      case 'composition':
      default:
        // For media and composition tabs, show the clips list
        return MediasListPanel(selectedExtension: selectedExtension);
    }
  }

  String _getExtensionTitle() {
    switch (selectedExtension) {
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
        return selectedExtension.toUpperCase();
    }
  }
}
