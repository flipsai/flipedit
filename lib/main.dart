import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
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
  await setupServiceLocator();

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

  runApp(FlipEditApp());
}
