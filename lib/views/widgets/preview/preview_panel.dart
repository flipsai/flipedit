import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart'; // Import watch_it

import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Keep for frame number display

/// PreviewPanel displays the video stream received via the PreviewViewModel.
class PreviewPanel extends StatelessWidget with WatchItMixin {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch specific values from the PreviewViewModel
    final isConnected = watchValue(
      (PreviewViewModel vm) => vm.isConnectedNotifier,
    );
    final status = watchValue((PreviewViewModel vm) => vm.statusNotifier);
    final fps = watchValue((PreviewViewModel vm) => vm.fpsNotifier);
    final currentFrame = watchValue(
      (PreviewViewModel vm) => vm.currentFrameNotifier,
    );

    // Watch current frame number from TimelineNavigationViewModel
    final currentFrameNumber = watchValue(
      (TimelineNavigationViewModel vm) => vm.currentFrameNotifier,
    );

    final theme = FluentTheme.of(context);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Status bar using ViewModel state
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            color: isConnected ? Colors.green.lighter : Colors.red.lighter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Preview: $status'),
                Text('FPS: $fps'),
                Text(
                  'Frame: $currentFrameNumber',
                ), // Display current frame number
              ],
            ),
          ),

          // Video display area using ViewModel state
          Expanded(
            child: Container(
              color: Colors.black,
              child: LayoutBuilder(
                // Keep LayoutBuilder for sizing if needed by painter
                builder: (context, constraints) {
                  return Center(
                    child:
                        currentFrame != null
                            ? VideoFrameWidget(
                              image: currentFrame,
                            ) // Display frame from VM
                            : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const ProgressRing(),
                                const SizedBox(height: 10),
                                Text(
                                  status, // Show status from VM when no frame
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple widget to display the ui.Image using CustomPaint.
/// Assumes a VideoFramePainter exists to handle the actual painting.
class VideoFrameWidget extends StatelessWidget {
  final ui.Image image;

  const VideoFrameWidget({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      // Ensure the painter takes available space
      child: CustomPaint(painter: VideoFramePainter(image: image)),
    );
  }
}

/// CustomPainter to draw the video frame.
class VideoFramePainter extends CustomPainter {
  final ui.Image image;

  VideoFramePainter({required this.image});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate aspect ratios
    final double imageAspect = image.width / image.height;
    final double canvasAspect = size.width / size.height;

    Rect srcRect;
    Rect dstRect;

    // Fit the image within the canvas bounds, maintaining aspect ratio
    if (imageAspect > canvasAspect) {
      // Image is wider than canvas, fit width
      final double scale = size.width / image.width;
      final double scaledHeight = image.height * scale;
      final double dy = (size.height - scaledHeight) / 2.0;
      srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      dstRect = Rect.fromLTWH(0, dy, size.width, scaledHeight);
    } else {
      // Image is taller than canvas (or same aspect), fit height
      final double scale = size.height / image.height;
      final double scaledWidth = image.width * scale;
      final double dx = (size.width - scaledWidth) / 2.0;
      srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      dstRect = Rect.fromLTWH(dx, 0, scaledWidth, size.height);
    }

    // Draw the image
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  @override
  bool shouldRepaint(covariant VideoFramePainter oldDelegate) {
    // Repaint only if the image object itself changes
    return oldDelegate.image != image;
  }
}
