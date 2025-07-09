import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

class ProjectSettingsPanel extends StatefulWidget
    with WatchItStatefulWidgetMixin {
  const ProjectSettingsPanel({super.key});

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

    return Scaffold(
      backgroundColor: ShadTheme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Project Settings'),
        backgroundColor: ShadTheme.of(context).colorScheme.card,
        foregroundColor: ShadTheme.of(context).colorScheme.foreground,
        actions: [
          ShadButton(
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.rotateCcw),
                SizedBox(width: 8),
                Text('Reset to Default'),
              ],
            ),
            onPressed: () {
              canvasDimensionsService.resetToDefaults();
              setState(() {
                _widthController.text =
                    canvasDimensionsService.canvasWidth.toInt().toString();
                _heightController.text =
                    canvasDimensionsService.canvasHeight.toInt().toString();
              });
              logger.logInfo('Reset dimensions to default values', _logTag);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project dimensions section
            Text(
              'Project Canvas Dimensions',
              style: ShadTheme.of(context).textTheme.large.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Set the dimensions for your project canvas. This affects preview rendering and effects processing.',
              style: ShadTheme.of(context).textTheme.muted,
            ),
            const SizedBox(height: 16),

            // Current dimensions display
            ShadCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(LucideIcons.video, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: ShadTheme.of(context).textTheme.p,
                          children: [
                            const TextSpan(text: 'Current dimensions: '),
                            TextSpan(
                              text:
                                  '${canvasWidth.toInt()} × ${canvasHeight.toInt()} px',
                              style: ShadTheme.of(context).textTheme.p.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Dimensions input
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Width (pixels)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      ShadInput(
                        controller: _widthController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final intValue = int.tryParse(value);
                          if (intValue != null && intValue >= 320 && intValue <= 7680) {
                            canvasDimensionsService.canvasWidth = intValue.toDouble();
                            logger.logInfo(
                              'Canvas width updated to $intValue px',
                              _logTag,
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Height (pixels)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      ShadInput(
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final intValue = int.tryParse(value);
                          if (intValue != null && intValue >= 240 && intValue <= 4320) {
                            canvasDimensionsService.canvasHeight = intValue.toDouble();
                            logger.logInfo(
                              'Canvas height updated to $intValue px',
                              _logTag,
                            );
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Preset buttons
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Common Presets',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateDimensions(int width, int height) {
    final canvasDimensionsService = di<CanvasDimensionsService>();
    canvasDimensionsService.updateCanvasDimensions(
      width.toDouble(),
      height.toDouble(),
    );
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
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ShadButton(
      child: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () => onPressed(width, height),
    );
  }
}
