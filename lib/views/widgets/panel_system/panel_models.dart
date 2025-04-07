import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// Defines the direction of a split in the panel layout
enum SplitDirection { horizontal, vertical }

/// Defines where a panel can be dropped
enum DropPosition { left, right, top, bottom, center }

/// Defines the position of a resize handle
class ResizeHandlePosition {
  final bool isHorizontal;
  final int row;
  final int column;
  
  const ResizeHandlePosition({
    required this.isHorizontal,
    required this.row,
    required this.column,
  });
}

/// Defines a panel in the grid
class PanelDefinition {
  final String id;
  final String title;
  final Widget content;
  final IconData? icon;
  
  PanelDefinition({
    String? id,
    required this.title,
    required this.content,
    this.icon,
  }) : id = id ?? const Uuid().v4();
}

/// Node in panel layout tree
class PanelNode {
  final String id;
  final bool isLeaf; // True if panel, false if container
  final SplitDirection? direction; // Horizontal or vertical split
  final List<PanelNode> children;
  final PanelDefinition? panel; // Non-null if isLeaf
  double size; // Relative size (0.0-1.0)
  
  PanelNode({
    String? id,
    required this.isLeaf,
    this.direction,
    List<PanelNode>? children,
    this.panel,
    this.size = 1.0,
  }) : 
    id = id ?? const Uuid().v4(),
    children = children ?? [];
  
  PanelNode copyWith({
    String? id,
    bool? isLeaf,
    SplitDirection? direction,
    List<PanelNode>? children,
    PanelDefinition? panel,
    double? size,
  }) {
    return PanelNode(
      id: id ?? this.id,
      isLeaf: isLeaf ?? this.isLeaf,
      direction: direction ?? this.direction,
      children: children ?? this.children,
      panel: panel ?? this.panel,
      size: size ?? this.size,
    );
  }
  
  /// Create a leaf node containing a panel
  factory PanelNode.leaf(PanelDefinition panel, {double size = 1.0}) {
    return PanelNode(
      isLeaf: true,
      panel: panel,
      size: size,
    );
  }
  
  /// Create a container node with children
  factory PanelNode.container({
    required SplitDirection direction,
    required List<PanelNode> children,
    double size = 1.0,
  }) {
    return PanelNode(
      isLeaf: false,
      direction: direction,
      children: children,
      size: size,
    );
  }
  
  /// Create a default horizontal layout with panels side by side
  static PanelNode createDefaultHorizontalLayout(List<PanelDefinition> panels) {
    if (panels.isEmpty) {
      return PanelNode(isLeaf: false, direction: SplitDirection.horizontal);
    }
    
    if (panels.length == 1) {
      return PanelNode.leaf(panels.first);
    }
    
    final List<PanelNode> children = panels.map((panel) {
      return PanelNode.leaf(panel, size: 1.0 / panels.length);
    }).toList();
    
    return PanelNode.container(
      direction: SplitDirection.horizontal,
      children: children,
    );
  }
  
  /// Create a default layout with the specified panels
  static PanelNode createDefaultLayout(List<PanelDefinition> panels) {
    return createDefaultHorizontalLayout(panels);
  }
  
  /// Find a node by id
  PanelNode? findNodeById(String nodeId) {
    if (id == nodeId) {
      return this;
    }
    
    if (isLeaf) {
      return null;
    }
    
    for (var child in children) {
      final found = child.findNodeById(nodeId);
      if (found != null) {
        return found;
      }
    }
    
    return null;
  }
  
  /// Find a node containing a panel by panel id
  PanelNode? findNodeByPanelId(String panelId) {
    if (isLeaf && panel?.id == panelId) {
      return this;
    }
    
    if (isLeaf) {
      return null;
    }
    
    for (var child in children) {
      final found = child.findNodeByPanelId(panelId);
      if (found != null) {
        return found;
      }
    }
    
    return null;
  }
}

/// Model to manage panel layout
class PanelLayoutModel {
  // A tree structure to represent panel layout
  PanelNode rootNode;
  bool isDragging = false;
  String? draggingPanelId;
  
  PanelLayoutModel({required this.rootNode});
  
  factory PanelLayoutModel.fromInitialPanels(List<PanelDefinition> panels) {
    // Create initial layout
    return PanelLayoutModel(
      rootNode: PanelNode.createDefaultLayout(panels),
    );
  }
  
  /// Move a panel to a new position
  bool movePanel(String panelId, String targetPanelId, DropPosition position) {
    final sourceNode = rootNode.findNodeByPanelId(panelId);
    final targetNode = rootNode.findNodeByPanelId(targetPanelId);
    
    if (sourceNode == null || targetNode == null) {
      return false;
    }
    
    // TODO: Implement complex move panel logic
    // This requires restructuring the tree based on drop position
    
    return false;
  }
  
  /// Resize panels
  void resizeAt(ResizeHandlePosition handle, double delta) {
    // TODO: Implement resize logic
    // This would find the nodes affected by the resize handle and adjust their sizes
  }
  
  /// Add a panel to the layout
  void addPanel(PanelDefinition panel, {String? targetPanelId, DropPosition? position}) {
    if (targetPanelId == null || position == null) {
      // Just add to root if it's the first panel
      if (rootNode.children.isEmpty) {
        rootNode.children.add(PanelNode.leaf(panel));
        return;
      }
      
      // Otherwise add to the end of root's children
      rootNode.children.add(PanelNode.leaf(panel, size: 1.0 / (rootNode.children.length + 1)));
      
      // Adjust other sizes
      final newSize = 1.0 / rootNode.children.length;
      for (var child in rootNode.children) {
        child.size = newSize;
      }
      
      return;
    }
    
    // TODO: Implement logic to add panel at specific location
  }
  
  /// Remove a panel from the layout
  bool removePanel(String panelId) {
    // TODO: Implement panel removal logic
    return false;
  }
}
