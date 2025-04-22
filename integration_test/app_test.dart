import 'dart:io';

import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:collection/collection.dart';


// Helper function to ensure SharedPreferences work in tests
void setupTestSharedPreferences() {
  // Set mock initial values for SharedPreferences testing
  SharedPreferences.setMockInitialValues({});
}

// --- Mock PathProviderPlatform START ---
// Use a fake platform implementation to redirect storage paths during tests
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
    // Point support path to a subdirectory within the temp path
    final supportPath = p.join(temporaryPath, 'support');
    await Directory(supportPath).create(recursive: true);
    return supportPath;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async {
    // Point documents path (where databases are stored) to a subdirectory
    final docsPath = p.join(temporaryPath, 'documents');
    await Directory(docsPath).create(recursive: true);
    return docsPath;
  }

  // Implement other paths as needed, pointing them to the temp directory
  @override
  Future<String?> getLibraryPath() async {
    final libPath = p.join(temporaryPath, 'library');
    await Directory(libPath).create(recursive: true);
    return libPath;
  }

  @override
  Future<String?> getExternalStoragePath() async {
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
     final storagePath = p.join(temporaryPath, 'storage', type?.toString() ?? 'default');
     await Directory(storagePath).create(recursive: true);
     return [storagePath];
   }

  @override
  Future<String?> getDownloadsPath() async {
    final downloadsPath = p.join(temporaryPath, 'downloads');
    await Directory(downloadsPath).create(recursive: true);
    return downloadsPath;
  }
}
// --- Mock PathProviderPlatform END ---


// Helper function for DI setup - now uses the correct function
Future<void> setupDependencyInjection() async {
  // Ensure SharedPreferences are mocked before DI setup uses them
  setupTestSharedPreferences();
  // Call the correct DI setup function from its file
  await setupServiceLocator();
}

// Function to clean up databases and DI before/after tests
Future<void> cleanupState() async {
  print('--- Starting Cleanup ---');
  try {
    // Close any active project in services that hold state
     try {
       // Check registration before accessing to avoid errors if DI was reset improperly
       if (di.isRegistered<ProjectViewModel>()) {
         // final projectVm = di<ProjectViewModel>();
         // projectVm.resetState(); // Add a reset method if possible
         print('Checked ProjectViewModel registration.');
       }
        if (di.isRegistered<ProjectMetadataService>()) {
          final metaService = di<ProjectMetadataService>();
          await metaService.closeCurrentDatabase(); // Close any open project DB connection
           print('Closed current project database in ProjectMetadataService.');
        } else {
           print('ProjectMetadataService not registered during cleanup.');
        }
        if (di.isRegistered<ProjectDatabaseService>()) {
           final dbService = di<ProjectDatabaseService>();
           await dbService.closeCurrentProject(); // Ensure this service is also reset
           print('Closed current project in ProjectDatabaseService.');
         } else {
           print('ProjectDatabaseService not registered during cleanup.');
         }
     } catch (e) {
       print('Error during service state cleanup: $e');
     }


    // Delete database files
    final dbFolder = await getApplicationDocumentsDirectory();
    final metadataDbFile = File(p.join(dbFolder.path, 'flipedit_projects_metadata.sqlite'));
    if (await metadataDbFile.exists()) {
       try {
        await metadataDbFile.delete();
        print('Deleted metadata DB: ${metadataDbFile.path}');
       } catch (e) {
          print('Failed to delete metadata DB ${metadataDbFile.path}: $e');
       }
    }
    // Delete project-specific databases
    final dir = Directory(dbFolder.path);
    if (await dir.exists()) {
        final entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.contains('flipedit_project_') && entity.path.endsWith('.sqlite')) {
             try {
               await entity.delete();
               print('Deleted project DB: ${entity.path}');
             } catch(e) {
               print('Failed to delete project DB ${entity.path}: $e');
             }
          }
        }
    }


     // Reset the DI container to ensure a clean slate for dependencies
     print('Resetting DI container...');
      // Check if reset is available and use it, otherwise re-setup might be the only way
     await di.reset(dispose: true); // Assuming WatchIt supports this


     // Re-initialize essential services for the next test
     print('Re-initializing dependencies...');
     await setupDependencyInjection(); // This now calls setupServiceLocator
     print('--- Cleanup Complete ---');

  } catch (e) {
    print('Error during cleanup: $e');
     // It might be better to not rethrow here, to allow other tests to run
     // rethrow;
  }
}

void main() {
  // Ensure binding is initialized
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Temporary directory for this test run
  late Directory testTempDir;

  setUpAll(() async {
    print('Running setUpAll...');
    // 1. Create a temporary directory for this test run
    testTempDir = await Directory.systemTemp.createTemp('flipedit_test_');
    print('Using temporary directory for tests: ${testTempDir.path}');

    // 2. Set the mock PathProviderPlatform BEFORE anything else that might use paths
    PathProviderPlatform.instance = FakePathProviderPlatform(testTempDir.path);
    print('Mock PathProviderPlatform set.');

    // 3. Clean up state thoroughly before any tests run (will now use the temp dir)
    await cleanupState(); // Should run after mock is set
    // 4. Setup DI (will also use the temp dir now)
    // await setupDependencyInjection(); // cleanupState already calls this
    print('setUpAll complete.');
  });

   tearDown(() async {
     print('Running tearDown...');
     // Clean up after each test to isolate them
     await cleanupState();
     print('tearDown complete.');
   });

  // Add tearDownAll to clean up the temporary directory
  tearDownAll(() async {
    print('Running tearDownAll...');
    try {
      if (await testTempDir.exists()) {
        print('Deleting temporary directory: ${testTempDir.path}');
        await testTempDir.delete(recursive: true);
        print('Temporary directory deleted.');
      }
    } catch (e) {
      print('Error deleting temporary directory ${testTempDir.path}: $e');
    }
    // Reset the mock (optional, but good practice)
    // PathProviderPlatform.instance = null; // Removed due to linter error
    print('tearDownAll complete.');
  });


  testWidgets('Create new project test', (WidgetTester tester) async {
    print('--- Starting Test: Create new project test ---');
    // Arrange: Pump the root widget of your app.
    print('Setting up main app widget...');
    // Use the correct app widget name
    await tester.pumpWidget(FlipEditApp()); // Use const if constructor is const
    print('Waiting for app to settle after initial pump...');
    // Increased settle time can help with complex startups
    await tester.pumpAndSettle(const Duration(seconds: 5));
    print('App settled.');


    // Get necessary services/DAOs via DI *after* pumpWidget ensures DI is ready
    late ProjectMetadataDao metadataDao; // Use late to handle potential init errors
    late ProjectViewModel projectVm;
    try {
       // It's crucial that setupDependencyInjection has completed successfully before this point.
       metadataDao = di<ProjectMetadataDao>();
       projectVm = di<ProjectViewModel>();
       print('DI components retrieved successfully.');
    } catch (e) {
       print('Fatal Error: Failed to retrieve dependencies via DI: $e');
       print('Check that setupServiceLocator() completes correctly before FlipEditApp builds.');
       print('Also ensure cleanupState re-initializes DI properly.');
       fail('Failed to get dependencies from DI container.');
    }


    // Get initial project count from the metadata database
    List<ProjectMetadata> initialProjects = [];
     try {
       initialProjects = await metadataDao.watchAllProjects().first;
     } catch (e) {
       print('Error getting initial projects: $e');
       fail('Failed to query initial projects from metadataDao.');
     }
    final initialProjectCount = initialProjects.length;
    print('Initial project count: $initialProjectCount');


    // Act: Simulate creating a new project by directly calling the ViewModel command
    const newProjectName = 'My Test Project';
    print('Calling createNewProjectCommand with name: "$newProjectName"'); // Fixed unterminated string

    int? newProjectId;
    try {
      // Ensure projectVm is initialized before calling methods on it
      newProjectId = await projectVm.createNewProjectCommand(newProjectName);
      print('createNewProjectCommand completed, got ID: $newProjectId');
      if (newProjectId == null) {
         fail('createNewProjectCommand returned null ID');
      }

      print('Loading the newly created project (ID: $newProjectId)...');
      await projectVm.loadProjectCommand(newProjectId);
      print('loadProjectCommand completed.');

      // Wait for UI updates and any async operations triggered by loading
      print('Waiting for app to settle after project load...');
      await tester.pumpAndSettle(const Duration(seconds: 3)); // Allow time for loading state changes
       print('App settled after load.');

    } catch (e, stackTrace) {
       print('Error during project creation/loading: $e\n$stackTrace');
       fail('Failed during project creation or loading step: $e');
    }


    // Assert: Verify project creation
    print('Starting assertions...');
    // 1. Check metadata database for the new entry
    List<ProjectMetadata> finalProjects = [];
    try {
       finalProjects = await metadataDao.watchAllProjects().first;
    } catch (e) {
       print('Error getting final projects: $e');
       fail('Failed to query final projects from metadataDao.');
    }
    expect(finalProjects.length, initialProjectCount + 1, reason: "Metadata count should increase by 1. Initial: $initialProjectCount, Final: ${finalProjects.length}");

    ProjectMetadata? createdProjectMetadata;
    try {
       // Use firstWhereOrNull for safer lookup (needs collection package import)
       createdProjectMetadata = finalProjects.firstWhereOrNull((p) => p.id == newProjectId);
    } catch (e) {
      print("Error finding project in final list: $e");
      // Don't assign null here, let the expect handle it.
    }

     expect(createdProjectMetadata, isNotNull, reason: 'Project metadata with ID $newProjectId should exist in the final list.');
     // Only access fields if not null
     if (createdProjectMetadata != null) {
        expect(createdProjectMetadata.name, newProjectName, reason: 'Project metadata name should match.');
        print('Verified project in metadata: ${createdProjectMetadata.name} (ID: ${createdProjectMetadata.id}) Path: ${createdProjectMetadata.databasePath}');
     }


    // 2. Check project database file existence on the filesystem
    if (createdProjectMetadata != null) {
        final expectedDbPath = createdProjectMetadata.databasePath;
        final projectDbFile = File(expectedDbPath);

        print('Checking for project DB file at: ${projectDbFile.path}');
        // Use expectLater for async matchers like exists
        await expectLater(projectDbFile.exists(), completion(isTrue), reason: "Project-specific database file should exist at path: ${projectDbFile.path}");

        // 3. Optional: Verify the integrity of the created project database only if file exists
        // Check existence again before trying to open, as expectLater might have delay
        if (await projectDbFile.exists()){
            print('Verifying project database integrity...');
            // Get the service that holds the current project DB instance
            ProjectDatabaseService? dbService;
            try {
              dbService = di<ProjectDatabaseService>();
              final trackDao = dbService.trackDao;

              if (trackDao == null) {
                fail('ProjectDatabaseService did not have an active trackDao after loading.');
              }

              // Verify the tracks table is empty using the DAO's watch method
              final initialTracks = await trackDao!.watchAllTracks().first;
              expect(initialTracks, isEmpty, reason: 'Tracks table should be empty initially.');
              print('Successfully verified project DB schema via service.trackDao (checked tracks table is empty).');
            } catch (e, stackTrace) {
              print('Stack trace for DB verification error: $stackTrace');
              fail('Failed to get DB service/DAO or query the created project database (${projectDbFile.path}) via DAO: $e');
            } finally {
              // DO NOT close the connection here - it's managed by the service/DI
               print('Verification finished (connection managed by service).');
            }
        } else {
           fail('Database file check failed just before opening (after expectLater): ${projectDbFile.path}');
        }

    } else {
       fail('Cannot verify database file existence because createdProjectMetadata was null.');
    }


    print('--- Test Passed: Create new project test ---');
  });

   // Add more tests here...
   testWidgets('Placeholder test 2', (WidgetTester tester) async {
     print('--- Starting Test: Placeholder test 2 ---');
     expect(1 + 1, 2);
     print('--- Test Passed: Placeholder test 2 ---');
   });
} 