import 'dart:io' show Platform;
import 'package:flipedit/views/widgets/preview/composite_preview_example_demo.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart'; // Import WidgetsBinding
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/app_menu_bar.dart';
import 'package:window_manager/window_manager.dart'; // Import window_manager

class FlipEditApp extends fluent.StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Get ViewModels needed for menu actions and title
    final editorVm = di<EditorViewModel>();
    final projectVm = di<ProjectViewModel>();
    final timelineVm = di<TimelineViewModel>();

    // Watch the current project
    final currentProject = watchValue((ProjectViewModel vm) => vm.currentProjectNotifier);

    // Determine the window title and update the native window
    final String windowTitle = currentProject != null
        ? '${currentProject.name} - FlipEdit'
        : 'FlipEdit';
    
    // Use window_manager to set the actual window title
    // We use a post-frame callback to avoid setting state during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      windowManager.setTitle(windowTitle);
    });

    // Determine the root widget based on Platform and test mode
    Widget homeWidget;
    const bool isTestMode = bool.fromEnvironment('TEST_MODE');

    if ((Platform.isMacOS || Platform.isWindows) && !isTestMode) {
      // --- macOS / Windows (Non-Test): Use PlatformAppMenuBar ---
      homeWidget = PlatformAppMenuBar(
        editorVm: editorVm,
        projectVm: projectVm,
        timelineVm: timelineVm,
        child: const EditorScreen(), // Pass main content as child
      );
    } else {
       // --- Linux / Other: Use Fluent UI Structure with FluentAppMenuBar ---
       homeWidget = fluent.NavigationView(
          appBar: fluent.NavigationAppBar(
            title: const fluent.Text('FlipEdit'),
            // Instantiate FluentAppMenuBar for the actions
            actions: FluentAppMenuBar(
              editorVm: editorVm,
              projectVm: projectVm,
              timelineVm: timelineVm,
            ),
          ),
          content: const EditorScreen(), // Place main content here
      );
    }

    // Return the FluentApp with the determined home widget and dynamic title
    return fluent.FluentApp(
      title: windowTitle, // Keep this for fallback/other platforms
      theme: fluent.FluentThemeData(
        accentColor: fluent.Colors.blue,
        brightness: fluent.Brightness.light,
        visualDensity: fluent.VisualDensity.standard,
        focusTheme: fluent.FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      darkTheme: fluent.FluentThemeData(
        accentColor: fluent.Colors.blue,
        brightness: fluent.Brightness.dark,
        visualDensity: fluent.VisualDensity.standard,
        focusTheme: fluent.FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      themeMode: fluent.ThemeMode.system,
      home: CompositePreviewDemo(), // Use the conditionally built widget
    );
  }
}
