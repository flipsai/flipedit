import 'dart:io' show Platform;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/app_menu_bar.dart';
import 'package:window_manager/window_manager.dart';

class FlipEditApp extends fluent.StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  @override
  fluent.Widget build(fluent.BuildContext context) {
    final editorVm = di<EditorViewModel>();
    final projectVm = di<ProjectViewModel>();
    final timelineVm = di<TimelineViewModel>();

    final currentProject = watchValue(
      (ProjectViewModel vm) => vm.currentProjectNotifier,
    );

    final String windowTitle =
        currentProject != null
            ? '${currentProject.name} - FlipEdit'
            : 'FlipEdit';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      windowManager.setTitle(windowTitle);
    });

    Widget homeWidget;
    const bool isTestMode = bool.fromEnvironment('TEST_MODE');

    if ((Platform.isMacOS || Platform.isWindows) && !isTestMode) {
      homeWidget = PlatformAppMenuBar(
        editorVm: editorVm,
        projectVm: projectVm,
        timelineVm: timelineVm,
        child: const EditorScreen(),
      );
    } else {
      homeWidget = fluent.NavigationView(
        appBar: fluent.NavigationAppBar(
          title: const fluent.Text('FlipEdit'),
          actions: FluentAppMenuBar(
            editorVm: editorVm,
            projectVm: projectVm,
            timelineVm: timelineVm,
          ),
        ),
        content: const EditorScreen(),
      );
    }

    return fluent.FluentApp(
      title: windowTitle,
      theme: fluent.FluentThemeData(
        accentColor: fluent.Colors.blue,
        brightness: fluent.Brightness.light,
        visualDensity: fluent.VisualDensity.standard,
        focusTheme: fluent.FocusThemeData(glowFactor: 4.0),
      ),
      darkTheme: fluent.FluentThemeData(
        accentColor: fluent.Colors.blue,
        brightness: fluent.Brightness.dark,
        visualDensity: fluent.VisualDensity.standard,
        focusTheme: fluent.FocusThemeData(glowFactor: 4.0),
      ),
      themeMode: fluent.ThemeMode.system,
      home: homeWidget,
    );
  }
}
