import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/common/resizable_divider.dart';

// Convert EditorScreen to StatelessWidget as state is moved down
class EditorScreen extends StatelessWidget with WatchItMixin {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = watchValue((EditorViewModel vm) => vm.layoutNotifier);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: material.Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // Left sidebar with extensions (VS Code's activity bar)
            const ExtensionSidebar(),

            const _ConditionalExtensionPanel(),

            // Main content area with docking panels
            Expanded(
              child: MultiSplitViewTheme(
                data: MultiSplitViewThemeData(
                  dividerThickness: 8.0,
                  dividerPainter: DividerPainters.background(
                    color:
                        FluentTheme.of(
                          context,
                        ).resources.subtleFillColorTertiary,
                    highlightedColor:
                        FluentTheme.of(
                          context,
                        ).resources.subtleFillColorSecondary,
                  ),
                ),
                child: TabbedViewTheme(
                  data: TabbedViewThemeData.dark(),
                  child:
                      layout != null
                          ? Docking(
                            layout: layout,
                            onItemClose: _handlePanelClosed,
                          )
                          : const Center(child: ProgressRing()),
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

class _ConditionalExtensionPanel extends StatefulWidget {
  const _ConditionalExtensionPanel();

  @override
  State<_ConditionalExtensionPanel> createState() =>
      _ConditionalExtensionPanelState();
}

class _ConditionalExtensionPanelState extends State<_ConditionalExtensionPanel> {
  double _extensionPanelWidth = 250.0; // Initial width
  final double _minExtensionPanelWidth = 150.0; // Minimum width
  final double _maxExtensionPanelWidth = 500.0; // Maximum width

  // Callback function to update the width
  void _updateWidth(double dx) {
    setState(() {
      _extensionPanelWidth = (_extensionPanelWidth + dx).clamp(
        _minExtensionPanelWidth,
        _maxExtensionPanelWidth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pass the current width and the update function to the internal widget
    return _ExtensionPanelInternal(
      width: _extensionPanelWidth,
      onResize: _updateWidth,
    );
  }
}

class _ExtensionPanelInternal extends StatelessWidget with WatchItMixin {
  final double width;
  final Function(double) onResize;

  const _ExtensionPanelInternal({
    required this.width,
    required this.onResize,
  });

  @override
  Widget build(BuildContext context) {
    // Watch the value here using the mixin
    final selectedExtension = watchValue(
      (EditorViewModel vm) => vm.selectedExtensionNotifier,
    );

    // Return the panel and divider row only if an extension is selected
    if (selectedExtension.isNotEmpty) {
      return Row(
        mainAxisSize:
            MainAxisSize.min, // Important to prevent Row taking extra space
        children: [
          SizedBox(
            width: width, // Use width passed from parent stateful widget
            child: ExtensionPanelContainer(extensionId: selectedExtension),
          ),
          ResizableDivider(
            onDragUpdate: onResize, // Use callback passed from parent
          ),
        ],
      );
    } else {
      // Return an empty container when no extension is selected
      return const SizedBox.shrink();
    }
  }
}
