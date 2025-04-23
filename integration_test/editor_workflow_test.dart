import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/commands/remove_clip_command.dart';
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

    // --- Calculate Drop Position (e.g., Frame 0 + offset) ---
    // Use calculation similar to Test 2, but target frame 0 for simplicity
    final timelineVm = di<TimelineViewModel>();
    final zoom = timelineVm.zoomNotifier.value;
    final trackLabelWidth = timelineVm.trackLabelWidthNotifier.value;
    const double framePixelWidth = 5.0;
    const double timeRulerHeight = 25.0;
    const targetFrame = 0; // Target the beginning

    final effectiveFrameWidth = framePixelWidth * zoom;
    final targetX = (targetFrame * effectiveFrameWidth) + trackLabelWidth;
    final targetY = timeRulerHeight + 50.0; // Drop 50px below the ruler

    final timelineTopLeft = tester.getTopLeft(timelineFinder);
    final dropOffset = timelineTopLeft + Offset(targetX, targetY);

    // --- Drag and Drop ---
    final draggableCenter = tester.getCenter(draggableFinder);
    await tester.dragFrom(draggableCenter, dropOffset); // Drop at calculated position
    // Use 4s delay like in Test 2 for consistency with this method
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // --- Verify Track and Clip Creation ---
    // Verify that a new track is created
    final tracks = dbService.tracksNotifier.value;
    expect(tracks.length, 1, reason: 'Expected one track to be created after drag-and-drop.');

    // Verify that a new clip is created on the timeline
    final clipDao = dbService.clipDao!;
    final allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 1, reason: 'Expected one clip to be created after drag-and-drop.');
  });


  // Test: Drag and drop media to specific timeline position
  testWidgets('Drag and drop media to specific timeline position', (WidgetTester tester) async {
    // --- Setup (similar to previous test) ---
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(FlipEditApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final projectVm = di<ProjectViewModel>();
    final projectId = await projectVm.createNewProject('Test Project Drag Position');
    expect(projectId, isNotNull);
    await projectVm.loadProject(projectId);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final dbService = di<ProjectDatabaseService>();
    const fakeFileName = 'video_for_position.mp4';
    const fakeFilePath = '/fake/path/$fakeFileName';
    const clipDurationMs = 5000; // 5 seconds
    await dbService.importAsset(
      filePath: fakeFilePath,
      type: ClipType.video,
      durationMs: clipDurationMs,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Find Draggable and Timeline ---
    final draggableFinder = find.widgetWithText(Draggable<ClipModel>, fakeFileName);
    expect(draggableFinder, findsOneWidget);
    final timelineFinder = find.byType(Timeline);
    expect(timelineFinder, findsOneWidget);

    // --- Calculate Drop Position for Frame 30 ---
    final timelineVm = di<TimelineViewModel>();
    final zoom = timelineVm.zoomNotifier.value;
    final trackLabelWidth = timelineVm.trackLabelWidthNotifier.value;
    const double framePixelWidth = 5.0;
    const double timeRulerHeight = 25.0;
    const targetFrame = 30;

    final effectiveFrameWidth = framePixelWidth * zoom;
    final targetX = (targetFrame * effectiveFrameWidth) + trackLabelWidth;
    final targetY = timeRulerHeight + 50.0; // Drop 50px below the ruler

    final timelineTopLeft = tester.getTopLeft(timelineFinder);
    final dropOffset = timelineTopLeft + Offset(targetX, targetY);

    // --- Drag and Drop ---
    // --- DEBUG PRINT --- 
    print('--- Drag Debug Info ---');
    print('Zoom: $zoom');
    print('Track Label Width: $trackLabelWidth');
    print('Timeline Top Left: $timelineTopLeft');
    print('Target X: $targetX');
    print('Target Y: $targetY');
    print('Calculated Drop Offset: $dropOffset');
    print('Draggable Center: ${tester.getCenter(draggableFinder)}');
    print('-----------------------');

    final draggableCenter = tester.getCenter(draggableFinder);
    await tester.dragFrom(draggableCenter, dropOffset); // Drop at calculated position for frame 30
    // Use increased settle time as it might still be needed
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // --- Verify Clip Position ---
    final tracks = dbService.tracksNotifier.value;
    expect(tracks.length, 1, reason: 'Expected one track.');
    final allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 1, reason: 'Expected one clip.');

    final addedClip = allClips.first;
    expect(addedClip.trackId, tracks.first.id, reason: 'Clip should be on the created track.');
    // Verify start time is positive (precise check needs timeline scale)
    expect(addedClip.startTimeOnTrackMs, greaterThan(0), reason: 'Clip start time should be positive.'); // Corrected field name
    print('Clip added at startTimeOnTrackMs: ${addedClip.startTimeOnTrackMs}'); // Corrected field name
  });

  // Test: Add and remove clip from timeline
  testWidgets('Add and remove clip from timeline', (WidgetTester tester) async {
    // --- Setup (Add a clip first) ---
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(FlipEditApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final projectVm = di<ProjectViewModel>();
    final projectId = await projectVm.createNewProject('Test Project Remove Clip');
    expect(projectId, isNotNull);
    await projectVm.loadProject(projectId);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final dbService = di<ProjectDatabaseService>();
    const fakeFileName = 'video_to_remove.mp4';
    const fakeFilePath = '/fake/path/$fakeFileName';
    await dbService.importAsset(
      filePath: fakeFilePath,
      type: ClipType.video,
      durationMs: 2000,
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Drag to timeline
    final draggableFinder = find.widgetWithText(Draggable<ClipModel>, fakeFileName);
    expect(draggableFinder, findsOneWidget);
    final timelineFinder = find.byType(Timeline);
    expect(timelineFinder, findsOneWidget);

    // --- Calculate Drop Position (e.g., Frame 0 + offset) ---
    final timelineVm = di<TimelineViewModel>();
    final zoom = timelineVm.zoomNotifier.value;
    final trackLabelWidth = timelineVm.trackLabelWidthNotifier.value;
    const double framePixelWidth = 5.0;
    const double timeRulerHeight = 25.0;
    const targetFrame = 0; // Target the beginning

    final effectiveFrameWidth = framePixelWidth * zoom;
    final targetX = (targetFrame * effectiveFrameWidth) + trackLabelWidth;
    final targetY = timeRulerHeight + 50.0; // Drop 50px below the ruler

    final timelineTopLeft = tester.getTopLeft(timelineFinder);
    final dropOffset = timelineTopLeft + Offset(targetX, targetY);

    // --- Drag and Drop ---
    final draggableCenter = tester.getCenter(draggableFinder);
    await tester.dragFrom(draggableCenter, dropOffset); // Drop at calculated position
    // Use 4s delay like in Test 2 for consistency with this method
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Verify clip added
    var allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 1, reason: 'Expected one clip initially.');
    final clipToRemove = allClips.first;

    // --- Find and Remove Clip ---
    final timelineClipFinder = find.byType(TimelineClip);
    expect(timelineClipFinder, findsOneWidget, reason: 'Expected to find the TimelineClip widget.');

    // Simulate selecting the clip
    await tester.tap(timelineClipFinder);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Simulate removal via Command
    final timelineVmForRemove = di<TimelineViewModel>(); // Renamed variable
    final removeCommand = RemoveClipCommand(vm: timelineVmForRemove, clipId: clipToRemove.id);
    await removeCommand.execute();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // --- Verify Removal ---
    // Check UI
    expect(timelineClipFinder, findsNothing, reason: 'TimelineClip widget should be removed from UI.');

    // Check Database
    allClips = await dbService.currentDatabase!.select(dbService.currentDatabase!.clips).get();
    expect(allClips.length, 0, reason: 'Expected zero clips in database after removal.');
  });
}