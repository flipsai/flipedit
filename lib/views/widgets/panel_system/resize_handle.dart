import 'package:flutter/material.dart';
import 'panel_models.dart';

class ResizeHandle extends StatefulWidget {
  final ResizeHandlePosition position;
  final Function(double delta) onResize;
  final Color? color;
  final Color? hoverColor;
  
  const ResizeHandle({
    Key? key,
    required this.position,
    required this.onResize,
    this.color,
    this.hoverColor,
  }) : super(key: key);
  
  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _isHovering = false;
  
  @override
  Widget build(BuildContext context) {
    final bool isHorizontal = widget.position.isHorizontal;
    
    return MouseRegion(
      cursor: isHorizontal 
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onPanUpdate: (details) {
          if (isHorizontal) {
            widget.onResize(details.delta.dx);
          } else {
            widget.onResize(details.delta.dy);
          }
        },
        child: Container(
          width: isHorizontal ? 6 : double.infinity,
          height: isHorizontal ? double.infinity : 6,
          color: _isHovering 
              ? (widget.hoverColor ?? Colors.blue.withOpacity(0.3))
              : (widget.color ?? Colors.transparent),
          child: Center(
            child: Container(
              width: isHorizontal ? 2 : 20,
              height: isHorizontal ? 20 : 2,
              decoration: BoxDecoration(
                color: _isHovering ? Colors.blue.withOpacity(0.8) : Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
