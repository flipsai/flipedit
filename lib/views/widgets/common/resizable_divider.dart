import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

/// A divider that can be dragged horizontally or vertically to resize adjacent widgets.
class ResizableDivider extends StatefulWidget {
  /// The orientation of the divider and the drag direction.
  final Axis axis;

  /// The thickness of the interactive drag area (width for vertical, height for horizontal).
  final double thickness;

  /// Callback function invoked when a drag update occurs.
  /// Provides the delta of the drag (dx for vertical, dy for horizontal).
  final ValueChanged<double> onDragUpdate;

  /// Callback function invoked when a drag starts.
  final VoidCallback? onDragStart;

  /// Callback function invoked when a drag ends.
  final VoidCallback? onDragEnd;

  /// The color of the divider line when not hovered or dragged.
  final Color? color;

  /// The background color of the interactive area when hovered or dragged.
  final Color? highlightColor;

  /// Duration of the hover animation effect
  final Duration animationDuration;

  const ResizableDivider({
    super.key,
    required this.onDragUpdate,
    this.axis = Axis.vertical, // Default to vertical
    this.onDragStart,
    this.onDragEnd,
    this.thickness = 8.0, // Default thickness for the grab area
    this.color,
    this.highlightColor,
    this.animationDuration = const Duration(
      milliseconds: 150,
    ), // Default animation duration
  });

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  bool _isHovering = false;
  bool _isResizing = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final effectiveColor =
        widget.color ?? theme.resources.subtleFillColorTertiary;
    final effectiveHighlightColor =
        widget.highlightColor ?? theme.resources.subtleFillColorSecondary;
    final isVertical = widget.axis == Axis.vertical;

    return GestureDetector(
      onHorizontalDragStart:
          isVertical
              ? (_) {
                setState(() => _isResizing = true);
                widget.onDragStart?.call();
              }
              : null,
      onVerticalDragStart:
          !isVertical
              ? (_) {
                setState(() => _isResizing = true);
                widget.onDragStart?.call();
              }
              : null,
      onHorizontalDragUpdate:
          isVertical
              ? (details) {
                widget.onDragUpdate(details.delta.dx);
              }
              : null,
      onVerticalDragUpdate:
          !isVertical
              ? (details) {
                widget.onDragUpdate(details.delta.dy);
              }
              : null,
      onHorizontalDragEnd:
          isVertical
              ? (_) {
                setState(() => _isResizing = false);
                widget.onDragEnd?.call();
              }
              : null,
      onVerticalDragEnd:
          !isVertical
              ? (_) {
                setState(() => _isResizing = false);
                widget.onDragEnd?.call();
              }
              : null,
      child: MouseRegion(
        cursor:
            isVertical
                ? SystemMouseCursors.resizeColumn
                : SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: widget.animationDuration,
          width: isVertical ? widget.thickness : null,
          height: !isVertical ? widget.thickness : null,
          color:
              (_isHovering || _isResizing)
                  ? effectiveHighlightColor
                  : effectiveColor,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}
