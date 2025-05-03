import 'dart:io';

import 'package:flipedit/app.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watch_it/watch_it.dart';
import 'package:collection/collection.dart';

// Import the common setup file
import 'common_test_setup.dart';

void main() {
  // Ensure binding is initialized
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Temporary directory for this test run - now managed by common setup
  late Directory testTempDir;
  // Use late initialization for the path string
  late String testTempDirPath;

  // Use common setUpAll
  setUpAll(() async {
    testTempDir = await commonSetUpAll();
    testTempDirPath = testTempDir.path; // Store the path string
  });

  // Use common tearDown
  tearDown(() async {
    // Pass the temp directory path string to common tearDown
    await commonTearDown(testTempDirPath);
  });

  // Use common tearDownAll
  tearDownAll(() async {
    // Pass the temp Directory object to common tearDownAll
    await commonTearDownAll(testTempDir);
  });

  // --- Test Cases Start Here ---

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
    late ProjectMetadataDao
    metadataDao; // Use late to handle potential init errors
    late ProjectViewModel projectVm;
    try {
      // It's crucial that setupDependencyInjection has completed successfully before this point.
      metadataDao = di<ProjectMetadataDao>();
      projectVm = di<ProjectViewModel>();
      print('DI components retrieved successfully.');
    } catch (e) {
      print('Fatal Error: Failed to retrieve dependencies via DI: $e');
      print(
        'Check that setupServiceLocator() completes correctly before FlipEditApp builds.',
      );
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

    // Act: Use the ProjectViewModel to create a project
    print('Attempting to create project...');
    // Rename createNewProjectCommand to createNewProject and use positional argument
    final projectId = await projectVm.createNewProject('Test Project 1');
    print('Create project call returned ID: $projectId');

    // Expect a non-null project ID
    expect(projectId, isNotNull);
    expect(projectId, greaterThan(0));

    // Pump and settle to allow any UI updates or async operations
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Optional: Load the project to verify further (replace loadProjectCommand with loadProject)
    print('Attempting to load created project...');
    // Use await with loadProject
    await projectVm.loadProject(projectId);
    print('Load project call completed.');

    // Pump and settle again
    await tester.pumpAndSettle(const Duration(seconds: 1));

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
    expect(
      finalProjects.length,
      initialProjectCount + 1,
      reason:
          "Metadata count should increase by 1. Initial: $initialProjectCount, Final: ${finalProjects.length}",
    );

    ProjectMetadata? createdProjectMetadata;
    try {
      // Use firstWhereOrNull for safer lookup (needs collection package import)
      createdProjectMetadata = finalProjects.firstWhereOrNull(
        (p) => p.id == projectId,
      );
    } catch (e) {
      print("Error finding project in final list: $e");
      // Don't assign null here, let the expect handle it.
    }

    expect(
      createdProjectMetadata,
      isNotNull,
      reason:
          'Project metadata with ID $projectId should exist in the final list.',
    );
    // Only access fields if not null
    if (createdProjectMetadata != null) {
      expect(
        createdProjectMetadata.name,
        'Test Project 1',
        reason: 'Project metadata name should match.',
      );
      print(
        'Verified project in metadata: ${createdProjectMetadata.name} (ID: ${createdProjectMetadata.id}) Path: ${createdProjectMetadata.databasePath}',
      );
    }

    // 2. Check project database file existence on the filesystem
    if (createdProjectMetadata != null) {
      final expectedDbPath = createdProjectMetadata.databasePath;
      final projectDbFile = File(expectedDbPath);

      print('Checking for project DB file at: ${projectDbFile.path}');
      // Use expectLater for async matchers like exists
      await expectLater(
        projectDbFile.exists(),
        completion(isTrue),
        reason:
            "Project-specific database file should exist at path: ${projectDbFile.path}",
      );

      // 3. Optional: Verify the integrity of the created project database only if file exists
      // Check existence again before trying to open, as expectLater might have delay
      if (await projectDbFile.exists()) {
        print('Verifying project database integrity...');
        // Get the service that holds the current project DB instance
        ProjectDatabaseService? dbService;
        try {
          dbService = di<ProjectDatabaseService>();
          final trackDao = dbService.trackDao;

          if (trackDao == null) {
            fail(
              'ProjectDatabaseService did not have an active trackDao after loading.',
            );
          }

          // Verify the tracks table is empty using the DAO's watch method
          final initialTracks = await trackDao.watchAllTracks().first;
          expect(
            initialTracks,
            isEmpty,
            reason: 'Tracks table should be empty initially.',
          );
          print(
            'Successfully verified project DB schema via service.trackDao (checked tracks table is empty).',
          );
        } catch (e, stackTrace) {
          print('Stack trace for DB verification error: $stackTrace');
          fail(
            'Failed to get DB service/DAO or query the created project database (${projectDbFile.path}) via DAO: $e',
          );
        } finally {
          // DO NOT close the connection here - it's managed by the service/DI
          print('Verification finished (connection managed by service).');
        }
      } else {
        fail(
          'Database file check failed just before opening (after expectLater): ${projectDbFile.path}',
        );
      }
    } else {
      fail(
        'Cannot verify database file existence because createdProjectMetadata was null.',
      );
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
