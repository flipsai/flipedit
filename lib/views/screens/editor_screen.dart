import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/common/resizable_divider.dart';

class EditorScreen extends WatchingStatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorViewModel _editorViewModel;
  double _extensionPanelWidth = 250.0; // Initial width
  final double _minExtensionPanelWidth = 150.0; // Minimum width
  final double _maxExtensionPanelWidth = 500.0; // Maximum width

  @override
  void initState() {
    super.initState();
    
    // Initialize the panel layout
    _editorViewModel = di<EditorViewModel>();
    _editorViewModel.initializePanelLayout();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the selected extension using watchPropertyValue - should work now
    final selectedExtension = watchPropertyValue((EditorViewModel vm) => vm.selectedExtension);
    
    // Get panel definitions for the current layout
    final DockingLayout? initialLayout = _editorViewModel.getInitialLayout();

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: material.Material(
        color: Colors.transparent,
        // No WatchItBuilder needed here, direct conditional logic
        child: Row(
          children: [
            // Left sidebar with extensions (VS Code's activity bar)
            const ExtensionSidebar(),
            
            // Conditionally display the selected extension panel and resize handle
            if (selectedExtension != null && selectedExtension.isNotEmpty) ...[
              SizedBox(
                width: _extensionPanelWidth,
                child: ExtensionPanelContainer(extensionId: selectedExtension),
              ),
              ResizableDivider(
                onDragUpdate: (dx) {
                  setState(() {
                    _extensionPanelWidth = (_extensionPanelWidth + dx)
                        .clamp(_minExtensionPanelWidth, _maxExtensionPanelWidth);
                  });
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
                child: Docking(
                  layout: initialLayout ?? DockingLayout(root: DockingRow([])), 
                  // We might need to add controller/callbacks later if needed
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
