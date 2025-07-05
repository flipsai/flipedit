import 'package:fluent_ui/fluent_ui.dart'; // For DropDownButton, FlyoutListTile, FluentIcons
import 'package:flipedit/viewmodels/editor_viewmodel.dart'; // For EditorViewModel

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_it/watch_it.dart'; // For di

// --- Helper Functions for Editor Integration Tests ---

/// Creates a new project, loads it, and returns the project ID.
Future<int> createAndLoadProject(
  WidgetTester tester,
  String projectName,
) async {
  final projectVm = di<ProjectViewModel>();
  final projectId = await projectVm.createNewProject(projectName);
  expect(
    projectId,
    isNotNull,
    reason: 'Project creation should return a valid ID.',
  );
  expect(projectId, greaterThan(0), reason: 'Project ID should be positive.');

  await projectVm.loadProject(projectId);
  // Allow time for project loading and UI updates
  await tester.pumpAndSettle(const Duration(seconds: 2));
  logInfo('Created and loaded project "$projectName" (ID: $projectId)');
  return projectId;
}

/// Imports a media asset directly into the currently loaded project's database.
Future<void> importTestMedia(
  WidgetTester tester, {
  required String fileName,
  required String filePath,
  required ClipType type,
  required int durationMs,
}) async {
  final dbService = di<ProjectDatabaseService>();
  expect(
    dbService.currentDatabase,
    isNotNull,
    reason: 'A project must be open to import media.',
  );

  await dbService.importAsset(
    filePath: filePath,
    type: type,
    durationMs: durationMs,
  );
  // Allow time for the media list panel to update
  await tester.pumpAndSettle(const Duration(seconds: 2));
  logInfo('Imported test media: $fileName');
}

/// Finds the Draggable<ClipModel> widget associated with a media file name in the media panel.
Future<Finder> findMediaPanelDraggable(
  WidgetTester tester,
  String mediaFileName,
) async {
  // Assuming the Draggable wraps a widget containing the text (e.g., ListTile -> Text)
  // Adjust finder logic if the widget structure is different.
  final draggableFinder = find.widgetWithText(
    Draggable<ClipModel>,
    mediaFileName,
  );

  expect(
    draggableFinder,
    findsOneWidget,
    reason:
        'Expected to find one Draggable<ClipModel> containing text "$mediaFileName" in the media panel.',
  );
  logInfo('Found draggable for media: $mediaFileName');
  return draggableFinder;
}

/// Performs a drag-and-drop operation from a source finder (draggable) to a target finder (timeline).
/// Optionally accepts a dropOffset relative to the timeline's top-left corner.
Future<void> dragMediaToTimeline(
  WidgetTester tester,
  Finder draggableFinder,
  Finder timelineFinder, {
  Offset dropOffset = const Offset(
    100,
    50,
  ), // Default drop slightly into the timeline area
}) async {
  expect(
    draggableFinder,
    findsOneWidget,
    reason: 'Draggable finder must locate exactly one widget.',
  );
  expect(
    timelineFinder,
    findsOneWidget,
    reason: 'Timeline finder must locate exactly one widget.',
  );

  final Offset draggableCenter = tester.getCenter(draggableFinder);
  final Offset timelineTopLeft = tester.getTopLeft(timelineFinder);
  final Offset targetDropPosition = timelineTopLeft + dropOffset;

  logInfo(
    'Dragging from $draggableCenter to $targetDropPosition (Timeline TopLeft: $timelineTopLeft, Offset: $dropOffset)',
  );

  await tester.dragFrom(draggableCenter, targetDropPosition);
  // Allow time for the drop operation, database updates, and UI refresh
  await tester.pumpAndSettle(
    const Duration(seconds: 3),
  ); // Increased settle time might be needed
  logInfo('Drag and drop completed.');
}

/// Verifies that at least one track and at least one clip exist in the database after an operation.
Future<void> verifyTrackAndClipCreation(WidgetTester tester) async {
  final dbService = di<ProjectDatabaseService>();
  expect(
    dbService.currentDatabase,
    isNotNull,
    reason: 'A project must be open to verify tracks/clips.',
  );

  // Check tracks via Notifier (assuming it's updated)
  final tracks = dbService.tracksNotifier.value;
  expect(
    tracks,
    isNotEmpty,
    reason: 'Expected at least one track to be created.',
  );
  logInfo('Verified track creation (found ${tracks.length} track(s)).');

  // Check clips directly in the database
  final clipDao = dbService.clipDao;
  expect(
    clipDao,
    isNotNull,
    reason: 'ClipDao should be available in the open project.',
  );
  final allClips =
      await dbService.currentDatabase!
          .select(dbService.currentDatabase!.clips)
          .get();
  expect(
    allClips,
    isNotEmpty,
    reason: 'Expected at least one clip to be created in the database.',
  );
  logInfo('Verified clip creation (found ${allClips.length} clip(s) in DB).');

  // Optional: Verify UI representation (e.g., find TimelineClip widget)
  // final timelineClipFinder = find.byType(TimelineClip);
  // expect(timelineClipFinder, findsWidgets, reason: 'Expected to find TimelineClip widget(s) in the UI.');
}

// Add more helpers as needed (e.g., findTimelineClip, verifyClipPosition, etc.)
// --- Helper Functions for View Menu Toggling (from view_menu_integration_test.dart) ---

// Helper to find the "View" menu DropDownButton by finding the Text('View') first
Finder findViewMenuButton(WidgetTester tester) {
  // Find the Text widget first
  final textFinder = find.text('View');
  expect(
    textFinder,
    findsOneWidget,
    reason: 'Should find the Text widget "View" for the menu button',
  );

  // Find the DropDownButton ancestor of that Text widget
  final buttonFinder = find.ancestor(
    of: textFinder,
    matching: find.byType(DropDownButton),
  );
  expect(
    buttonFinder,
    findsOneWidget,
    reason: 'Should find the DropDownButton ancestor of the "View" Text',
  );
  return buttonFinder;
}

/// Tests toggling the visibility of a specific panel via the View menu.
/// Requires EditorViewModel, panel name, getter for visibility state,
/// the view menu button finder, and the panel widget finder.
Future<void> testPanelToggleViaViewMenu({
  required WidgetTester tester,
  required EditorViewModel editorVm,
  required String panelName,
  required ValueGetter<bool> isVisibleGetter,
  required Finder viewMenuButtonFinder,
  required Finder panelWidgetFinder,
}) async {
  // --- Scoped Helper Functions (Specific to this test helper) ---
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

  Future<void> tapFlyoutItemByTextScoped(String text) async {
    final lastTextFinder = findLastTextWidget(text);
    await tester.tap(lastTextFinder);
    await tester.pumpAndSettle();
  }
  // --- End Scoped Helper Functions ---

  logInfo('--- Testing $panelName toggle via View Menu ---');
  bool initialVisible = isVisibleGetter();
  logInfo('Initial $panelName Visible: $initialVisible');

  // Initial UI Check:
  expect(
    panelWidgetFinder,
    initialVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Initial Panel Widget visibility should match state ($initialVisible)',
  );

  // --- First Toggle ---
  logInfo('Toggling $panelName via menu...');
  await tester.tap(viewMenuButtonFinder); // Open menu
  await tester.pumpAndSettle();

  expect(
    hasCheckmarkScoped(panelName),
    initialVisible,
    reason:
        '[$panelName] Menu checkmark should match initial state ($initialVisible)',
  );
  await tapFlyoutItemByTextScoped(panelName); // Tap menu item to toggle

  bool toggledVisible = !initialVisible;
  expect(
    isVisibleGetter(),
    toggledVisible,
    reason:
        '[$panelName] ViewModel state should have toggled to $toggledVisible',
  );
  logInfo('$panelName ViewModel Visible after toggle: ${isVisibleGetter()}');
  expect(
    panelWidgetFinder,
    toggledVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Panel Widget visibility should be updated after toggle ($toggledVisible)',
  );
  logInfo(
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
  logInfo('Toggling $panelName back via menu...');
  await tapFlyoutItemByTextScoped(panelName); // Tap menu item again

  expect(
    isVisibleGetter(),
    initialVisible,
    reason: '[$panelName] ViewModel state should revert to $initialVisible',
  );
  logInfo('$panelName ViewModel Visible after revert: ${isVisibleGetter()}');
  expect(
    panelWidgetFinder,
    initialVisible ? findsOneWidget : findsNothing,
    reason:
        '[$panelName] Panel Widget visibility should revert ($initialVisible)',
  );
  logInfo(
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
  logInfo('$panelName toggle test complete.');
}
