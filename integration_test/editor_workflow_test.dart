import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:watch_it/watch_it.dart';

import 'common_test_setup.dart';

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

  testWidgets('Import media, verify panel, and drag to timeline',
      (WidgetTester tester) async {
    // --- Setup ---
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(FlipEditApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final projectVm = di<ProjectViewModel>();
    final projectId = await projectVm.createNewProject('Test Project Combined');
    expect(projectId, isNotNull);
    await projectVm.loadProject(projectId);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Import Media ---
    final dbService = di<ProjectDatabaseService>();
    const fakeFileName = 'random_video.mp4';
    const fakeFilePath = '/fake/path/$fakeFileName';
    await dbService.importAsset(
      filePath: fakeFilePath,
      type: ClipType.video,
      durationMs: 1000,
    );
    // Service now updates notifier, pump to reflect
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Verify Media in Panel and Find Draggable ---
    const importedFileName = fakeFileName;

    // Find the Draggable<ClipModel> that contains the Text widget with the filename
    final draggableFinder = find.widgetWithText(Draggable<ClipModel>, importedFileName);

    expect(
      draggableFinder,
      findsOneWidget,
      reason: 'Expected to find Draggable<ClipModel> containing text "$importedFileName" in MediasListPanel.',
    );

    // --- Drag and Drop ---
    // Find the Timeline widget
    final timelineFinder = find.byType(Timeline);
    expect(timelineFinder, findsOneWidget, reason: 'Expected to find Timeline widget.');

    // Get the center of the draggable and timeline
    final draggableCenter = tester.getCenter(draggableFinder);
    final timelineCenter = tester.getCenter(timelineFinder);

    // Drag from the draggable to the timeline
    await tester.dragFrom(draggableCenter, timelineCenter);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Verify Track and Clip Creation ---
    // Verify that a new track is created
    final tracks = dbService.tracksNotifier.value;
    expect(tracks.length, 1, reason: 'Expected one track to be created after drag-and-drop.');

    // Verify that a new clip is created on the timeline
    final clipDao = dbService.clipDao!;
    final allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 1, reason: 'Expected one clip to be created after drag-and-drop.');
  });
}