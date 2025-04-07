import 'package:flutter/material.dart';
import 'package:flipedit/views/widgets/panel_system/panel_models.dart';
import 'package:flipedit/views/widgets/panel_system/resize_handle.dart';
import 'package:flipedit/views/widgets/panel_system/panel_tabs.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/panel_grid_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// A system for managing draggable and resizable panels like VS Code
class PanelGridSystem extends StatefulWidget {
  final List<PanelDefinition> initialPanels;
  final Color? backgroundColor;
  final Color? resizeHandleColor;
  
  const PanelGridSystem({
    Key? key,
    required this.initialPanels,
    this.backgroundColor,
    this.resizeHandleColor,
  }) : super(key: key);

  @override
  State<PanelGridSystem> createState() => _PanelGridSystemState();
}

class _PanelGridSystemState extends State<PanelGridSystem> {
  // Data structure to hold panel layout information
  late PanelLayoutModel _layoutModel;
  
  // Calculate resize handles
  List<ResizeHandlePosition> _resizeHandles = [];
  
  @override
  void initState() {
    super.initState();
    _layoutModel = PanelLayoutModel.fromInitialPanels(widget.initialPanels);
    _updateResizeHandles();
  }
  
  void _updateResizeHandles() {
    // Calculate resize handles based on layout
    // For now, we'll use a simple approach
    _resizeHandles = [];
    
    // Add horizontal resize handles between panels
    if (_layoutModel.rootNode.direction == SplitDirection.horizontal) {
      for (int i = 0; i < _layoutModel.rootNode.children.length - 1; i++) {
        _resizeHandles.add(ResizeHandlePosition(
          isHorizontal: true,
          row: 0,
          column: i,
        ));
      }
    }
    // Add vertical resize handles between panels
    else if (_layoutModel.rootNode.direction == SplitDirection.vertical) {
      for (int i = 0; i < _layoutModel.rootNode.children.length - 1; i++) {
        _resizeHandles.add(ResizeHandlePosition(
          isHorizontal: false,
          row: i,
          column: 0,
        ));
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Background
            Container(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              color: widget.backgroundColor ?? Colors.grey[50],
            ),
            
            // Render panel grid
            ..._buildPanelGrid(constraints),
            
            // Resize handles
            ..._buildResizeHandles(constraints),
            
            // Drop target indicator when dragging
            _DropTargetIndicator(
              layoutModel: _layoutModel,
              constraints: constraints,
            ),
          ],
        );
      }
    );
  }
  
  // Build the main panel grid based on current layout
  List<Widget> _buildPanelGrid(BoxConstraints constraints) {
    final widgets = <Widget>[];
    
    // For now, we'll use a simple approach to render panels
    if (_layoutModel.rootNode.direction == SplitDirection.horizontal) {
      double currentX = 0;
      
      for (int i = 0; i < _layoutModel.rootNode.children.length; i++) {
        final child = _layoutModel.rootNode.children[i];
        final width = constraints.maxWidth * child.size;
        
        widgets.add(
          Positioned(
            left: currentX,
            top: 0,
            width: width,
            height: constraints.maxHeight,
            child: _buildPanel(child),
          ),
        );
        
        currentX += width;
      }
    } else if (_layoutModel.rootNode.direction == SplitDirection.vertical) {
      double currentY = 0;
      
      for (int i = 0; i < _layoutModel.rootNode.children.length; i++) {
        final child = _layoutModel.rootNode.children[i];
        final height = constraints.maxHeight * child.size;
        
        widgets.add(
          Positioned(
            left: 0,
            top: currentY,
            width: constraints.maxWidth,
            height: height,
            child: _buildPanel(child),
          ),
        );
        
        currentY += height;
      }
    } else {
      // Single panel or no panels
      if (_layoutModel.rootNode.isLeaf && _layoutModel.rootNode.panel != null) {
        widgets.add(
          Positioned.fill(
            child: _buildPanel(_layoutModel.rootNode),
          ),
        );
      }
    }
    
    return widgets;
  }
  
  // Build a panel
  Widget _buildPanel(PanelNode node) {
    if (!node.isLeaf || node.panel == null) {
      return const SizedBox.shrink();
    }
    
    final panel = node.panel!;
    
    return DragTarget<PanelDefinition>(
      onWillAccept: (data) {
        // Don't accept if it's the same panel
        return data?.id != panel.id;
      },
      onAccept: (data) {
        // Handle drop
        di<PanelGridViewModel>().clearDropTarget();
      },
      onLeave: (_) {
        di<PanelGridViewModel>().clearDropTarget();
      },
      onMove: (details) {
        // Calculate drop position (top, right, bottom, left, or center)
        final RenderBox box = context.findRenderObject() as RenderBox;
        final Offset localOffset = box.globalToLocal(details.offset);
        
        final width = box.size.width;
        final height = box.size.height;
        
        DropPosition position;
        
        // Determine edge proximity
        final edgeThreshold = 40.0;
        
        if (localOffset.dx < edgeThreshold) {
          position = DropPosition.left;
        } else if (localOffset.dx > width - edgeThreshold) {
          position = DropPosition.right;
        } else if (localOffset.dy < edgeThreshold) {
          position = DropPosition.top;
        } else if (localOffset.dy > height - edgeThreshold) {
          position = DropPosition.bottom;
        } else {
          position = DropPosition.center;
        }
        
        di<PanelGridViewModel>().updateDropTarget(panel.id, position);
      },
      builder: (context, candidateData, rejectedData) {
        return LongPressDraggable<PanelDefinition>(
          data: panel,
          delay: const Duration(milliseconds: 200),
          feedback: Material(
            elevation: 4,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              width: 200,
              height: 40,
              child: Row(
                children: [
                  if (panel.icon != null)
                    Icon(panel.icon, size: 16),
                  const SizedBox(width: 8),
                  Text(panel.title),
                ],
              ),
            ),
          ),
          child: _buildPanelContent(panel),
        );
      },
    );
  }
  
  Widget _buildPanelContent(PanelDefinition panel) {
    // For now, wrap the content in a basic container with a header
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFFE7E7E7),
            child: Row(
              children: [
                if (panel.icon != null) ...[
                  Icon(panel.icon, size: 16, color: Colors.black87),
                  const SizedBox(width: 8),
                ],
                Text(
                  panel.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                // Example of split button
                IconButton(
                  icon: const Icon(Icons.splitscreen, size: 16),
                  onPressed: () {
                    // TODO: Add a new panel next to this one
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    // TODO: Remove this panel
                  },
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: panel.content,
          ),
        ],
      ),
    );
  }
  
  // Build resize handles
  List<Widget> _buildResizeHandles(BoxConstraints constraints) {
    final widgets = <Widget>[];
    
    // Horizontal handles (for vertical resizing)
    if (_layoutModel.rootNode.direction == SplitDirection.horizontal) {
      double currentX = 0;
      
      for (int i = 0; i < _layoutModel.rootNode.children.length - 1; i++) {
        final child = _layoutModel.rootNode.children[i];
        currentX += constraints.maxWidth * child.size;
        
        widgets.add(
          Positioned(
            left: currentX - 3, // Center the handle
            top: 0,
            width: 6,
            height: constraints.maxHeight,
            child: ResizeHandle(
              position: ResizeHandlePosition(
                isHorizontal: true,
                row: 0,
                column: i,
              ),
              onResize: (delta) => _handleResize(i, delta, true),
              color: widget.resizeHandleColor,
            ),
          ),
        );
      }
    }
    // Vertical handles (for horizontal resizing)
    else if (_layoutModel.rootNode.direction == SplitDirection.vertical) {
      double currentY = 0;
      
      for (int i = 0; i < _layoutModel.rootNode.children.length - 1; i++) {
        final child = _layoutModel.rootNode.children[i];
        currentY += constraints.maxHeight * child.size;
        
        widgets.add(
          Positioned(
            left: 0,
            top: currentY - 3, // Center the handle
            width: constraints.maxWidth,
            height: 6,
            child: ResizeHandle(
              position: ResizeHandlePosition(
                isHorizontal: false,
                row: i,
                column: 0,
              ),
              onResize: (delta) => _handleResize(i, delta, false),
              color: widget.resizeHandleColor,
            ),
          ),
        );
      }
    }
    
    return widgets;
  }
  
  // Handle resize events
  void _handleResize(int index, double delta, bool isHorizontal) {
    setState(() {
      if (_layoutModel.rootNode.children.length <= index + 1) {
        return;
      }
      
      // Calculate size changes
      final node1 = _layoutModel.rootNode.children[index];
      final node2 = _layoutModel.rootNode.children[index + 1];
      
      // Convert delta to size ratio change
      double deltaSize = 0;
      if (isHorizontal) {
        deltaSize = delta / context.size!.width;
      } else {
        deltaSize = delta / context.size!.height;
      }
      
      // Apply size changes with min size limits
      final minSize = 0.1; // 10% minimum
      
      if (node1.size + deltaSize < minSize || node2.size - deltaSize < minSize) {
        return;
      }
      
      node1.size += deltaSize;
      node2.size -= deltaSize;
    });
  }
}

class _DropTargetIndicator extends StatelessWidget with WatchItMixin {
  final PanelLayoutModel layoutModel;
  final BoxConstraints constraints;

  const _DropTargetIndicator({
    required this.layoutModel,
    required this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final dropTargetId = watchPropertyValue((PanelGridViewModel vm) => vm.dropTargetId);
    final dropPosition = watchPropertyValue((PanelGridViewModel vm) => vm.dropPosition);

    if (dropTargetId == null || dropPosition == null) {
      return const SizedBox.shrink();
    }

    final targetNode = layoutModel.rootNode.findNodeByPanelId(dropTargetId);
    if (targetNode == null) {
      return const SizedBox.shrink();
    }
    
    // Find the position of the target panel
    double left = 0;
    double top = 0;
    double width = constraints.maxWidth;
    double height = constraints.maxHeight;
    
    // In a production app, you'd calculate the exact position
    // This is simplified for demonstration
    
    // Draw indicator based on drop position
    Color indicatorColor = Colors.blue.withOpacity(0.3);
    
    switch (dropPosition) {
      case DropPosition.left:
        width = 40;
        break;
      case DropPosition.right:
        left = constraints.maxWidth - 40;
        width = 40;
        break;
      case DropPosition.top:
        height = 40;
        break;
      case DropPosition.bottom:
        top = constraints.maxHeight - 40;
        height = 40;
        break;
      case DropPosition.center:
        // Highlight the whole panel
        break;
    }
    
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: indicatorColor,
          border: Border.all(color: Colors.blue, width: 2),
        ),
      ),
    );
  }
}
