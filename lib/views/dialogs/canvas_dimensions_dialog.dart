import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/utils/constants.dart';
import 'package:watch_it/watch_it.dart';

/// Shows a dialog asking the user if they want to use the dimensions of the first clip for the canvas.
class CanvasDimensionsDialog extends StatelessWidget {
  final int clipWidth;
  final int clipHeight;
  final String _logTag = 'CanvasDimensionsDialog';
  
  const CanvasDimensionsDialog({
    super.key,
    required this.clipWidth,
    required this.clipHeight,
  });

  static Future<bool?> show(BuildContext context, int clipWidth, int clipHeight) async {
    logger.logInfo(
      'Showing canvas dimensions dialog for clip: ${clipWidth}x$clipHeight',
      'CanvasDimensionsDialog',
    );
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => CanvasDimensionsDialog(
        clipWidth: clipWidth,
        clipHeight: clipHeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canvasDimensionsService = di<CanvasDimensionsService>();
    final defaultWidth = AppConstants.defaultVideoWidth;
    final defaultHeight = AppConstants.defaultVideoHeight;
    
    // Get theme colors for consistent styling
    final FluentThemeData theme = FluentTheme.of(context);
    
    logger.logInfo(
      'Building dialog with canvas: ${canvasDimensionsService.canvasWidth.toInt()}x${canvasDimensionsService.canvasHeight.toInt()}, ' +
      'clip: ${clipWidth}x$clipHeight, default: ${defaultWidth}x$defaultHeight',
      _logTag,
    );
    
    return ContentDialog(
      title: Text(
        'Set Canvas Dimensions',
        style: theme.typography.title,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Do you want to set the canvas dimensions to match this clip?',
            style: theme.typography.body,
          ),
          const SizedBox(height: 16),
          InfoBar(
            title: const Text('Note:'),
            content: Text(
              'This affects preview rendering and how effects like OpenCV are applied.',
              style: theme.typography.caption,
            ),
            severity: InfoBarSeverity.info,
          ),
          const SizedBox(height: 16),
          
          // Dimensions display in a card-like container
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLabel(
                  label: 'Current Default Canvas',
                  child: Text(
                    '${defaultWidth}x$defaultHeight',
                    style: theme.typography.bodyStrong,
                  ),
                ),
                const SizedBox(height: 8),
                InfoLabel(
                  label: 'Current Canvas',
                  child: Text(
                    '${canvasDimensionsService.canvasWidth.toInt()} x ${canvasDimensionsService.canvasHeight.toInt()}',
                    style: theme.typography.bodyStrong,
                  ),
                ),
                const SizedBox(height: 8),
                InfoLabel(
                  label: 'Clip Dimensions',
                  child: Text(
                    '$clipWidth x $clipHeight',
                    style: theme.typography.bodyStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Cancel button
        Button(
          onPressed: () {
            logger.logInfo('User chose to keep default dimensions', _logTag);
            canvasDimensionsService.resetToDefaults();
            canvasDimensionsService.markUserPrompted();
            Navigator.of(context).pop(false);
          },
          style: ButtonStyle(
            padding: ButtonState.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          ),
          child: const Text('Keep Default Dimensions'),
        ),
        
        // Confirm button with accent color
        FilledButton(
          onPressed: () {
            logger.logInfo('User chose to use clip dimensions: ${clipWidth}x$clipHeight', _logTag);
            canvasDimensionsService.updateCanvasDimensions(
              clipWidth.toDouble(),
              clipHeight.toDouble(),
            );
            canvasDimensionsService.markUserPrompted();
            Navigator.of(context).pop(true);
          },
          style: ButtonStyle(
            padding: ButtonState.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          ),
          child: const Text('Use Clip Dimensions'),
        ),
      ],
    );
  }
} 