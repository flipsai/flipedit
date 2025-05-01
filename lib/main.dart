import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure window_manager is initialized for desktop platforms
  await windowManager.ensureInitialized();

  // Set up dependency injection
  await setupServiceLocator();

  // Initialize UvManager
  try {
    final uvManager = di.get<UvManager>();
    await uvManager.initialize();
    logInfo('main', 'UvManager initialized successfully');
  } catch (e) {
    logError('main', 'Failed to initialize UvManager: $e');
    // Continue app execution even if UV initialization fails
  }

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
