import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/common/resizable_divider.dart';
import 'package:flutter/services.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/commands/remove_clip_command.dart';
import 'package:flipedit/views/widgets/docking/resizable_docking.dart';

class EditorScreen extends StatelessWidget with WatchItMixin {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = watchValue((EditorViewModel vm) => vm.layoutNotifier);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Row(
        children: [
          const ExtensionSidebar(),

          const _ConditionalExtensionPanel(),

          Expanded(
            child: MultiSplitViewTheme(
              data: MultiSplitViewThemeData(
                dividerThickness: 8.0,
                dividerPainter: DividerPainters.background(
                  color:
                      FluentTheme.of(context).resources.subtleFillColorTertiary,
                  highlightedColor:
                      FluentTheme.of(
                        context,
                      ).resources.subtleFillColorSecondary,
                ),
              ),
              child: TabbedViewTheme(
                data: TabbedViewThemeData.dark(),
                child: Focus(
                  autofocus: true,
                  onKeyEvent: _handleKeyEvent,
                  child:
                      layout != null
                          ? ResizableDocking(
                            layout: layout,
                            onItemClose: _handlePanelClosed,
                          )
                          : const Center(child: ProgressRing()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handlePanelClosed(DockingItem item) {
    if (item.id == 'inspector') {
      di<EditorViewModel>().markInspectorClosed();
    } else if (item.id == 'timeline') {
      di<EditorViewModel>().markTimelineClosed();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    logDebug(
      'Key event received: ${event.runtimeType}, LogicalKey: ${event.logicalKey}',
      'EditorScreen',
    );
    logDebug('Focus hasPrimaryFocus: ${node.hasPrimaryFocus}', 'EditorScreen');

    // Check for both Delete and Backspace keys
    final isDeleteKey =
        event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace;

    if (event is KeyDownEvent && isDeleteKey) {
      logInfo('Delete/Backspace key pressed', 'EditorScreen');

      // Check if there's any text input field focused
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus != null) {
        final focusedWidget = primaryFocus.context?.widget;
        // Don't process delete key if a text field has focus
        if (focusedWidget is TextBox ||
            focusedWidget is TextFormBox ||
            focusedWidget is NumberBox ||
            primaryFocus.context?.findAncestorWidgetOfExactType<TextBox>() !=
                null ||
            primaryFocus.context
                    ?.findAncestorWidgetOfExactType<TextFormBox>() !=
                null ||
            primaryFocus.context?.findAncestorWidgetOfExactType<NumberBox>() !=
                null) {
          logDebug(
            'Ignoring delete key as text field has focus',
            'EditorScreen',
          );
          return KeyEventResult.ignored;
        }
      }

      final editorVm = di<EditorViewModel>();
      final timelineVm = di<TimelineViewModel>();
      final selectedIdString = editorVm.selectedClipId;
      logDebug('Selected Clip ID: $selectedIdString', 'EditorScreen');

      if (selectedIdString != null && selectedIdString.isNotEmpty) {
        final clipId = int.tryParse(selectedIdString);
        logDebug('Parsed Clip ID: $clipId', 'EditorScreen');
        if (clipId != null) {
          logInfo('Running RemoveClipCommand for ID: $clipId', 'EditorScreen');
          final cmd = RemoveClipCommand(vm: timelineVm, clipId: clipId);
          timelineVm.runCommand(cmd);
          editorVm.selectedClipId = null; // Deselect after deletion
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }
}

class _ConditionalExtensionPanel extends StatefulWidget {
  const _ConditionalExtensionPanel();

  @override
  State<_ConditionalExtensionPanel> createState() =>
      _ConditionalExtensionPanelState();
}

class _ConditionalExtensionPanelState
    extends State<_ConditionalExtensionPanel> {
  double _extensionPanelWidth = 250.0;
  final double _minExtensionPanelWidth = 150.0;
  final double _maxExtensionPanelWidth = 500.0;

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
    return _ExtensionPanelInternal(
      width: _extensionPanelWidth,
      onResize: _updateWidth,
    );
  }
}

class _ExtensionPanelInternal extends StatelessWidget with WatchItMixin {
  final double width;
  final Function(double) onResize;

  const _ExtensionPanelInternal({required this.width, required this.onResize});

  @override
  Widget build(BuildContext context) {
    final selectedExtension = watchValue(
      (EditorViewModel vm) => vm.selectedExtensionNotifier,
    );

    if (selectedExtension.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            child: ExtensionPanelContainer(
              selectedExtension: selectedExtension,
            ),
          ),
          ResizableDivider(onDragUpdate: onResize),
        ],
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
