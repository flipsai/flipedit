import 'dart:io' show Platform;
import 'package:flipedit/views/demo_tab_system_view.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flipedit/utils/global_context.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/app_menu_bar.dart';
import 'package:window_manager/window_manager.dart';

class FlipEditApp extends fluent.StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  final _logTag = 'FlipEditApp';

  @override
  fluent.Widget build(fluent.BuildContext context) {
    // Set global context immediately in build method
    GlobalContext.setContext(context);
    logger.logInfo('Global context set in build method', _logTag);

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

      // Ensure global context is still valid
      GlobalContext.setContext(context);
      logger.logInfo(
        'Global context refreshed in post-frame callback',
        _logTag,
      );
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
      builder: (context, child) {
        // Update global context whenever it changes
        GlobalContext.setContext(context);
        logger.logInfo('Global context set in app builder', _logTag);
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
