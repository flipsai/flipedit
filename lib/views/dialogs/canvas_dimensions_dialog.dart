import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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

  static Future<bool?> show(
    BuildContext context,
    int clipWidth,
    int clipHeight,
  ) async {
    logger.logInfo(
      'Showing canvas dimensions dialog for clip: ${clipWidth}x$clipHeight',
      'CanvasDimensionsDialog',
    );

    return await showShadDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder:
          (context) => CanvasDimensionsDialog(
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
    final ShadThemeData theme = ShadTheme.of(context);

    logger.logInfo(
      'Building dialog with canvas: ${canvasDimensionsService.canvasWidth.toInt()}x${canvasDimensionsService.canvasHeight.toInt()}, '
      'clip: ${clipWidth}x$clipHeight, default: ${defaultWidth}x$defaultHeight',
      _logTag,
    );

    return ShadDialog(
      title: Text('Set Canvas Dimensions'),
      description: Text('Do you want to set the canvas dimensions to match this clip?'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.border,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Note:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'This affects preview rendering and how effects like OpenCV are applied.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dimensions display in a card-like container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.card,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.border,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Default Canvas',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
                    ),
                    Text(
                      '${defaultWidth}x$defaultHeight',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Canvas',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
                    ),
                    Text(
                      '${canvasDimensionsService.canvasWidth.toInt()} x ${canvasDimensionsService.canvasHeight.toInt()}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clip Dimensions',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.mutedForeground),
                    ),
                    Text(
                      '$clipWidth x $clipHeight',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Cancel button
        ShadButton.outline(
          onPressed: () {
            logger.logInfo('User chose to keep default dimensions', _logTag);
            canvasDimensionsService.resetToDefaults();
            canvasDimensionsService.markUserPrompted();
            Navigator.of(context).pop(false);
          },
          child: const Text('Keep Default Dimensions'),
        ),

        // Confirm button with accent color
        ShadButton(
          onPressed: () {
            logger.logInfo(
              'User chose to use clip dimensions: ${clipWidth}x$clipHeight',
              _logTag,
            );
            canvasDimensionsService.updateCanvasDimensions(
              clipWidth.toDouble(),
              clipHeight.toDouble(),
            );
            canvasDimensionsService.markUserPrompted();
            Navigator.of(context).pop(true);
          },
          child: const Text('Use Clip Dimensions'),
        ),
      ],
    );
  }
}
