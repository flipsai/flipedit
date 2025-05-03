import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/utils/constants.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

class ProjectSettingsPanel extends StatefulWidget with WatchItStatefulWidgetMixin {
  const ProjectSettingsPanel({Key? key}) : super(key: key);

  @override
  _ProjectSettingsPanelState createState() => _ProjectSettingsPanelState();
}

class _ProjectSettingsPanelState extends State<ProjectSettingsPanel> {
  final String _logTag = 'ProjectSettingsPanel';
  
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  
  @override
  void initState() {
    super.initState();
    
    final canvasDimensionsService = di<CanvasDimensionsService>();
    _widthController = TextEditingController(
      text: canvasDimensionsService.canvasWidth.toInt().toString(),
    );
    _heightController = TextEditingController(
      text: canvasDimensionsService.canvasHeight.toInt().toString(),
    );
  }
  
  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvasDimensionsService = di<CanvasDimensionsService>();
    final theme = FluentTheme.of(context);
    
    // Get the current dimensions
    final canvasWidth = canvasDimensionsService.canvasWidth;
    final canvasHeight = canvasDimensionsService.canvasHeight;
    
    // Update controllers if they don't match current values
    if (_widthController.text != canvasWidth.toInt().toString()) {
      _widthController.text = canvasWidth.toInt().toString();
    }
    if (_heightController.text != canvasHeight.toInt().toString()) {
      _heightController.text = canvasHeight.toInt().toString();
    }
    
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Project Settings'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.reset),
              label: const Text('Reset to Default'),
              onPressed: () {
                canvasDimensionsService.resetToDefaults();
                setState(() {
                  _widthController.text = canvasDimensionsService.canvasWidth.toInt().toString();
                  _heightController.text = canvasDimensionsService.canvasHeight.toInt().toString();
                });
                logger.logInfo('Reset dimensions to default values', _logTag);
              },
            ),
          ],
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project dimensions section
            Text(
              'Project Canvas Dimensions',
              style: theme.typography.subtitle,
            ),
            const SizedBox(height: 8),
            Text(
              'Set the dimensions for your project canvas. This affects preview rendering and effects processing.',
              style: theme.typography.body,
            ),
            const SizedBox(height: 16),
            
            // Current dimensions display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.resources.cardBackgroundFillColorSecondary,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.resources.controlStrokeColorDefault,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.video,
                    color: theme.accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: theme.typography.body,
                        children: [
                          const TextSpan(text: 'Current dimensions: '),
                          TextSpan(
                            text: '${canvasWidth.toInt()} × ${canvasHeight.toInt()} px',
                            style: theme.typography.bodyStrong,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Dimensions input
            Row(
              children: [
                Expanded(
                  child: InfoLabel(
                    label: 'Width (pixels)',
                    child: NumberBox<int>(
                      value: canvasWidth.toInt(),
                      mode: SpinButtonPlacementMode.inline,
                      min: 320,
                      max: 7680, // 8K
                      onChanged: (value) {
                        if (value != null && value > 0) {
                          canvasDimensionsService.canvasWidth = value.toDouble();
                          _widthController.text = value.toString();
                          logger.logInfo('Canvas width updated to $value px', _logTag);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InfoLabel(
                    label: 'Height (pixels)',
                    child: NumberBox<int>(
                      value: canvasHeight.toInt(),
                      mode: SpinButtonPlacementMode.inline,
                      min: 240,
                      max: 4320, // 8K
                      onChanged: (value) {
                        if (value != null && value > 0) {
                          canvasDimensionsService.canvasHeight = value.toDouble();
                          _heightController.text = value.toString();
                          logger.logInfo('Canvas height updated to $value px', _logTag);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Preset buttons
            InfoLabel(
              label: 'Common Presets',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PresetButton(
                      label: 'HD (1280×720)',
                      width: 1280,
                      height: 720,
                      onPressed: _updateDimensions,
                    ),
                    _PresetButton(
                      label: 'Full HD (1920×1080)',
                      width: 1920,
                      height: 1080,
                      onPressed: _updateDimensions,
                    ),
                    _PresetButton(
                      label: '2K (2560×1440)',
                      width: 2560,
                      height: 1440,
                      onPressed: _updateDimensions,
                    ),
                    _PresetButton(
                      label: '4K (3840×2160)',
                      width: 3840,
                      height: 2160,
                      onPressed: _updateDimensions,
                    ),
                    _PresetButton(
                      label: 'Square (1080×1080)',
                      width: 1080,
                      height: 1080,
                      onPressed: _updateDimensions,
                    ),
                    _PresetButton(
                      label: 'Instagram (1080×1350)',
                      width: 1080,
                      height: 1350,
                      onPressed: _updateDimensions,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _updateDimensions(int width, int height) {
    final canvasDimensionsService = di<CanvasDimensionsService>();
    canvasDimensionsService.updateCanvasDimensions(width.toDouble(), height.toDouble());
    setState(() {
      _widthController.text = width.toString();
      _heightController.text = height.toString();
    });
    logger.logInfo('Updated dimensions to preset: ${width}x$height', _logTag);
  }
}

// Helper widget for dimension presets
class _PresetButton extends StatelessWidget {
  final String label;
  final int width;
  final int height;
  final Function(int width, int height) onPressed;

  const _PresetButton({
    required this.label,
    required this.width,
    required this.height,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      style: ButtonStyle(
        padding: ButtonState.all(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: () => onPressed(width, height),
    );
  }
} 