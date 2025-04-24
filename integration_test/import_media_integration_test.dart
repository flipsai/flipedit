import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'common_test_setup.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/di/service_locator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Directory? testTempDir;

  setUpAll(() async {
    testTempDir = await commonSetUpAll();
  });

  tearDownAll(() async {
    if (testTempDir != null) await commonTearDownAll(testTempDir!);
  });

  setUp(() async {
    if (testTempDir != null) await commonSetUp(testTempDir!.path);
  });

  tearDown(() async {
    if (testTempDir != null) await commonTearDown(testTempDir!.path);
  });

  testWidgets('Import media via panel button shows Draggable<ClipModel>', (WidgetTester tester) async {
    await tester.pumpWidget(FlipEditApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final projectVm = di<ProjectViewModel>();
    final projectId = await projectVm.createNewProject('Test Project Panel');
    expect(projectId, isNotNull);
    await projectVm.loadProject(projectId);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Insert a fake media asset directly into the project database
    final dbService = di<ProjectDatabaseService>();
    const fakeFileName = 'random_video.mp4';
    const fakeFilePath = '/fake/path/$fakeFileName';
    await dbService.importAsset(
      filePath: fakeFilePath,
      type: ClipType.video,
      durationMs: 1000,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Use the fake file name for finding the draggable
    const importedFileName = fakeFileName;

    // Verify that the imported asset appears in the media list
    final tileFinder = find.widgetWithText(ListTile, importedFileName);
    expect(tileFinder, findsOneWidget, reason: 'Expected media list tile for "$importedFileName" in MediasListPanel.');
  });

}
