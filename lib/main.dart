import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:fvp/fvp.dart';
import 'package:window_manager/window_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart';
// import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure window_manager is initialized for desktop platforms
  await windowManager.ensureInitialized();


  // Initialize FVP/MDK with registerWith
  try {
    logInfo('main', "Initializing FVP/MDK...");
    // Register FVP to be used as the backend for video_player
    registerWith(); // Use default options when integrating with video_player
    logInfo('main', "FVP/MDK Initialized Successfully!");
  } catch (e) {
    logError('main', "Error initializing FVP/MDK: $e");
  }

  // Set up dependency injection
  setupServiceLocator();

  // Ensure TimelineViewModel is accessible to watch_it
  // This line is important to make sure the type is registered
  di.get<TimelineViewModel>();

  // debugRepaintRainbowEnabled = true;

  runApp(FlipEditApp());
}
