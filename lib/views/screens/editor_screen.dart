import 'package:flutter/material.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/extensions/extension_panel_container.dart';
import 'package:flipedit/views/widgets/extensions/extension_sidebar.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/common/resizable_divider.dart';
import 'package:flutter/services.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/commands/remove_clip_command.dart';
import 'package:flipedit/views/widgets/tab_system_widget.dart';
import 'package:flipedit/viewmodels/tab_system_viewmodel.dart';
import 'package:flipedit/services/tab_content_factory.dart';

class EditorScreen extends StatelessWidget with WatchItMixin {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const ExtensionSidebar(),

          const _ConditionalExtensionPanel(),

          Expanded(
            child: Focus(
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: _buildEditorContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorContent(BuildContext context) {
    return FutureBuilder<TabSystemViewModel>(
      future: di.getAsync<TabSystemViewModel>(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading tab system: ${snapshot.error}'),
          );
        }
        
        final tabSystem = snapshot.data!;
        
        return ListenableBuilder(
          listenable: tabSystem.tabLinesNotifier,
          builder: (context, child) {
            // Initialize default tabs if empty
            if (tabSystem.tabGroups.isEmpty || tabSystem.getAllTabs().isEmpty) {
              _createDefaultTabs();
            }
            
            return TabSystemWidget(
              onTabSelected: (tabId) {
                logInfo('Tab selected: $tabId', 'EditorScreen');
              },
              onTabClosed: (tabId) {
                logInfo('Tab closed: $tabId', 'EditorScreen');
              },
            );
          },
        );
      },
    );
  }

  void _createDefaultTabs() {
    final tabSystem = di<TabSystemViewModel>();
    
    // Check if already initialized with tabs
    if (tabSystem.tabGroups.isNotEmpty && tabSystem.getAllTabs().isNotEmpty) {
      return;
    }
    
    // Create main editor tabs
    final previewTab = TabContentFactory.createVideoTab(
      id: 'preview',
      title: 'Preview',
      isModified: false,
    );
    
    final inspectorTab = TabContentFactory.createDocumentTab(
      id: 'inspector',
      title: 'Inspector', 
      isModified: false,
    );

    // Add initial tabs to create the first group
    tabSystem.addTab(previewTab);
    tabSystem.addTab(inspectorTab);

    // Create vertical layout with timeline at bottom
    tabSystem.createTerminalGroup();
    
    // Create timeline tab for the terminal group
    final timelineTab = TabContentFactory.createAudioTab(
      id: 'timeline', 
      title: 'Timeline',
      isModified: false,
    );

    // Add timeline to the terminal group if we have at least 2 groups
    if (tabSystem.tabGroups.length >= 2) {
      final terminalGroupId = tabSystem.tabGroups.last.id;
      tabSystem.addTab(timelineTab, targetGroupId: terminalGroupId);
    } else {
      // Fallback: just add to the main group if terminal group creation failed
      tabSystem.addTab(timelineTab);
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
        if (focusedWidget is TextField ||
            focusedWidget is TextFormField ||
            primaryFocus.context?.findAncestorWidgetOfExactType<TextField>() !=
                null ||
            primaryFocus.context
                    ?.findAncestorWidgetOfExactType<TextFormField>() !=
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

