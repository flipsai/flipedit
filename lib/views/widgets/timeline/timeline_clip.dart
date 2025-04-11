import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;

/// A clip in the timeline track
class TimelineClip extends StatelessWidget with WatchItMixin {
  final Clip clip;
  final int trackIndex;
  final bool isDragging;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackIndex,
    this.isDragging = false,
  });

  // Define base colors for clip types (consider making these theme-dependent later)
  static const Map<ClipType, Color> _clipTypeColors = {
    ClipType.video: Color(0xFF264F78), // Blueish
    ClipType.audio: Color(0xFF498205), // Greenish
    ClipType.image: Color(0xFF8764B8), // Purplish
    ClipType.text: Color(0xFFC29008), // Yellowish/Orange
    ClipType.effect: Color(0xFFC50F1F), // Reddish
  };

  // Helper to get appropriate contrast color (white or black)
  Color _getContrastColor(Color backgroundColor) {
    // Calculate luminance
    final luminance =
        (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it's data binding to observe the selectedClipId property
    final selectedClipId = watchValue(
      (EditorViewModel vm) => vm.selectedClipIdNotifier,
    );
    final isSelected = selectedClipId == clip.id;

    // Get base color for clip type
    final baseClipColor =
        _clipTypeColors[clip.type] ?? Colors.grey; // Default grey
    // Adjust color based on theme brightness maybe? (Optional)
    // final clipColor = theme.brightness == Brightness.dark ? baseClipColor : baseClipColor.withOpacity(0.8);
    final clipColor = baseClipColor;
    final contrastColor = _getContrastColor(
      clipColor,
    ); // Color for text/icons on the clip

    // Use theme accent color for selection border
    final selectionBorderColor = theme.accentColor.normal;

    return GestureDetector(
      onTap: () {
        di<EditorViewModel>().selectedClipId = clip.id;
      },
      onHorizontalDragUpdate: (details) {
        // TODO: Implement clip dragging logic (horizontal only)
        // Convert details.delta.dx based on zoom from TimelineViewModel
        // Update clip.startFrame via EditorViewModel or TimelineViewModel
      },
      child: Container(
        // Add margin for spacing between clips
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          // Use lighter color and maybe less opacity when dragging
          color: isDragging ? clipColor.withOpacity(0.5) : clipColor,
          border: Border.all(
            // Use theme accent for selection, different color for dragging feedback
            color:
                isDragging
                    ? theme.accentColor.light
                    : (isSelected ? selectionBorderColor : Colors.transparent),
            width: isDragging ? 1 : (isSelected ? 2 : 1), // Adjust width
          ),
          borderRadius: BorderRadius.circular(4),
          // Add a subtle shadow for depth (optional)
          // boxShadow: kElevationToShadow[1],
        ),
        // Slightly reduce opacity of content when dragging maybe?
        child: Opacity(
          opacity: isDragging ? 0.8 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clip header with title
              Container(
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  // Slightly darker/lighter shade for header background
                  color: clipColor.withOpacity(0.8),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(
                      3,
                    ), // Match container radius slightly
                    topRight: Radius.circular(3),
                  ),
                ),
                child: Row(
                  // No need for min size, let it fill
                  children: [
                    Expanded(
                      // Allow title to take available space
                      child: Text(
                        clip.name,
                        // Use theme caption style with contrast color
                        style: theme.typography.caption?.copyWith(
                          color: contrastColor,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis, // Prevent overflow
                        maxLines: 1,
                      ),
                    ),
                    // Display duration at the end
                    Text(
                      '${clip.durationFrames}f',
                      // Use theme caption style with contrast color
                      style: theme.typography.caption?.copyWith(
                        color: contrastColor,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),

              // Clip content area
              Expanded(
                // Use ShapeBorderClipper for rounded corners on the bottom
                child: ClipPath(
                  clipper: const ShapeBorderClipper(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                  ),
                  child: _buildClipContent(clipColor, contrastColor, theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipContent(
    Color clipColor,
    Color contrastColor,
    FluentThemeData theme,
  ) {
    // Use a semi-transparent version of the contrast color for icons/content
    final contentColor = contrastColor.withOpacity(0.7);
    // Use a slightly transparent version of the base color for backgrounds
    final contentBackgroundColor = clipColor.withOpacity(0.6);

    switch (clip.type) {
      case ClipType.video:
        return Container(
          color: contentBackgroundColor,
          child: Center(
            child: Icon(FluentIcons.video, size: 16, color: contentColor),
          ),
        );

      case ClipType.audio:
        // Use CustomPaint for waveform
        return CustomPaint(
          painter: _AudioWaveformPainter(
            // Pass the content color for the waveform
            color: contentColor,
            // Pass clip hashcode for deterministic random waveform
            seed: clip.hashCode,
          ),
          child: Container(
            color: contentBackgroundColor.withOpacity(0.5),
          ), // Fainter background behind waveform
        );

      case ClipType.image:
        return Container(
          color: contentBackgroundColor,
          child: Center(
            child: Icon(FluentIcons.picture, size: 16, color: contentColor),
          ),
        );

      case ClipType.text:
        return Container(
          color: contentBackgroundColor,
          child: Center(
            child: Icon(
              FluentIcons.text_document,
              size: 16,
              color: contentColor,
            ),
          ),
        );

      case ClipType.effect:
        return Container(
          color: contentBackgroundColor,
          child: Center(
            child: Icon(FluentIcons.filter, size: 16, color: contentColor),
          ),
        );
    }
  }
}

/// Paints a simple audio waveform
class _AudioWaveformPainter extends CustomPainter {
  final Color color;
  final int seed;

  _AudioWaveformPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return; // Avoid painting on zero size
    }

    final paint =
        Paint()
          ..color = color
          ..strokeWidth =
              1.5 // Slightly thicker line
          ..style = PaintingStyle.stroke;

    final path = Path();
    final random = math.Random(seed); // Use the passed seed
    final waveHeight = size.height * 0.6; // Max height of waveform
    final middleY = size.height / 2;

    path.moveTo(0, middleY);

    const step = 3.0; // Draw line every 3 pixels
    for (double x = step; x < size.width; x += step) {
      final y = middleY + (random.nextDouble() * 2 - 1) * (waveHeight / 2);
      path.lineTo(x, y);
    }
    // Ensure path ends at the edge
    // path.lineTo(size.width, middleY);

    canvas.drawPath(path, paint);
  }

  // Repaint if color changes (though unlikely here)
  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
}

// Helper to get EditorViewModel instance (assuming watch_it/get_it setup)
EditorViewModel get _editorVm => di<EditorViewModel>();
// Ensure di is properly initialized in your app.
