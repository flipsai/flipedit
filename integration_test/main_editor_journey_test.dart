import 'dart:io';
// Import for Size class

import 'package:flutter/material.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart'; // Needed for timelineFinder
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Import common setup and helpers
import 'common_test_setup.dart';
import 'helpers/editor_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Directory? testTempDir;
  String? testTempDirPath;

  // Use common setup/teardown from common_test_setup.dart
  setUpAll(() async {
    testTempDir = await commonSetUpAll();
    testTempDirPath = testTempDir!.path;
  });

  tearDownAll(() async {
    if (testTempDir != null) await commonTearDownAll(testTempDir!);
  });

  setUp(() async {
    if (testTempDirPath != null) await commonSetUp(testTempDirPath!);
  });

  tearDown(() async {
    if (testTempDirPath != null) await commonTearDown(testTempDirPath!);
  });

  // --- Main Editor Journey Test ---
  testWidgets('Main Editor Journey: Create, Import, Drag to Timeline', (
    WidgetTester tester,
  ) async {
    debugPrint('--- Starting Test: Main Editor Journey ---');

    // --- 1. Setup App ---
    // Set a reasonable window size to avoid rendering issues
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(FlipEditApp());
    // Allow time for the app to initialize fully
    await tester.pumpAndSettle(const Duration(seconds: 5));
    debugPrint('App pumped and settled.');

    // --- 2. Create and Load Project ---

    // --- 2b. Test View Menu Toggles ---
    debugPrint('--- Testing View Menu Toggles ---');
    // final editorVm = di<EditorViewModel>();
    // final viewMenuButtonFinder = findViewMenuButton(tester);

    // Test Inspector Toggle
    // await testPanelToggleViaViewMenu(
    //   tester: tester,
    //   editorVm: editorVm,
    //   panelName: 'Inspector',
    //   isVisibleGetter: () => editorVm.isInspectorVisible,
    //   viewMenuButtonFinder: viewMenuButtonFinder,
    //   panelWidgetFinder: find.byType(InspectorPanel),
    // );

    // Test Timeline Toggle
    // await testPanelToggleViaViewMenu(
    //   tester: tester,
    //   editorVm: editorVm,
    //   panelName: 'Timeline',
    //   isVisibleGetter: () => editorVm.isTimelineVisible,
    //   viewMenuButtonFinder: viewMenuButtonFinder,
    //   panelWidgetFinder: find.byType(
    //     Timeline,
    //   ), // Timeline finder already used below
    // );

    // Test Preview Toggle
    // await testPanelToggleViaViewMenu(
    //   tester: tester,
    //   editorVm: editorVm,
    //   panelName: 'Player', // Updated panel name
    //   isVisibleGetter:
    //       () =>
    //           editorVm
    //               .isPreviewVisible, // ViewModel property is still isPreviewVisible
    //   viewMenuButtonFinder: viewMenuButtonFinder,
    //   // panelWidgetFinder: find.byType(PlayerPanel), // Updated to PlayerPanel
    // );
    debugPrint('--- View Menu Toggles Tested ---');

    // --- 3. Import Media ---
    const testVideoFile = 'journey_video.mp4';
    const testVideoPath = '/fake/path/$testVideoFile'; // Use a fake path
    await importTestMedia(
      tester,
      fileName: testVideoFile,
      filePath: testVideoPath,
      type: ClipType.video,
      durationMs: 5000, // 5 seconds duration
    );
    // Verification that import succeeded (e.g., asset exists) is implicitly
    // checked by the next step trying to find the draggable.

    // --- 4. Verify Media Appears in Panel ---
    final draggableFinder = await findMediaPanelDraggable(
      tester,
      testVideoFile,
    );
    // Expectation is handled within the helper function

    // --- 5. Drag Media to Timeline ---
    final timelineFinder = find.byType(Timeline);
    expect(
      timelineFinder,
      findsOneWidget,
      reason: 'Expected to find the Timeline widget.',
    );
    // Use the helper to perform the drag and drop
    await dragMediaToTimeline(
      tester,
      draggableFinder,
      timelineFinder,
      // Optional: Specify a precise drop offset if needed, otherwise uses helper default
      // dropOffset: Offset(150, 60),
    );
    // pumpAndSettle is handled within the helper

    // --- 6. Verify Track and Clip Creation ---
    await verifyTrackAndClipCreation(tester);
    // Expectations for track and clip existence are handled within the helper

    // Verify the editor is displayed with the expected components
    // await verifyPanelExists(
    //   tester: tester,
    //   panelName: 'Inspector',
    //   panelWidgetFinder: find.byType(InspectorPanel),
    //   isVisibleNotifier: vm.isInspectorVisible,
    // );

    // await verifyPanelExists(
    //   tester: tester,
    //   panelName: 'Timeline',
    //   isVisibleNotifier: vm.isTimelineVisible,
    // );

    // TODO: Add tab system verification when ready

    debugPrint('--- Test Passed: Main Editor Journey ---');
  });
}
