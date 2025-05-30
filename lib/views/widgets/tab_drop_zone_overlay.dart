import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import '../../viewmodels/tab_system_viewmodel.dart';
import 'tab_bar_widget.dart';

enum DropZonePosition {
  left,
  right,
  top,
  bottom,
  center,
}

class TabDropZoneOverlay extends StatelessWidget {
  final bool isVisible;
  final TabSystemLayout layoutOrientation;
  final Function(DropZonePosition? position)? onDropZoneHovered;
  final DropZonePosition? hoveredZone;

  const TabDropZoneOverlay({
    Key? key,
    required this.isVisible,
    required this.layoutOrientation,
    this.onDropZoneHovered,
    this.hoveredZone,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Stack(
      children: [
        // Left drop zone (covers left half)
        _buildHalfScreenDropZone(
          context,
          position: DropZonePosition.left,
          alignment: Alignment.centerLeft,
          fraction: 0.5,
          axis: Axis.horizontal,
          isFirstHalf: true,
        ),
        
        // Right drop zone (covers right half)
        _buildHalfScreenDropZone(
          context,
          position: DropZonePosition.right,
          alignment: Alignment.centerRight,
          fraction: 0.5,
          axis: Axis.horizontal,
          isFirstHalf: false,
        ),
        
        // Bottom drop zone (covers bottom half)
        _buildHalfScreenDropZone(
          context,
          position: DropZonePosition.bottom,
          alignment: Alignment.bottomCenter,
          fraction: 0.5,
          axis: Axis.vertical,
          isFirstHalf: false,
        ),
      ],
    );
  }

  Widget _buildHalfScreenDropZone(
    BuildContext context, {
    required DropZonePosition position,
    required Alignment alignment,
    required double fraction,
    required Axis axis,
    required bool isFirstHalf,
  }) {
    final theme = FluentTheme.of(context);
    final tabSystem = di<TabSystemViewModel>();
    final isHovered = hoveredZone == position;
    
    // Calculate the drop zone area - it should be at the edge for detection
    // but show preview covering the half when hovered
    double detectionZoneSize = 50.0; // Thin area at edge for hover detection
    
    Widget detectionZone;
    Widget? previewArea;
    
    if (axis == Axis.horizontal) {
      // Horizontal split (left/right)
      detectionZone = Align(
        alignment: alignment,
        child: Container(
          width: detectionZoneSize,
          height: double.infinity,
          color: Colors.transparent,
        ),
      );
      
      if (isHovered) {
        previewArea = Align(
          alignment: alignment,
          child: Container(
            width: MediaQuery.of(context).size.width * fraction,
            height: double.infinity,
            decoration: BoxDecoration(
              color: theme.accentColor.withOpacity(0.3),
              border: Border.all(
                color: theme.accentColor,
                width: 2,
              ),
            ),
            child: _buildPreviewContent(context, position),
          ),
        );
      }
    } else {
      // Vertical split (top/bottom)
      detectionZone = Align(
        alignment: alignment,
        child: Container(
          width: double.infinity,
          height: detectionZoneSize,
          color: Colors.transparent,
        ),
      );
      
      if (isHovered) {
        previewArea = Align(
          alignment: alignment,
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height * fraction,
            decoration: BoxDecoration(
              color: theme.accentColor.withOpacity(0.3),
              border: Border.all(
                color: theme.accentColor,
                width: 2,
              ),
            ),
            child: _buildPreviewContent(context, position),
          ),
        );
      }
    }

    return Stack(
      children: [
        // Always show preview area if hovered
        if (previewArea != null) previewArea,
        
        // Drag target for detection
        Align(
          alignment: alignment,
          child: DragTarget<TabDragData>(
            onWillAcceptWithDetails: (details) {
              onDropZoneHovered?.call(position);
              return true;
            },
            onAcceptWithDetails: (details) {
              final tabId = details.data.tabId;
              final sourceGroupId = details.data.sourceGroupId;
              
              tabSystem.handleDropZoneAction(tabId, sourceGroupId, position.name);
              onDropZoneHovered?.call(null);
            },
            onLeave: (data) {
              if (hoveredZone == position) {
                onDropZoneHovered?.call(null);
              }
            },
            builder: (context, candidateData, rejectedData) {
              return axis == Axis.horizontal
                ? Container(
                    width: detectionZoneSize,
                    height: double.infinity,
                    color: Colors.transparent,
                  )
                : Container(
                    width: double.infinity,
                    height: detectionZoneSize,
                    color: Colors.transparent,
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewContent(BuildContext context, DropZonePosition position) {
    final theme = FluentTheme.of(context);
    
    String label;
    IconData icon;
    
    switch (position) {
      case DropZonePosition.left:
        label = 'New Group\n(Left Split)';
        icon = FluentIcons.chrome_back;
        break;
      case DropZonePosition.right:
        label = 'New Group\n(Right Split)';
        icon = FluentIcons.chrome_back;
        break;
      case DropZonePosition.top:
        label = 'New Group\n(Top Split)';
        icon = FluentIcons.up;
        break;
      case DropZonePosition.bottom:
        label = 'New Group\n(Bottom Split)';
        icon = FluentIcons.down;
        break;
      case DropZonePosition.center:
      default:
        label = 'Add to Group';
        icon = FluentIcons.add;
        break;
    }
    
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.typography.subtitle?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
} 