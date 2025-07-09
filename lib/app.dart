import 'dart:io' show Platform;
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flipedit/utils/global_context.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/views/widgets/app_menu_bar.dart';
import 'package:window_manager/window_manager.dart';

class FlipEditApp extends StatelessWidget with WatchItMixin {
  FlipEditApp({super.key, this.navigatorKey});

  final GlobalKey<NavigatorState>? navigatorKey;
  final _logTag = 'FlipEditApp';

  @override
  Widget build(BuildContext context) {
    // Set global context immediately in build method
    GlobalContext.setContext(context);
    logger.logInfo('Global context set in build method', _logTag);

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

    // Determine the root widget based on the platform.
    // For macOS, we wrap the app in a PlatformMenuBar.
    Widget homeWidget = EditorScreen();
    if (Platform.isMacOS || Platform.isWindows) {
      homeWidget = PlatformAppMenuBar(
        editorVm: di<EditorViewModel>(),
        projectVm: di<ProjectViewModel>(),
        timelineVm: di<TimelineViewModel>(),
        child: EditorScreen(),
      );
    }

    return ShadApp.custom(
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadSlateColorScheme.dark(),
      ),
      theme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.light(),
      ),
      themeMode: ThemeMode.dark, // Force dark theme
      appBuilder: (context) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: windowTitle,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.dark, // Force dark theme
        home: homeWidget,
        builder: (context, child) {
          // Update global context whenever it changes
          GlobalContext.setContext(context);
          logger.logInfo('Global context set in app builder', _logTag);
          return ShadAppBuilder(child: child ?? const SizedBox.shrink());
        },
      ),
    );
  }
}
