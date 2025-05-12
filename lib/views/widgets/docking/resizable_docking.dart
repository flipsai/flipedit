import 'package:flutter/widgets.dart';
import 'package:docking/docking.dart';
import 'package:flipedit/viewmodels/editor/editor_layout_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// A wrapper around the Docking widget that handles saving dimensions after layout changes
class ResizableDocking extends StatefulWidget {
  /// The docking layout
  final DockingLayout? layout;
  
  /// Callback for item selection
  final OnItemSelection? onItemSelection;
  
  /// Callback for item close
  final OnItemClose? onItemClose;
  
  /// Interceptor for item close
  final ItemCloseInterceptor? itemCloseInterceptor;
  
  /// Builder for docking buttons
  final DockingButtonsBuilder? dockingButtonsBuilder;
  
  /// Whether items are maximizable
  final bool maximizableItem;
  
  /// Whether tabs are maximizable
  final bool maximizableTab;
  
  /// Whether tabs areas are maximizable
  final bool maximizableTabsArea;
  
  /// Anti-aliasing workaround flag
  final bool antiAliasingWorkaround;
  
  /// Whether the layout is draggable
  final bool draggable;

  const ResizableDocking({
    Key? key,
    this.layout,
    this.onItemSelection,
    this.onItemClose,
    this.itemCloseInterceptor,
    this.dockingButtonsBuilder,
    this.maximizableItem = true,
    this.maximizableTab = true,
    this.maximizableTabsArea = true,
    this.antiAliasingWorkaround = true,
    this.draggable = true,
  }) : super(key: key);

  @override
  State<ResizableDocking> createState() => _ResizableDockingState();
}

class _ResizableDockingState extends State<ResizableDocking> {
  final EditorLayoutViewModel _layoutViewModel = di<EditorViewModel>().layoutManager;
  
  @override
  void initState() {
    super.initState();
    if (widget.layout != null) {
      widget.layout!.addListener(_onLayoutChanged);
    }
  }
  
  @override
  void didUpdateWidget(ResizableDocking oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      oldWidget.layout?.removeListener(_onLayoutChanged);
      widget.layout?.addListener(_onLayoutChanged);
    }
  }
  
  @override
  void dispose() {
    widget.layout?.removeListener(_onLayoutChanged);
    super.dispose();
  }
  
  void _onLayoutChanged() {
    // Save the complete layout when it changes
    _layoutViewModel.updateAreaDimensions();
  }
  
  @override
  Widget build(BuildContext context) {
    return Docking(
      layout: widget.layout,
      onItemSelection: widget.onItemSelection,
      onItemClose: (item) {
        // When an item is closed, make sure to save the layout
        if (widget.onItemClose != null) {
          widget.onItemClose!(item);
        }
        // Save layout after close
        _layoutViewModel.updateAreaDimensions();
      },
      itemCloseInterceptor: widget.itemCloseInterceptor,
      dockingButtonsBuilder: widget.dockingButtonsBuilder,
      maximizableItem: widget.maximizableItem,
      maximizableTab: widget.maximizableTab,
      maximizableTabsArea: widget.maximizableTabsArea,
      antiAliasingWorkaround: widget.antiAliasingWorkaround,
      draggable: widget.draggable,
      onAreaDimensionsChange: (DockingArea area) {
        // Save layout when dimensions change
        _layoutViewModel.updateAreaDimensions();
      },
    );
  }
} 