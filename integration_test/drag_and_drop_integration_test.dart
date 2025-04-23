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
import 'package:watch_it/watch_it.dart'; // Import watch_it

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

  testWidgets('Drag and drop media from panel to timeline creates a new track',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(FlipEditApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final projectVm = di<ProjectViewModel>();
    final projectId = await projectVm.createNewProject('Test Project Drag Drop');
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
    // No need to reload project here, ProjectDatabaseService now updates notifier
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Use the fake file name for finding the draggable
    const importedFileName = fakeFileName;

    // Find the Text widget with the filename
    final textFinder = find.text(importedFileName);
    expect(
      textFinder,
      findsOneWidget,
      reason: 'Expected to find Text widget for "$importedFileName" in MediasListPanel.',
    );

    // Find the ListTile ancestor of the Text widget
    final tileFinder = find.ancestor(
      of: textFinder,
      matching: find.byType(ListTile),
    );
    expect(
      tileFinder,
      findsOneWidget,
      reason: 'Expected to find ListTile ancestor for "$importedFileName" text.',
    );

    // Find the Draggable<ClipModel> ancestor of the ListTile
    final draggableFinder = find.ancestor(
      of: tileFinder, // Use the found ListTile finder
      matching: find.byType(Draggable<ClipModel>),
    );
    expect(
      draggableFinder,
      findsOneWidget,
      reason: 'Expected to find Draggable<ClipModel> ancestor for "$importedFileName" tile.',
    );

    // Find the Timeline widget
    final timelineFinder = find.byType(Timeline);
    expect(timelineFinder, findsOneWidget, reason: 'Expected to find Timeline widget.');

    // Perform the drag and drop
    final draggable = tester.widget<Draggable<ClipModel>>(draggableFinder);
    final timeline = tester.widget<Timeline>(timelineFinder);

    // Get the center of the draggable and timeline
    final draggableCenter = tester.getCenter(draggableFinder);
    final timelineCenter = tester.getCenter(timelineFinder);

    // Drag from the draggable to the timeline
    await tester.dragFrom(draggableCenter, timelineCenter);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify that a new track is created
    final tracks = dbService.tracksNotifier.value;
    expect(tracks.length, 1, reason: 'Expected one track to be created.');

    // Verify that a new clip is created on the timeline
    final clipDao = dbService.clipDao!;
    final allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 1, reason: 'Expected one clip to be created.');
  });
}