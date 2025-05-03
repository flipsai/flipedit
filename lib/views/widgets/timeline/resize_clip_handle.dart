import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';

/// Widget for handling resize operations on timeline clips
class ResizeClipHandle extends StatefulWidget {
  final String direction;
  final ClipModel clip;
  final double pixelsPerFrame;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  const ResizeClipHandle({
    super.key,
    required this.direction,
    required this.clip,
    required this.pixelsPerFrame,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  }) : assert(direction == 'left' || direction == 'right');

  @override
  State<ResizeClipHandle> createState() => _ResizeClipHandleState();
}

class _ResizeClipHandleState extends State<ResizeClipHandle> {
  double _accumulatedPixelDelta = 0.0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final bool isLeft = widget.direction == 'left';
    final Color handleColor = theme.accentColor.light.withOpacity(0.5);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          _accumulatedPixelDelta = 0;
          widget.onDragStart();
        },
        onHorizontalDragUpdate: (details) {
          _accumulatedPixelDelta += details.primaryDelta ?? 0;
          widget.onDragUpdate(_accumulatedPixelDelta);
        },
        onHorizontalDragEnd: (details) {
          widget.onDragEnd(_accumulatedPixelDelta);
          _accumulatedPixelDelta = 0;
        },
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: handleColor,
            borderRadius: BorderRadius.only(
              topLeft: isLeft ? const Radius.circular(3) : Radius.zero,
              bottomLeft: isLeft ? const Radius.circular(3) : Radius.zero,
              topRight: !isLeft ? const Radius.circular(3) : Radius.zero,
              bottomRight: !isLeft ? const Radius.circular(3) : Radius.zero,
            ),
            border: Border(
              left:
                  isLeft
                      ? BorderSide.none
                      : BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 0.5,
                      ),
              right:
                  !isLeft
                      ? BorderSide.none
                      : BorderSide(
                        color: Colors.black.withOpacity(0.2),
                        width: 0.5,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
