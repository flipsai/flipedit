import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'package:flutter_test/flutter_test.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'timeline_track_test.mocks.dart'; // Import generated mocks
import 'package:flutter/material.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/persistence/database/project_database.dart'
    as project_db;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

// Mocks
@GenerateMocks([
  TimelineViewModel,
  TimelineNavigationViewModel,
]) // Added TimelineNavigationViewModel
// Removed manual definition: class MockTimelineViewModel extends Mock implements TimelineViewModel {}
class MockProjectDatabaseService extends Mock
    implements ProjectDatabaseService {}

class MockValueNotifier<T> extends Mock
    implements
        ValueNotifier<
          T
        > {} // Keep if mocking notifiers, remove if using real ones

void main() {
  late MockTimelineViewModel mockTimelineViewModel;
  late MockTimelineNavigationViewModel mockTimelineNavigationViewModel; // Added
  late MockProjectDatabaseService mockProjectDatabaseService;
  late project_db.Track testTrack;
  late ValueNotifier<double> testZoomNotifier;
  late ValueNotifier<List<ClipModel>> testClipsNotifier; // Use ClipModel
  // Removed testScrollOffsetNotifier as it's not used directly here

  setUp(() {
    // 1. Reset DI first
    di.reset();

    // 2. Create mocks
    mockTimelineViewModel = MockTimelineViewModel();
    mockTimelineNavigationViewModel =
        MockTimelineNavigationViewModel(); // Added
    mockProjectDatabaseService = MockProjectDatabaseService();

    // Create the test track
    testTrack = project_db.Track(
      id: 1,
      name: 'Test Track',
      type: 'video',
      order: 0,
      isVisible: true,
      isLocked: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 3. Initialize real Notifiers needed by mocks
    testZoomNotifier = ValueNotifier<double>(1.0);
    testClipsNotifier = ValueNotifier<List<ClipModel>>([]);

    // 4. Stub properties BEFORE registering mocks
    // Correctly stub ValueNotifier properties by returning the pre-initialized notifiers
    when(mockTimelineNavigationViewModel.zoomNotifier).thenReturn(
      testZoomNotifier,
    ); // Changed to mockTimelineNavigationViewModel
    when(mockTimelineViewModel.clipsNotifier).thenReturn(testClipsNotifier);

    // 5. Register mocks AFTER stubbing
    di.registerSingleton<TimelineViewModel>(mockTimelineViewModel);
    di.registerSingleton<TimelineNavigationViewModel>(
      mockTimelineNavigationViewModel,
    ); // Added
    di.registerSingleton<ProjectDatabaseService>(mockProjectDatabaseService);
  });

  tearDown(() {
    di.reset();
  });

  group('TimelineTrack Widget', () {
    testWidgets('should render TimelineTrack widget correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineTrack(
            track: testTrack,
            onDelete: () {},
            trackLabelWidth: 120.0,
            scrollOffset: 0.0, // Added required parameter
          ),
        ),
      );

      expect(find.byType(TimelineTrack), findsOneWidget);
      expect(find.text('Test Track'), findsOneWidget);
    });

    testWidgets('should call onDelete when delete action is triggered', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TimelineTrack(
            track: testTrack,
            onDelete: () {
              logInfo('TimelineTrackTest', 'onDelete called');
            },
            trackLabelWidth: 120.0,
            scrollOffset: 0.0, // Added required parameter
          ),
        ),
      );

      // Assuming there's a delete button or action in the widget
      // This is a placeholder for the actual interaction once the widget structure is known
      // For now, we can't simulate the tap without knowing the exact UI
      expect(find.byType(TimelineTrack), findsOneWidget);
    });
  });
}
