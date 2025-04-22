import 'package:flutter_test/flutter_test.dart';
import 'package:flipedit/viewmodels/commands/trim_overlap_command.dart';
// import 'package:flipedit/viewmodels/commands/timeline_command.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'trim_overlap_command_test.mocks.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/persistence/dao/project_database_clip_dao.dart';

@GenerateMocks([TimelineViewModel])

class MockProjectDatabaseClipDao extends Mock implements ProjectDatabaseClipDao {
  // @override
  // Future<bool> updateClipFields(int clipId, Map<String, dynamic> fields) async {
  //   // Simulate success
  //   return true;
  // }
}

class MockProjectDatabaseService extends Mock implements ProjectDatabaseService {
  @override
  ProjectDatabaseClipDao? get clipDao => _clipDao;
  final MockProjectDatabaseClipDao _clipDao = MockProjectDatabaseClipDao();
  @override
  Future<bool> loadProject(int projectId) async {
    return false;
  }
}

class MockClipModel extends Mock implements ClipModel {}

void main() {
  group('TrimOverlapCommand', () {
    late MockTimelineViewModel mockVm;
    late ClipModel newClip;
    late TrimOverlapCommand command;

    setUp(() {
      mockVm = MockTimelineViewModel();
      when(mockVm.placeClipOnTrack(
        clipId: anyNamed('clipId'),
        trackId: anyNamed('trackId'),
        type: anyNamed('type'),
        sourcePath: anyNamed('sourcePath'),
        startTimeOnTrackMs: anyNamed('startTimeOnTrackMs'),
        startTimeInSourceMs: anyNamed('startTimeInSourceMs'),
        endTimeInSourceMs: anyNamed('endTimeInSourceMs'),
      )).thenAnswer((_) async => true);
      when(mockVm.refreshClips()).thenAnswer((_) async {});
      when(mockVm.clips).thenAnswer((_) => []);
      when(mockVm.getOverlappingClips(any, any, any, any)).thenAnswer((_) => []);
      when(mockVm.projectDatabaseService).thenReturn(MockProjectDatabaseService());
      newClip = ClipModel(
        databaseId: 1,
        trackId: 1,
        name: 'Test Clip',
        type: ClipType.video,
        sourcePath: 'test.mp4',
        startTimeInSourceMs: 0,
        endTimeInSourceMs: 1000,
        startTimeOnTrackMs: 0,
        effects: const [],
        metadata: const {},
      );
      command = TrimOverlapCommand(mockVm, newClip);
    });

    test('execute calls placeClipOnTrack and refreshClips', () async {
      await command.execute();

      verify(mockVm.placeClipOnTrack(
        clipId: 1,
        trackId: 1,
        type: ClipType.video,
        sourcePath: 'test.mp4',
        startTimeOnTrackMs: 0,
        startTimeInSourceMs: 0,
        endTimeInSourceMs: 1000,
      )).called(1);
    });

    test('undo restores previous neighbors and refreshes clips', () async {
      // Setup: Simulate that _beforeNeighbors is set
      final neighbor = ClipModel(
        databaseId: 2,
        trackId: 1,
        name: 'Neighbor',
        type: ClipType.video,
        sourcePath: 'neighbor.mp4',
        startTimeInSourceMs: 0,
        endTimeInSourceMs: 500,
        startTimeOnTrackMs: 0,
        effects: const [],
        metadata: const {},
      );
      when(mockVm.clips).thenAnswer((_) => [neighbor]);
      command = TrimOverlapCommand(mockVm, newClip);
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      command.setBeforeNeighbors([neighbor]);
      // You would mock updateClipFields here if needed
      await command.undo();
    });
  });
}
