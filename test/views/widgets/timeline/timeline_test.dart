import 'package:flutter_test/flutter_test.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline.dart';
import 'package:mockito/mockito.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/undo_redo_service.dart'; // Keep for Mock definition if needed elsewhere, though not used here
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'package:flipedit/persistence/database/project_database.dart' as project_db; // Import for Track type


// Mocks
class MockTimelineViewModel extends Mock implements TimelineViewModel {}
class MockProjectDatabaseService extends Mock implements ProjectDatabaseService {}
class MockUndoRedoService extends Mock implements UndoRedoService {} // Keep mock class definition
class MockValueNotifier<T> extends Mock implements ValueNotifier<T> {} // Add mock notifier helper

void main() {
  late MockTimelineViewModel mockTimelineViewModel;
  late MockProjectDatabaseService mockProjectDatabaseService;
  // Notifiers and Controllers needed by Timeline widget
  late ValueNotifier<List<ClipModel>> testClipsNotifier;
  late ValueNotifier<int> testCurrentFrameNotifier;
  late ValueNotifier<double> testZoomNotifier;
  late ValueNotifier<int> testTotalFramesNotifier;
  late ValueNotifier<double> testTrackLabelWidthNotifier;
  late ScrollController testScrollController;
  late ValueNotifier<List<project_db.Track>> testTracksNotifier;
  
  // Define a static empty callback for test purposes
  void _emptyCallback() {}


  setUp(() {
   // 1. Reset DI first
    di.reset();
    
   // 2. Create mocks
    mockTimelineViewModel = MockTimelineViewModel();
    mockProjectDatabaseService = MockProjectDatabaseService();

   // 3. Initialize real Notifiers/Controller needed by mocks
    testClipsNotifier = ValueNotifier<List<ClipModel>>([]);
    testCurrentFrameNotifier = ValueNotifier<int>(0);
    testZoomNotifier = ValueNotifier<double>(1.0);
    testTotalFramesNotifier = ValueNotifier<int>(0);
    testTrackLabelWidthNotifier = ValueNotifier<double>(120.0);
    testScrollController = ScrollController();
    testTracksNotifier = ValueNotifier<List<project_db.Track>>([]);
 
   // 4. Stub all properties BEFORE registering mocks
    // Use thenAnswer for view model properties
    // Correctly stub properties by returning the pre-initialized notifiers and controllers
    when(mockTimelineViewModel.clipsNotifier).thenReturn(testClipsNotifier);
    when(mockTimelineViewModel.currentFrameNotifier).thenReturn(testCurrentFrameNotifier);
    when(mockTimelineViewModel.zoomNotifier).thenReturn(testZoomNotifier);
    when(mockTimelineViewModel.totalFramesNotifier).thenReturn(testTotalFramesNotifier);
    when(mockTimelineViewModel.trackLabelWidthNotifier).thenReturn(testTrackLabelWidthNotifier);
    when(mockProjectDatabaseService.tracksNotifier).thenReturn(testTracksNotifier); // Keep as is for service mock
 
   // 5. Register mocks AFTER all stubbing is complete
    di.registerSingleton<TimelineViewModel>(mockTimelineViewModel);
    di.registerSingleton<ProjectDatabaseService>(mockProjectDatabaseService);
  });

  tearDown(() {
    // Dispose ScrollController in tearDown to ensure it's disposed after each test
    testScrollController.dispose();
    di.reset();
  });

  group('Timeline Widget', () {
    testWidgets('should render Timeline widget correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: const Timeline(), // Remove parameters
        ),
      );

      expect(find.byType(Timeline), findsOneWidget);
    });

    testWidgets('should display timeline content based on view model', (WidgetTester tester) async {
      // This test would depend on the specific UI elements in Timeline
      // For now, a placeholder test to ensure rendering
      await tester.pumpWidget(
        FluentApp(
          home: const Timeline(), // Remove parameters
        ),
      );

      // Add specific assertions based on Timeline widget structure once known
      expect(find.byType(Timeline), findsOneWidget);
    });
  });
}