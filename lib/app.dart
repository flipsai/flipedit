import 'dart:io' show Platform;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:flipedit/views/screens/welcome_screen.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/app_menu_bar.dart';

class FlipEditApp extends fluent.StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Watch values
    final isInitialized = watchValue((AppViewModel vm) => vm.isInitializedNotifier);
    final isInspectorVisible = watchValue((EditorViewModel vm) => vm.isInspectorVisibleNotifier);
    final isTimelineVisible = watchValue((EditorViewModel vm) => vm.isTimelineVisibleNotifier);
    // Get ViewModels needed for menu actions
    final editorVm = di<EditorViewModel>();
    final projectVm = di<ProjectViewModel>();

    // Determine the root widget based on Platform
    Widget homeWidget; 
    final Widget mainContent = isInitialized ? const EditorScreen() : const WelcomeScreen();

    if (Platform.isMacOS || Platform.isWindows) {
      // --- macOS / Windows: Use PlatformAppMenuBar --- 
      homeWidget = PlatformAppMenuBar(
        isInspectorVisible: isInspectorVisible,
        isTimelineVisible: isTimelineVisible,
        editorVm: editorVm,
        projectVm: projectVm,
        child: mainContent, // Pass main content as child
      );
    } else {
       // --- Linux / Other: Use Fluent UI Structure with FluentAppMenuBar ---
       homeWidget = fluent.ScaffoldPage(
        content: fluent.NavigationView(
          appBar: fluent.NavigationAppBar(
            title: const fluent.Text('FlipEdit'),
            // Instantiate FluentAppMenuBar for the actions
            actions: FluentAppMenuBar(
              isInspectorVisible: isInspectorVisible,
              isTimelineVisible: isTimelineVisible,
              editorVm: editorVm,
              projectVm: projectVm,
            ),
          ),
          content: mainContent, // Place main content here
        ),
      );
    }

    // Return the FluentApp with the determined home widget
    return fluent.FluentApp(
      title: 'FlipEdit',
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
      home: homeWidget, // Use the conditionally built widget
    );
  }
}
