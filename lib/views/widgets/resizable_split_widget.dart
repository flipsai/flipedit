import 'package:fluent_ui/fluent_ui.dart';

class ResizableSplitItem {
  final Widget child;
  final double initialWeight;
  final double minSize;
  final double maxSize;

  const ResizableSplitItem({
    required this.child,
    this.initialWeight = 1.0,
    this.minSize = 100.0,
    this.maxSize = double.infinity,
  });
}

class ResizableSplitWidget extends StatefulWidget {
  final List<ResizableSplitItem> children;
  final Axis axis;
  final double dividerWidth;
  final Color? dividerColor;
  final Function(List<double> weights)? onWeightsChanged;

  const ResizableSplitWidget({
    super.key,
    required this.children,
    this.axis = Axis.horizontal,
    this.dividerWidth = 4.0,
    this.dividerColor,
    this.onWeightsChanged,
  });

  @override
  State<ResizableSplitWidget> createState() => _ResizableSplitWidgetState();
}

class _ResizableSplitWidgetState extends State<ResizableSplitWidget> {
  late List<double> _weights;
  late List<GlobalKey> _childKeys;

  @override
  void initState() {
    super.initState();
    _weights = widget.children.map((child) => child.initialWeight).toList();
    _childKeys = widget.children.map((child) => GlobalKey()).toList();
    _normalizeWeights();
  }

  @override
  void didUpdateWidget(ResizableSplitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.children.length != oldWidget.children.length) {
      _weights = widget.children.map((child) => child.initialWeight).toList();
      _childKeys = widget.children.map((child) => GlobalKey()).toList();
      _normalizeWeights();
    }
  }

  void _normalizeWeights() {
    if (_weights.isEmpty) return;
    
    final totalWeight = _weights.fold(0.0, (sum, weight) => sum + weight);
    if (totalWeight > 0) {
      _weights = _weights.map((weight) => weight / totalWeight).toList();
    }
  }

  void _updateWeights(int dividerIndex, double delta) {
    if (dividerIndex < 0 || dividerIndex >= _weights.length - 1) return;

    setState(() {
      final leftIndex = dividerIndex;
      final rightIndex = dividerIndex + 1;
      
      final leftWeight = _weights[leftIndex];
      final rightWeight = _weights[rightIndex];
      
      final totalWeight = leftWeight + rightWeight;
      final newLeftWeight = (leftWeight + delta).clamp(0.1, totalWeight - 0.1);
      final newRightWeight = totalWeight - newLeftWeight;
      
      _weights[leftIndex] = newLeftWeight;
      _weights[rightIndex] = newRightWeight;
    });
    
    // Notify about weight changes
    widget.onWeightsChanged?.call(List.from(_weights));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final dividerColor = widget.dividerColor ?? 
        theme.resources.cardStrokeColorDefault.withValues(alpha: 0.3);

    if (widget.children.isEmpty) {
      return const SizedBox.shrink();
    }

    if (widget.children.length == 1) {
      return widget.children.first.child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableSpace = widget.axis == Axis.horizontal 
            ? constraints.maxWidth 
            : constraints.maxHeight;
        
        final dividerCount = widget.children.length - 1;
        final totalDividerSpace = dividerCount * widget.dividerWidth;
        final contentSpace = availableSpace - totalDividerSpace;

        if (contentSpace <= 0) {
          return const SizedBox.shrink();
        }

        return Flex(
          direction: widget.axis,
          children: _buildChildren(contentSpace, dividerColor),
        );
      },
    );
  }

  List<Widget> _buildChildren(double contentSpace, Color dividerColor) {
    final List<Widget> children = [];

    for (int i = 0; i < widget.children.length; i++) {
      final child = widget.children[i];
      final weight = _weights[i];
      final size = contentSpace * weight;

      children.add(
        SizedBox(
          key: _childKeys[i],
          width: widget.axis == Axis.horizontal ? size : null,
          height: widget.axis == Axis.vertical ? size : null,
          child: child.child,
        ),
      );

      if (i < widget.children.length - 1) {
        children.add(_buildDivider(i, dividerColor));
      }
    }

    return children;
  }

  Widget _buildDivider(int index, Color color) {
    return GestureDetector(
      onPanUpdate: (details) {
        final delta = widget.axis == Axis.horizontal 
            ? details.delta.dx 
            : details.delta.dy;
        
        final totalWeight = _weights[index] + _weights[index + 1];
        final normalizedDelta = delta / 1000.0 * totalWeight;
        
        _updateWeights(index, normalizedDelta);
      },
      child: MouseRegion(
        cursor: widget.axis == Axis.horizontal 
            ? SystemMouseCursors.resizeColumn 
            : SystemMouseCursors.resizeRow,
        child: Container(
          width: widget.axis == Axis.horizontal ? widget.dividerWidth : null,
          height: widget.axis == Axis.vertical ? widget.dividerWidth : null,
          color: color,
          child: Center(
            child: Container(
              width: widget.axis == Axis.horizontal ? 1 : double.infinity,
              height: widget.axis == Axis.vertical ? 1 : double.infinity,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
} 