import 'dart:io';

import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter/foundation.dart'; // Required for kIsWeb
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart'; // Added import for window_manager mocking
import 'package:integration_test/integration_test.dart'; // For IntegrationTestWidgetsFlutterBinding
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

// --- Mock PathProviderPlatform START ---
class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String temporaryPath;

  FakePathProviderPlatform(this.temporaryPath);

  @override
  Future<String?> getTemporaryPath() async {
    return temporaryPath;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    final supportPath = p.join(temporaryPath, 'support');
    await Directory(supportPath).create(recursive: true);
    return supportPath;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    final docsPath = p.join(temporaryPath, 'documents');
    await Directory(docsPath).create(recursive: true);
    return docsPath;
  }

  @override
  Future<String?> getLibraryPath() async {
    final libPath = p.join(temporaryPath, 'library');
    await Directory(libPath).create(recursive: true);
    return libPath;
  }

  @override
  Future<String?> getExternalStoragePath() async {
    // Simulate null for platforms where it might be null
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return null;
    }
    final externalPath = p.join(temporaryPath, 'external');
    await Directory(externalPath).create(recursive: true);
    return externalPath;
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    final cachePath = p.join(temporaryPath, 'cache');
    await Directory(cachePath).create(recursive: true);
    return [cachePath];
  }

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async {
    // Simulate null for platforms where it might be null
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return null;
    }
    final storagePath = p.join(
      temporaryPath,
      'storage',
      type?.toString() ?? 'default',
    );
    await Directory(storagePath).create(recursive: true);
    return [storagePath];
  }

  @override
  Future<String?> getDownloadsPath() async {
    // Simulate null for platforms where it might be null
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      // These platforms might return null if the directory doesn't exist or isn't configured
      // For testing, we'll provide a path, but be aware it might be null in reality.
    }
    final downloadsPath = p.join(temporaryPath, 'downloads');
    await Directory(downloadsPath).create(recursive: true);
    return downloadsPath;
  }
}
// --- Mock PathProviderPlatform END ---

// Helper function to ensure SharedPreferences work in tests
void setupTestSharedPreferences() {
  // Set mock initial values for SharedPreferences testing
  SharedPreferences.setMockInitialValues({});
}

// Helper function to mock window_manager plugin so that tests don't fail due to MissingPluginException
void setupMockWindowManager() {
  const MethodChannel channel = MethodChannel('window_manager');

  // Map to store window state
  final windowState = {
    'visible': true,
    'focused': true,
    'size': {'width': 1280.0, 'height': 800.0},
    'position': {'x': 0.0, 'y': 0.0},
    'title': 'FlipEdit Test',
  };

  // Provide actual implementations for common window_manager methods
  channel.setMockMethodCallHandler((MethodCall methodCall) async {
    logInfo('Window manager call: ${methodCall.method}');

    switch (methodCall.method) {
      case 'show':
        windowState['visible'] = true;
        return true;
      case 'hide':
        windowState['visible'] = false;
        return true;
      case 'focus':
        windowState['focused'] = true;
        return true;
      case 'setTitle':
        windowState['title'] = methodCall.arguments;
        return true;
      case 'setSize':
        final args = methodCall.arguments as Map;
        windowState['size'] = {
          'width': args['width'],
          'height': args['height'],
        };
        return true;
      case 'getSize':
        return windowState['size'];
      case 'isVisible':
        return windowState['visible'];
      case 'isFocused':
        return windowState['focused'];
      case 'waitUntilReadyToShow':
        return true;
      // Add more method handlers as needed
      default:
        logInfo('Unhandled window_manager method: ${methodCall.method}');
        return null;
    }
  });
}

// Helper to set a minimum window size for tests to prevent RenderFlex overflows
void setupMinTestWindowSize({
  Size minSize = const Size(1280, 800),
  double devicePixelRatio = 1.0,
}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.views.first.physicalSize = minSize;
  binding.platformDispatcher.views.first.devicePixelRatio = devicePixelRatio;
}

// Helper function for DI setup
Future<void> setupTestDependencyInjection() async {
  // Ensure SharedPreferences are mocked before DI setup uses them
  setupTestSharedPreferences();
  // Call the correct DI setup function from its file
  await setupServiceLocator();
}

// Function to clean up databases and DI before/after tests
Future<void> cleanupTestState(String tempDirPath) async {
  logInfo('--- Starting Cleanup ---');
  try {
    // Close any active project in services that hold state
    try {
      // Check registration before accessing to avoid errors if DI was reset improperly
      if (di.isRegistered<ProjectViewModel>()) {
        logInfo('Checked ProjectViewModel registration during cleanup.');
      }
      if (di.isRegistered<ProjectMetadataService>()) {
        final metaService = di<ProjectMetadataService>();
        await metaService
            .closeProject(); // Close any open project DB connection
        logInfo('Closed current project database in ProjectMetadataService.');
      } else {
        logInfo('ProjectMetadataService not registered during cleanup.');
      }
      if (di.isRegistered<ProjectDatabaseService>()) {
        final dbService = di<ProjectDatabaseService>();
        await dbService
            .closeCurrentProject(); // Ensure this service is also reset
        logInfo('Closed current project in ProjectDatabaseService.');
      } else {
        logInfo('ProjectDatabaseService not registered during cleanup.');
      }
    } catch (e) {
      logInfo('Error during service state cleanup: $e');
    }

    // Delete database files from the specific temp directory
    // Use the provided tempDirPath instead of calling getApplicationDocumentsDirectory
    final dbFolder = Directory(p.join(tempDirPath, 'documents'));
    logInfo('Attempting cleanup in: ${dbFolder.path}');

    if (await dbFolder.exists()) {
      final metadataDbFile = File(
        p.join(dbFolder.path, 'flipedit_projects_metadata.sqlite'),
      );
      if (await metadataDbFile.exists()) {
        try {
          await metadataDbFile.delete();
          logInfo('Deleted metadata DB: ${metadataDbFile.path}');
        } catch (e) {
          logInfo('Failed to delete metadata DB ${metadataDbFile.path}: $e');
        }
      } else {
        logInfo('Metadata DB not found for deletion: ${metadataDbFile.path}');
      }

      // Delete project-specific databases
      try {
        final entities = dbFolder.listSync();
        for (var entity in entities) {
          if (entity is File &&
              entity.path.contains('flipedit_project_') &&
              entity.path.endsWith('.sqlite')) {
            try {
              await entity.delete();
              logInfo('Deleted project DB: ${entity.path}');
            } catch (e) {
              logInfo('Failed to delete project DB ${entity.path}: $e');
            }
          }
        }
      } catch (e) {
        logInfo('Error listing or deleting project DBs in ${dbFolder.path}: $e');
      }
    } else {
      logInfo('Documents directory not found during cleanup: ${dbFolder.path}');
    }

    // Reset the DI container to ensure a clean slate for dependencies
    logInfo('Resetting DI container...');
    await di.reset(dispose: true);

    // Re-initialize essential services for the next test
    logInfo('Re-initializing dependencies...');
    await setupTestDependencyInjection();
    logInfo('--- Cleanup Complete ---');
  } catch (e) {
    logInfo('Error during cleanup: $e');
  }
}

// Common setup for all tests
Future<Directory> commonSetUpAll() async {
  logInfo('Running common setUpAll...');
  // 1. Create a temporary directory for this test run
  final testTempDir = await Directory.systemTemp.createTemp('flipedit_test_');
  logInfo('Using temporary directory for tests: ${testTempDir.path}');

  // 2. Set the mock PathProviderPlatform BEFORE anything else that might use paths
  PathProviderPlatform.instance = FakePathProviderPlatform(testTempDir.path);
  logInfo('Mock PathProviderPlatform set.');

  // Mock window_manager plugin to prevent MissingPluginException
  setupMockWindowManager();
  logInfo('Mock window_manager plugin set.');

  // 3. Clean up state thoroughly before any tests run (will now use the temp dir)
  // Pass the temp dir path to cleanup function
  await cleanupTestState(testTempDir.path);

  // 4. Setup DI (will also use the temp dir now) - cleanupTestState already calls this
  logInfo('Common setUpAll complete.');
  return testTempDir; // Return the directory path for teardown
}

// Common teardown for all tests
Future<void> commonTearDownAll(Directory testTempDir) async {
  logInfo('Running common tearDownAll...');
  try {
    // Attempt to reset DI one last time
    await di.reset(dispose: true);
    logInfo('Final DI reset complete.');

    // Delete the temporary directory
    if (await testTempDir.exists()) {
      logInfo('Deleting temporary directory: ${testTempDir.path}');
      await testTempDir.delete(recursive: true);
      logInfo('Temporary directory deleted.');
    } else {
      logInfo(
        'Temporary directory did not exist for deletion: ${testTempDir.path}',
      );
    }
  } catch (e) {
    logInfo(
      'Error during common tearDownAll (deleting temp dir ${testTempDir.path}): $e',
    );
  }
  // Reset the mock (optional, good practice)
  // PathProviderPlatform.instance = const PathProviderPlatform(); // Reset to default if needed
  logInfo('Common tearDownAll complete.');
}

// Common setup for each test
Future<void> commonSetUp(String tempDirPath) async {
  // Ensure PathProviderPlatform is still the fake one
  if (PathProviderPlatform.instance is! FakePathProviderPlatform) {
    logInfo('Re-setting FakePathProviderPlatform in commonSetUp');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDirPath);
  }
  // No DI reset here, cleanupState handles it before setupTestDependencyInjection
  // Just ensure DI is ready (it should be after cleanup/re-init)
  logInfo('Common setUp finished.');
}

// Common teardown for each test
Future<void> commonTearDown(String tempDirPath) async {
  logInfo('Running common tearDown...');
  // Clean up after each test to isolate them
  await cleanupTestState(tempDirPath);
  logInfo('Common tearDown complete.');
}
