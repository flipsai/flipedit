import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show PlatformMenuBar, PlatformMenu, PlatformMenuItem;
import 'package:flutter/services.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:flipedit/views/screens/welcome_screen.dart';
import 'package:watch_it/watch_it.dart';

class FlipEditApp extends StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use watch_it's data binding to observe properties
    final isInitialized = watchValue((AppViewModel vm) => vm.isInitializedNotifier);
    final isInspectorVisible = watchValue((EditorViewModel vm) => vm.isInspectorVisibleNotifier);
    final isTimelineVisible = watchValue((EditorViewModel vm) => vm.isTimelineVisibleNotifier);
    
    return FluentApp(
      title: 'FlipEdit',
      theme: FluentThemeData(
        accentColor: Colors.blue,
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
        focusTheme: FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      darkTheme: FluentThemeData(
        accentColor: Colors.blue,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        focusTheme: FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: PlatformMenuBar(
        menus: [
              PlatformMenu(
                label: 'File',
                menus: [
                  PlatformMenuItem(
                    label: 'New Project',
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
                    onSelected: () {
                      // Handle new project
                    },
                  ),
                  PlatformMenuItem(
                    label: 'Open Project...',
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
                    onSelected: () {
                      // Handle open project
                    },
                  ),
                  PlatformMenuItem(
                    label: 'Save Project',
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
                    onSelected: () {
                      di<ProjectViewModel>().saveProject();
                    },
                  ),
                ],
              ),
              PlatformMenu(
                label: 'Edit',
                menus: [
                  PlatformMenuItem(label: 'Undo', onSelected: () {
                     // TODO: Implement Undo
                  }),
                  PlatformMenuItem(label: 'Redo', onSelected: () {
                     // TODO: Implement Redo
                  }),
                ],
              ),
              PlatformMenu(
                label: 'View',
                menus: [
                  PlatformMenuItem(
                    label: isInspectorVisible ? '✓ Inspector' : '  Inspector',
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
                    onSelected: () {
                      di<EditorViewModel>().toggleInspector();
                    },
                  ),
                  PlatformMenuItem(
                    label: isTimelineVisible ? '✓ Timeline' : '  Timeline',
                    shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
                    onSelected: () {
                      di<EditorViewModel>().toggleTimeline();
                    },
                  ),
                ],
              ),
            ],
        child: isInitialized ? const EditorScreen() : const WelcomeScreen(),
      ),
    );
  }
}
