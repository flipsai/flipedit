import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/utils/texture_bridge_check.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/material.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/utils/global_context.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/src/rust/frb_generated.dart';

// Define a class to handle window events by implementing WindowListener
class _MyWindowListener implements WindowListener {
  @override
  void onWindowClose() async {
    logInfo('main', 'Window close requested. Shutting down video server...');
    await windowManager.destroy();
  }

  // Add empty implementations for all other required methods
  @override
  void onWindowBlur() {}
  @override
  void onWindowDocked() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowEvent(String eventName) {}
  @override
  void onWindowFocus() {}
  @override
  void onWindowLeaveFullScreen() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowMoved() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowResized() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowUndocked() {}
  @override
  void onWindowUnmaximize() {}
}

Future<void> main() async {
  await RustLib.init();
  WidgetsFlutterBinding.ensureInitialized();

  // Note: Irondash engine context is initialized automatically when needed
  logInfo('main', 'Irondash engine context ready');


  // Ensure window_manager is initialized for desktop platforms
  await windowManager.ensureInitialized();

  // Add the window listener
  final _MyWindowListener myWindowListener = _MyWindowListener();
  windowManager.addListener(myWindowListener);
  // Prevent default close behavior so our listener can handle it
  await windowManager.setPreventClose(true);

  // Configure window options
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 800), // Example size, adjust as needed
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  // Show the window when ready
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Set up dependency injection
  await setupServiceLocator();
  
  // Check and setup texture bridge
  final textureBridgeAvailable = await TextureBridgeChecker.checkTextureBridge();
  if (!textureBridgeAvailable) {
    logWarning('main', 'Texture bridge not available, Python-based rendering may not work properly');
  } else {
    logInfo('main', 'Texture bridge is available for Python-based rendering');
  }

  // UvManager is initialized asynchronously via its registration in service_locator.dart
  // We can wait for it to be ready if needed for subsequent steps,
  // or let parts of the app that depend on it (like OpenCvPythonPlayerViewModel)
  // await its readiness.
  // For now, we'll let dependent components handle awaiting.
  // If an error occurs during UvManager.initialize(), it will be caught by
  // di.getAsync<UvManager>() or di.isReady<UvManager>().

  // Ensure ViewModels are accessible to watch_it and load last project
  // Make sure ProjectViewModel is registered before trying to use it
  try {
    final projectVm = di.get<ProjectViewModel>(); // Get the instance
    await projectVm.loadLastOpenedProjectCommand(); // Load the last project
  } catch (e) {
    logError('main', "Error loading last project: $e");
    // Handle error appropriately, maybe show a message to the user
  }

  // debugRepaintRainbowEnabled = true;

  // Create a global navigator key to access BuildContext
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Create a wrapper MaterialApp to ensure global context is accessible early
  final app = MaterialApp(
    navigatorKey: navigatorKey,
    // Apply theme to match the main app
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
      visualDensity: VisualDensity.standard,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
      visualDensity: VisualDensity.standard,
    ),
    themeMode: ThemeMode.dark, // Force dark theme
    home: Builder(
      builder: (context) {
        // Set global context as early as possible in the app lifecycle
        GlobalContext.setContext(context);
        logInfo('main', 'Global context initialized in wrapper app');
        return FlipEditApp();
      },
    ),
  );

  runApp(app);
  
  // Ensure GlobalContext is set after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (navigatorKey.currentContext != null) {
      GlobalContext.setContext(navigatorKey.currentContext!);
      logInfo('main', 'Global context refreshed after first frame');
    }
  });
}
