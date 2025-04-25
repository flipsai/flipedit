import 'package:flutter_test/flutter_test.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:mockito/mockito.dart';
// Removed unused mockito/annotations.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/viewmodels/commands/timeline_command.dart';
// Removed unused move_clip_command.dart import

// Mocks
class MockTimelineViewModel extends Mock implements TimelineViewModel {
  // Override noSuchMethod with the correct signature
  @override
  dynamic noSuchMethod(Invocation invocation, {Object? returnValue, Object? returnValueForMissingStub}) {
    // Check if the method being called is runCommand
    if (invocation.memberName == Symbol('runCommand') && invocation.isMethod) {
       // Ensure there's at least one argument and it's a TimelineCommand
       if (invocation.positionalArguments.isNotEmpty && invocation.positionalArguments[0] is TimelineCommand) {
          return Future<void>.value(); // Return a completed Future for runCommand
       }
    }
    // Delegate other calls to the standard Mockito handling
    // Pass the optional parameters along to super
    return super.noSuchMethod(invocation, returnValue: returnValue, returnValueForMissingStub: returnValueForMissingStub);
  }
}
class MockProjectDatabaseService extends Mock implements ProjectDatabaseService {}
class MockEditorViewModel extends Mock implements EditorViewModel {}
class MockValueNotifier<T> extends Mock implements ValueNotifier<T> {}

void main() {
  late MockTimelineViewModel mockTimelineViewModel;
  late MockProjectDatabaseService mockProjectDatabaseService;
  late MockEditorViewModel mockEditorViewModel;
  late ClipModel testClip;
  late ValueNotifier<double> testZoomNotifier; // Added notifier
  late ValueNotifier<String?> testSelectedClipIdNotifier; // Added notifier

  setUp(() {
   // 1. Reset DI first
    di.reset();
    
   // 2. Create mocks
    mockTimelineViewModel = MockTimelineViewModel();
    mockProjectDatabaseService = MockProjectDatabaseService();
    mockEditorViewModel = MockEditorViewModel();

   // 3. Initialize real Notifiers needed by mocks
    testZoomNotifier = ValueNotifier<double>(1.0);
    testSelectedClipIdNotifier = ValueNotifier<String?>(null);

   // Note: Initializing the notifiers twice was redundant and removed.
   // The previous lines already initialize them.
 
    // Create test clip
    testClip = ClipModel(
      databaseId: 1,
      trackId: 1,
      name: 'Test Clip',
      type: ClipType.video,
      sourcePath: 'path/to/video.mp4',
      startTimeInSourceMs: 0,
      endTimeInSourceMs: 1000,
      startTimeOnTrackMs: 0,
      effects: [],
      metadata: {},
    );
  
    // 4. Stub properties BEFORE registering mocks
   // 4. Stub properties BEFORE registering mocks
   // Correctly stub ValueNotifier properties by returning the pre-initialized notifiers
    when(mockTimelineViewModel.zoomNotifier).thenReturn(testZoomNotifier);
    when(mockEditorViewModel.selectedClipIdNotifier).thenReturn(testSelectedClipIdNotifier);
 
     // 5. Register mocks AFTER stubbing
    di.registerSingleton<TimelineViewModel>(mockTimelineViewModel);
    di.registerSingleton<ProjectDatabaseService>(mockProjectDatabaseService);
    di.registerSingleton<EditorViewModel>(mockEditorViewModel);
  });

  tearDown(() {
    di.reset();
  });

  group('TimelineClip Widget', () {
    testWidgets('should render TimelineClip widget correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: TimelineClip(
            clip: testClip,
            trackId: 1,
          ),
        ),
      );

      expect(find.byType(TimelineClip), findsOneWidget);
      expect(find.text('Test Clip'), findsOneWidget);
    });

    testWidgets('should render with isDragging state', (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: TimelineClip(
            clip: testClip,
            trackId: 1,
            isDragging: true,
          ),
        ),
      );

      expect(find.byType(TimelineClip), findsOneWidget);
      // Additional assertions can be added based on how isDragging affects rendering
    });
  });
}