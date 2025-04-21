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
  final int trackId;
  final bool isDragging;

  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackId,
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

  // Controller for the context menu flyout
  final FlyoutController _contextMenuController = FlyoutController();

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
        (0.299 * backgroundColor.r +
            0.587 * backgroundColor.g +
            0.114 * backgroundColor.b) /
        255;
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  @override
  void initState() {
    super.initState();
    // Initialize _currentDragFrame based on the initial clip position
    // This prevents the clip appearing at 0s initially when first added.
    _currentDragFrame = widget.clip.startFrame;
  }

  @override
  void dispose() {
    _contextMenuController.dispose(); // Dispose the controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Get view models
    final editorVm = di<EditorViewModel>();
    final timelineVm = di<TimelineViewModel>();

    // Use watchValue here in the State's build method
    final selectedClipId = watchValue(
      (EditorViewModel vm) => vm.selectedClipIdNotifier,
    );
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);

    final isSelected = selectedClipId == widget.clip.databaseId?.toString();

    // Calculate the visual offset based on the difference between the current drag frame
    // and the clip's official start frame. Apply this offset always to keep the visual
    // position consistent until the parent rebuilds with the updated data.
    final double dragOffset =
        (_currentDragFrame - widget.clip.startFrame) * 5.0 * zoom;

    // Get base color for clip type
    final baseClipColor =
        _clipTypeColors[widget.clip.type] ?? Colors.grey; // Default grey
    final clipColor = baseClipColor;
    final contrastColor = _getContrastColor(
      clipColor,
    ); // Color for text/icons on the clip

    // Use theme accent color for selection border
    final selectionBorderColor = theme.accentColor.normal;
    
    // Format duration in seconds with 1 decimal place
    final durationInSec = widget.clip.durationMs / 1000.0;
    final formattedDuration = durationInSec.toStringAsFixed(1);
    
    // UI constants
    const double fixedClipHeight = 65.0;
    const double borderRadiusValue = 10.0;
    const double borderWidth = 2.5;
    const double shadowBlur = 12.0;

    return Transform.translate(
      offset: Offset(dragOffset, 0), // Apply the visual offset
      child: FlyoutTarget(
        controller: _contextMenuController,
        child: GestureDetector(
          onTap: () {
            editorVm.selectedClipId = widget.clip.databaseId?.toString();
          },
          onPanStart: (details) {
            setState(() {
              _isDragging = true;
              _dragStartX = details.localPosition.dx;
              _originalStartFrame = widget.clip.startFrame;
              _currentDragFrame = _originalStartFrame;
            });
            editorVm.selectedClipId = widget.clip.databaseId?.toString();
          },
          onPanUpdate: (details) {
            if (!_isDragging) return;
            final pixelsPerFrame = 5.0 * zoom;
            final dragDeltaInFrames =
                (details.localPosition.dx - _dragStartX) ~/ pixelsPerFrame;
            final newStartFrame = _originalStartFrame + dragDeltaInFrames;
            final clampedStartFrame = newStartFrame < 0 ? 0 : newStartFrame;
            if (_currentDragFrame != clampedStartFrame) {
              setState(() {
                _currentDragFrame = clampedStartFrame;
              });
            }
          },
          onPanEnd: (details) {
            if (!_isDragging) return;
            if (_originalStartFrame != _currentDragFrame) {
              if (widget.clip.databaseId != null) {
                final newStartTimeMs = ClipModel.framesToMs(_currentDragFrame);
                timelineVm.updateClipPosition(
                  widget.clip.databaseId!,
                  widget.clip.trackId,
                  newStartTimeMs,
                );
              } else {
                logWarning(
                  runtimeType.toString(),
                  "Warning: Cannot move clip - databaseId is null.",
                );
              }
            }
            setState(() {
              _isDragging = false;
            });
          },
          onSecondaryTapUp: (details) {
            editorVm.selectedClipId = widget.clip.databaseId?.toString();
            _contextMenuController.showFlyout(
              barrierDismissible: true,
              position: details.globalPosition,
              builder: (context) => _buildContextMenu(context),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: fixedClipHeight,
            padding: const EdgeInsets.all(borderWidth), // Ensure border is not covered
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadiusValue),
              border: Border.all(
                color: isSelected ? selectionBorderColor : clipColor.withAlpha(70),
                width: isSelected ? borderWidth : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: shadowBlur,
                  offset: const Offset(0, 3),
                ),
                if (isSelected)
                  BoxShadow(
                    color: selectionBorderColor.withOpacity(0.25),
                    blurRadius: shadowBlur * 1.2,
                    spreadRadius: 1.5,
                  ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  clipColor.withAlpha(210),
                  clipColor.withAlpha(160),
                ],
              ),
            ),
            child: Stack(
              children: [
                // Main content visualization
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadiusValue - 2),
                  child: _buildClipContent(
                    clipColor,
                    contrastColor,
                    theme,
                  ),
                ),
                // Info overlay at bottom (now inset, not covering border)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 16,
                    margin: const EdgeInsets.only(bottom: 2), // Give a bit more space from the border
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.09),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(borderRadiusValue - 1),
                        bottomRight: Radius.circular(borderRadiusValue - 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Display duration
                        Text(
                          '${formattedDuration}s',
                          style: theme.typography.caption?.copyWith(
                            color: contrastColor.withAlpha(220),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Display position
                        Text(
                          _getTimePosition(),
                          style: theme.typography.caption?.copyWith(
                            color: contrastColor.withAlpha(220),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper to get icon for clip type
  IconData _getIconForClipType(ClipType type) {
    switch (type) {
      case ClipType.video:
        return FluentIcons.video;
      case ClipType.audio:
        return FluentIcons.volume2;
      case ClipType.image:
        return FluentIcons.picture;
      case ClipType.text:
        return FluentIcons.text_document;
      case ClipType.effect:
        return FluentIcons.filter;
    }
  }
  
  // Helper to format time position
  String _getTimePosition() {
    final startMs = widget.clip.startTimeOnTrackMs;
    final startSec = startMs / 1000.0;
    return '${startSec.toStringAsFixed(1)}s';
  }

  Widget _buildClipContent(
    Color clipColor,
    Color contrastColor,
    FluentThemeData theme,
  ) {
    // Use a semi-transparent version of the contrast color for icons/content
    final contentColor = contrastColor.withAlpha(200);
    // Use a slightly transparent version of the base color for backgrounds
    final contentBackgroundColor = clipColor.withAlpha(170);

    // Extract filename without extension for display
    final fileName = widget.clip.sourcePath.split('/').last;
    final fileNameNoExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    // Track height should be fixed and match the track height everywhere (e.g. 65.0)
    const double fixedClipHeight = 65.0;

    switch (widget.clip.type) {
      case ClipType.video:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  // Add a subtle gradient
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      clipColor.withAlpha(170),
                      clipColor.withAlpha(140),
                    ],
                  ),
                ),
              ),
              // Video frame grid pattern
              CustomPaint(
                painter: _VideoFramesPainter(
                  color: contentColor.withAlpha(30),
                ),
                child: const SizedBox.expand(),
              ),
              // Center icon and file info
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.video, size: 16, color: contentColor),
                    if (widget.clip.durationFrames > 20) // Only show on larger clips
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          fileNameNoExt,
                          style: theme.typography.caption?.copyWith(
                            color: contentColor,
                            fontSize: 8,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case ClipType.audio:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                color: contentBackgroundColor.withOpacity(0.5),
              ),
              // Waveform visualization
              CustomPaint(
                painter: _AudioWaveformPainter(
                  color: contentColor,
                  seed: widget.clip.hashCode,
                ),
                child: const SizedBox.expand(),
              ),
              // Audio level indicators
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  FluentIcons.volume2,
                  size: 10,
                  color: contentColor.withAlpha(150),
                ),
              ),
            ],
          ),
        );

      case ClipType.image:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      clipColor.withAlpha(170),
                      clipColor.withAlpha(130),
                    ],
                  ),
                ),
              ),
              // Image grid pattern
              CustomPaint(
                painter: _ImageGridPainter(
                  color: contentColor.withAlpha(40),
                ),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.picture, size: 16, color: contentColor),
                    if (widget.clip.durationFrames > 20)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          fileNameNoExt,
                          style: theme.typography.caption?.copyWith(
                            color: contentColor,
                            fontSize: 8,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case ClipType.text:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      clipColor.withAlpha(170),
                      clipColor.withAlpha(130),
                    ],
                  ),
                ),
              ),
              // Text line pattern
              CustomPaint(
                painter: _TextLinesPainter(
                  color: contentColor.withAlpha(40),
                ),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.text_document, size: 16, color: contentColor),
                    if (widget.clip.durationFrames > 20)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          fileNameNoExt,
                          style: theme.typography.caption?.copyWith(
                            color: contentColor,
                            fontSize: 8,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

      case ClipType.effect:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      clipColor.withAlpha(170),
                      clipColor.withAlpha(130),
                    ],
                  ),
                ),
              ),
              // Effect pattern
              CustomPaint(
                painter: _EffectPatternPainter(
                  color: contentColor.withAlpha(40),
                  seed: widget.clip.hashCode,
                ),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(FluentIcons.filter, size: 16, color: contentColor),
                    if (widget.clip.durationFrames > 20)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          fileNameNoExt,
                          style: theme.typography.caption?.copyWith(
                            color: contentColor,
                            fontSize: 8,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  // Context menu for right-click
  Widget _buildContextMenu(BuildContext context) {
    final timelineVm = di<TimelineViewModel>();
    return MenuFlyout(
      items: [
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.delete),
          text: const Text('Remove'),
          onPressed: () {
            if (widget.clip.databaseId != null) {
              timelineVm.removeClip(widget.clip.databaseId!);
            }
            Flyout.of(context).close();
          },
        ),
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.edit),
          text: const Text('Edit'),
          onPressed: () {
            // TODO: Implement edit functionality
            Flyout.of(context).close();
          },
        ),
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.copy),
          text: const Text('Duplicate'),
          onPressed: () {
            // TODO: Implement duplicate functionality
            Flyout.of(context).close();
          },
        ),
      ],
    );
  }
}

// New painter for video frames pattern
class _VideoFramesPainter extends CustomPainter {
  final Color color;

  _VideoFramesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    final cellWidth = size.width / 4;
    final cellHeight = size.height / 3;
    
    // Draw vertical lines
    for (int i = 1; i < 4; i++) {
      final x = cellWidth * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    
    // Draw horizontal lines
    for (int i = 1; i < 3; i++) {
      final y = cellHeight * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// New painter for image grid pattern
class _ImageGridPainter extends CustomPainter {
  final Color color;

  _ImageGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    // Draw diagonal lines
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    
    // Draw frame border
    canvas.drawRect(Rect.fromLTWH(4, 4, size.width-8, size.height-8), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// New painter for text lines pattern
class _TextLinesPainter extends CustomPainter {
  final Color color;

  _TextLinesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    final lineSpacing = size.height / 5;
    
    // Draw text lines
    for (int i = 1; i < 5; i++) {
      final y = lineSpacing * i;
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// New painter for effect pattern
class _EffectPatternPainter extends CustomPainter {
  final Color color;
  final int seed;

  _EffectPatternPainter({required this.color, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
      
    final random = math.Random(seed);
    final path = Path();
    
    // Draw effect zigzag
    path.moveTo(0, size.height / 2);
    
    double step = size.width / 10;
    double amplitude = size.height / 3;
    double x = 0;
    
    while (x < size.width) {
      double y = size.height / 2 + (random.nextDouble() * 2 - 1) * amplitude;
      path.lineTo(x, y);
      x += step;
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => 
      oldDelegate is _EffectPatternPainter && oldDelegate.seed != seed;
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
