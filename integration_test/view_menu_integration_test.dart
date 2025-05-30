import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/inspector/inspector_panel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watch_it/watch_it.dart';

// Import the common setup file
import 'common_test_setup.dart';

// --- Parameterized Test Helper ---
// This function encapsulates the logic for testing a single panel toggle.
Future<void> _testPanelToggle({
  required WidgetTester tester,
  required EditorViewModel editorVm,
  required String panelName,
  required ValueGetter<bool>
  isVisibleGetter, // Function to get current visibility state from ViewModel
  required Finder viewMenuButtonFinder,
  required Finder panelWidgetFinder, // Renamed from panelTabFinder
}) async {
  // --- Scoped Helper Functions (Specific to this test helper) ---
  // Helper to get the finder for the LAST Text widget matching the text
  Finder findLastTextWidget(String text) {
    final finder = find.text(text);
    expect(
      finder,
      findsWidgets,
      reason:
          'Scoped [$panelName]: Should find at least one Text widget "$text"',
    );
    return finder.last;
  }

  // Helper to check if a MenuFlyoutItem (associated with the last itemText found) has the checkmark icon
  bool hasCheckmarkScoped(String itemText) {
    final lastTextFinder = findLastTextWidget(itemText);
    final itemFinder = find.ancestor(
      of: lastTextFinder,
      matching: find.byType(FlyoutListTile),
    );
    expect(
      itemFinder,
      findsOneWidget,
      reason:
          'Scoped [$panelName]: Should find the FlyoutListTile ancestor for the last "$itemText"',
    );
    final checkmarkFinder = find.descendant(
      of: itemFinder,
      matching: find.byIcon(FluentIcons.check_mark),
      matchRoot: true,
    );
    return tester.any(checkmarkFinder);
  }

  // Helper to tap a MenuFlyoutItem by tapping the LAST Text descendant found.
  Future<void> tapFlyoutItemByTextScoped(String text) async {
    final lastTextFinder = findLastTextWidget(text);
    await tester.tap(lastTextFinder);
    await tester.pumpAndSettle();
  }
  // --- End Scoped Helper Functions ---

  debugPrint('--- Testing $panelName toggle ---');
  bool initialVisible = isVisibleGetter();
  debugPrint('Initial $panelName Visible: $initialVisible');

  // Initial UI Check:
  expect(
    panelWidgetFinder,
    initialVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Initial Panel Widget visibility should match state ($initialVisible)',
  );

  // --- First Toggle --- (e.g., Visible -> Hidden or Hidden -> Visible)
  debugPrint('Toggling $panelName via menu...');
  await tester.tap(viewMenuButtonFinder); // Open menu
  await tester.pumpAndSettle();

  // Check initial checkmark in menu
  expect(
    hasCheckmarkScoped(panelName),
    initialVisible,
    reason:
        '[$panelName] Menu checkmark should match initial state ($initialVisible)',
  );

  // Tap menu item to toggle
  await tapFlyoutItemByTextScoped(panelName);

  // Check ViewModel state toggled
  bool toggledVisible = !initialVisible;
  expect(
    isVisibleGetter(),
    toggledVisible,
    reason:
        '[$panelName] ViewModel state should have toggled to $toggledVisible',
  );
  debugPrint('$panelName ViewModel Visible after toggle: ${isVisibleGetter()}');

  // Check UI Panel Widget visibility AFTER toggle
  expect(
    panelWidgetFinder,
    toggledVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Panel Widget visibility should be updated after toggle ($toggledVisible)',
  );
  debugPrint(
    '$panelName Panel Widget found after toggle: ${tester.any(panelWidgetFinder)}',
  );

  // Check Menu checkmark visibility AFTER toggle
  await tester.tap(viewMenuButtonFinder); // Re-open menu
  await tester.pumpAndSettle();
  expect(
    hasCheckmarkScoped(panelName),
    toggledVisible,
    reason:
        '[$panelName] Menu checkmark should be updated after toggle ($toggledVisible)',
  );

  // --- Second Toggle --- (Back to initial state)
  debugPrint('Toggling $panelName back via menu...');
  // Tap menu item again to toggle back
  await tapFlyoutItemByTextScoped(panelName);

  // Check ViewModel state reverted
  expect(
    isVisibleGetter(),
    initialVisible,
    reason: '[$panelName] ViewModel state should revert to $initialVisible',
  );
  debugPrint('$panelName ViewModel Visible after revert: ${isVisibleGetter()}');

  // Check UI Panel Widget visibility AFTER revert
  expect(
    panelWidgetFinder,
    initialVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Panel Widget visibility should revert ($initialVisible)',
  );
  debugPrint(
    '$panelName Panel Widget found after revert: ${tester.any(panelWidgetFinder)}',
  );

  // Check Menu checkmark visibility AFTER revert
  await tester.tap(viewMenuButtonFinder); // Re-open menu
  await tester.pumpAndSettle();
  expect(
    hasCheckmarkScoped(panelName),
    initialVisible,
    reason: '[$panelName] Menu checkmark should revert ($initialVisible)',
  );

  // Close the menu explicitly before finishing
  await tester.tap(viewMenuButtonFinder);
  await tester.pumpAndSettle();
  debugPrint('$panelName toggle test complete.');
  debugPrint('--- Test Passed: $panelName toggle ---');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory testTempDir;
  late String testTempDirPath;

  setUpAll(() async {
    testTempDir = await commonSetUpAll();
    testTempDirPath = testTempDir.path;
  });

  tearDown(() async {
    // Common tearDown logic is now only responsible for test-level cleanup
    await commonTearDown(testTempDirPath);
  });

  tearDownAll(() async {
    await commonTearDownAll(testTempDir);
  });

  // --- Test Setup Function ---
  // Common setup steps performed at the beginning of each testWidgets block
  Future<({EditorViewModel editorVm, Finder viewMenuButtonFinder})> setupTest(
    WidgetTester tester,
  ) async {
    debugPrint('Pumping FlipEditApp...');
    await tester.pumpWidget(FlipEditApp());
    // Increase settle time slightly if needed for initialization
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugPrint('App pumped.');

    late EditorViewModel editorVm;
    try {
      editorVm = di<EditorViewModel>();
      debugPrint('EditorViewModel retrieved from DI.');
    } catch (e) {
      debugPrint('Fatal Error: Failed to retrieve EditorViewModel from DI: $e');
      fail('Failed to get EditorViewModel from DI container.');
    }

    final viewMenuButtonFinder = find.widgetWithText(DropDownButton, 'View');
    expect(
      viewMenuButtonFinder,
      findsOneWidget,
      reason: 'Should find the "View" DropDownButton in setup',
    );

    return (editorVm: editorVm, viewMenuButtonFinder: viewMenuButtonFinder);
  }

  // --- Individual Test Cases ---

  // 'View menu toggles Inspector visibility and updates checkmark/panel',
  // (WidgetTester tester) async {
  //   debugPrint('--- Starting Test: View Menu - Inspector Toggle ---');

  //   await setupEditorScreenTest(tester);

  //   await testPanelToggleViaViewMenu(
  //     tester: tester,
  //     editorVm: di<EditorViewModel>(),
  //     panelName: 'Inspector',
  //     isVisibleGetter: () => di<EditorViewModel>().isInspectorVisible,
  //     viewMenuButtonFinder: findViewMenuButton(tester),
  //     panelWidgetFinder: find.byType(InspectorPanel),
  //   );

  //   debugPrint('--- Test Passed: View Menu - Inspector Toggle ---');
  // });

  // testWidgets(
  //   'View menu toggles Timeline visibility and updates checkmark/panel',
  //   (WidgetTester tester) async {
  //     debugPrint('\n=== Running Test: Timeline Toggle ===');
  //     final setup = await setupTest(tester);
  //     await _testPanelToggle(
  //       tester: tester,
  //       editorVm: setup.editorVm,
  //       panelName: 'Timeline',
  //       isVisibleGetter: () => setup.editorVm.isTimelineVisible,
  //       viewMenuButtonFinder: setup.viewMenuButtonFinder,
  //       panelWidgetFinder: find.byType(Timeline),
  //     );
  //     debugPrint('=== Finished Test: Timeline Toggle ===\n');
  //   },
  // );

  testWidgets(
    'View menu toggles Preview visibility and updates checkmark/panel',
    (WidgetTester tester) async {
      debugPrint('\n=== Running Test: Preview Toggle ===');
      final setup = await setupTest(tester);
      // await _testPanelToggle(
      //   tester: tester,
      //   editorVm: setup.editorVm,
      //   panelName: 'Player',
      //   isVisibleGetter: () => setup.editorVm.isPreviewVisible,
      //   viewMenuButtonFinder: setup.viewMenuButtonFinder,
      //   panelWidgetFinder: find.byType(PlayerPanel),
      // );
      debugPrint('=== Finished Test: Player Toggle ===\n'); // Updated log message
    },
  );
}
