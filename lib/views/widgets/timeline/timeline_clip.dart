import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;
import 'package:flipedit/utils/logger.dart';

/// A clip in the timeline track
class TimelineClip extends StatefulWidget with WatchItStatefulWidgetMixin {
  final ClipModel clip;
  final int trackIndex;
  final bool isDragging;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackIndex,
    this.isDragging = false,
  });

  @override
  State<TimelineClip> createState() => _TimelineClipState();
}

class _TimelineClipState extends State<TimelineClip> {
  // Track dragging state
  bool _isDragging = false;
  double _dragStartX = 0;
  int _originalStartFrame = 0;
  int _currentDragFrame = 0; // Track current drag position for smooth preview
  
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
    
    // Get view models
    final editorVm = di<EditorViewModel>();
    final timelineVm = di<TimelineViewModel>();
    
    // Use watchValue here in the State's build method
    final selectedClipId = watchValue((EditorViewModel vm) => vm.selectedClipIdNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    final isSelected = selectedClipId == widget.clip.databaseId?.toString();
    
    // Calculate the visual offset for smooth dragging preview
    final double dragOffset = _isDragging 
        ? (_currentDragFrame - widget.clip.startFrame) * 5.0 * zoom
        : 0.0;

    // Get base color for clip type
    final baseClipColor =
        _clipTypeColors[widget.clip.type] ?? Colors.grey; // Default grey
    final clipColor = baseClipColor;
    final contrastColor = _getContrastColor(
      clipColor,
    ); // Color for text/icons on the clip

    // Use theme accent color for selection border
    final selectionBorderColor = theme.accentColor.normal;

    return Transform.translate(
      offset: Offset(dragOffset, 0), // Apply the drag offset for smooth visual movement
      child: GestureDetector(
        onTap: () {
          // Use databaseId for selection
          editorVm.selectedClipId = widget.clip.databaseId?.toString();
        },
        onHorizontalDragStart: (details) {
          setState(() {
            _isDragging = true;
            _dragStartX = details.localPosition.dx;
            _originalStartFrame = widget.clip.startFrame;
            _currentDragFrame = _originalStartFrame;
          });
          // Select the clip when starting to drag using databaseId
          editorVm.selectedClipId = widget.clip.databaseId?.toString();
        },
        onHorizontalDragUpdate: (details) {
          if (!_isDragging) return;
          
          // Calculate frame movement based on horizontal drag distance and zoom
          final pixelsPerFrame = 5.0 * zoom; // Use watched zoom
          final dragDeltaInFrames = (details.localPosition.dx - _dragStartX) ~/ pixelsPerFrame;
          
          // Calculate new start frame
          final newStartFrame = _originalStartFrame + dragDeltaInFrames;
          
          // Clamp to prevent negative frames
          final clampedStartFrame = newStartFrame < 0 ? 0 : newStartFrame;
          
          // Update the visual state for smooth drag preview
          if (_currentDragFrame != clampedStartFrame) {
            setState(() {
              _currentDragFrame = clampedStartFrame;
            });
          }
        },
        onHorizontalDragEnd: (details) {
          if (!_isDragging) return;
          
          // Move the clip in the ViewModel to the current preview position
          if (_originalStartFrame != _currentDragFrame) {
            // Use the new method and databaseId
            if (widget.clip.databaseId != null) { // Ensure ID exists before calling
               final newStartTimeMs = ClipModel.framesToMs(_currentDragFrame);
               timelineVm.updateClipPosition(widget.clip.databaseId!, newStartTimeMs);
            } else {
               logWarning(runtimeType.toString(), "Warning: Cannot move clip - databaseId is null.");
            }
          }
          
          setState(() {
            _isDragging = false;
          });
        },
        child: Stack(
          children: [
            Container(
              // Add margin for spacing between clips
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                // Use lighter color and maybe less opacity when dragging
                color: _isDragging || widget.isDragging ? clipColor.withOpacity(0.5) : clipColor,
                border: Border.all(
                  // Use theme accent for selection, different color for dragging feedback
                  color:
                      _isDragging || widget.isDragging
                          ? theme.accentColor.light
                          : (isSelected ? selectionBorderColor : Colors.transparent),
                  width: _isDragging || widget.isDragging ? 1 : (isSelected ? 2 : 1), // Adjust width
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              // Slightly reduce opacity of content when dragging
              child: Opacity(
                opacity: _isDragging || widget.isDragging ? 0.8 : 1.0,
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
                              widget.clip.name,
                              // Use theme caption style with contrast color
                              style: theme.typography.caption?.copyWith(
                                color: contrastColor,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis, // Prevent overflow
                              maxLines: 1,
                            ),
                          ),
                          // Display frame position when dragging, otherwise duration
                          Text(
                            _isDragging 
                                ? 'Frame: $_currentDragFrame' 
                                : '${widget.clip.durationFrames}f',
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
            // Show edge indicators when dragging
            if (_isDragging)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: theme.accentColor.darker,
                ),
              ),
            if (_isDragging)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: theme.accentColor.darker,
                ),
              ),
          ],
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

    switch (widget.clip.type) {
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
            seed: widget.clip.hashCode,
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

    canvas.drawPath(path, paint);
  }

  // Repaint if color changes (though unlikely here)
  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.seed != seed;
} 