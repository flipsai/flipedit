import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/common/resizable_divider.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  double _extensionPanelWidth = 250.0; // Initial width
  final double _minExtensionPanelWidth = 150.0; // Minimum width
  final double _maxExtensionPanelWidth = 500.0; // Maximum width

  @override
  void initState() {
    super.initState();
    
    // Initialization call is now async and handled within the ViewModel constructor
    // di<EditorViewModel>().initializePanelLayout(); // Remove this line
  }

  @override
  Widget build(BuildContext context) {
    return _EditorContent(
      extensionPanelWidth: _extensionPanelWidth,
      minExtensionPanelWidth: _minExtensionPanelWidth,
      maxExtensionPanelWidth: _maxExtensionPanelWidth,
      onPanelResized: (newWidth) {
        setState(() {
          _extensionPanelWidth = newWidth;
        });
      },
    );
  }
}

// Separate stateless widget that uses WatchItMixin to handle reactive UI updates
class _EditorContent extends StatelessWidget with WatchItMixin {
  final double extensionPanelWidth;
  final double minExtensionPanelWidth;
  final double maxExtensionPanelWidth;
  final Function(double) onPanelResized;

  const _EditorContent({
    required this.extensionPanelWidth,
    required this.minExtensionPanelWidth,
    required this.maxExtensionPanelWidth,
    required this.onPanelResized,
  });

  @override
  Widget build(BuildContext context) {
    final selectedExtension = watchValue((EditorViewModel vm) => vm.selectedExtensionNotifier);
    final layout = watchValue((EditorViewModel vm) => vm.layoutNotifier);
    
    // No longer need to watch visibility explicitly here, layoutNotifier handles it
    // watchValue((EditorViewModel vm) => vm.isTimelineVisibleNotifier);
    // watchValue((EditorViewModel vm) => vm.isInspectorVisibleNotifier);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: material.Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // Left sidebar with extensions (VS Code's activity bar)
            const ExtensionSidebar(),
            
            // Conditionally display the selected extension panel and resize handle
            if (selectedExtension.isNotEmpty) ...[  
              SizedBox(
                width: extensionPanelWidth,
                child: ExtensionPanelContainer(extensionId: selectedExtension),
              ),
              ResizableDivider(
                onDragUpdate: (dx) {
                  final newWidth = (extensionPanelWidth + dx)
                      .clamp(minExtensionPanelWidth, maxExtensionPanelWidth);
                  onPanelResized(newWidth);
                },
              ),
            ],
            
            // Main content area with docking panels
            Expanded(
              child: MultiSplitViewTheme(
                data: MultiSplitViewThemeData(
                  dividerThickness: 8.0,
                  dividerPainter: DividerPainters.background(
                    // Use theme colors for consistency
                    color: Colors.transparent, // Normal state background
                    highlightedColor: FluentTheme.of(context).accentColor.lighter, // Highlighted state background
                    // You might want a visible line painter overlaid or adjust colors
                  ),
                ),
                child: layout != null
                    ? Docking(
                        // key: ValueKey(di<EditorViewModel>().layoutStructureKey), // Remove dynamic key
                        layout: layout,
                        onItemClose: _handlePanelClosed,
                        // Consider adding onLayoutChanged if available and needed for more fine-grained state saving
                      )
                    : const Center(
                        // Show a more informative loading state
                        child: ProgressRing(), 
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _handlePanelClosed(DockingItem item) {
    // Update the view model based on which panel was closed
    if (item.id == 'inspector') {
      di<EditorViewModel>().markInspectorClosed();
    } else if (item.id == 'timeline') {
      di<EditorViewModel>().markTimelineClosed();
    }
  }
}


