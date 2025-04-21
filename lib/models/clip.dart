import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:drift/drift.dart' show Value;

// Import the generated part of project_database which contains the Clip class
import 'package:flipedit/persistence/database/project_database.dart' show Clip, ClipsCompanion;

class ClipModel {
  final int? databaseId;
  final int trackId;
  final String name;
  final ClipType type;
  final String sourcePath;
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;
  final int startTimeOnTrackMs;
  final List<Effect> effects;
  final Map<String, dynamic> metadata;

  int get durationMs => endTimeInSourceMs - startTimeInSourceMs;

  ClipModel({
    this.databaseId,
    required this.trackId,
    required this.name,
    required this.type,
    required this.sourcePath,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    required this.startTimeOnTrackMs,
    this.effects = const [],
    this.metadata = const {},
  }) : assert(endTimeInSourceMs >= startTimeInSourceMs, 'End time must be >= start time in source');

  ClipModel copyWith({
    Value<int?>? databaseId,
    int? trackId,
    String? name,
    ClipType? type,
    String? sourcePath,
    int? startTimeInSourceMs,
    int? endTimeInSourceMs,
    int? startTimeOnTrackMs,
    List<Effect>? effects,
    Map<String, dynamic>? metadata,
  }) {
    return ClipModel(
      databaseId: databaseId == null ? this.databaseId : databaseId.value,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      type: type ?? this.type,
      sourcePath: sourcePath ?? this.sourcePath,
      startTimeInSourceMs: startTimeInSourceMs ?? this.startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs ?? this.endTimeInSourceMs,
      startTimeOnTrackMs: startTimeOnTrackMs ?? this.startTimeOnTrackMs,
      effects: effects ?? this.effects,
      metadata: metadata ?? this.metadata,
    );
  }

  factory ClipModel.fromDbData(Clip dbData) {
    return ClipModel(
      databaseId: dbData.id,
      trackId: dbData.trackId,
      name: dbData.name,
      type: ClipType.values.firstWhere(
            (e) => e.toString().split('.').last == dbData.type,
            orElse: () => ClipType.video,
          ),
      sourcePath: dbData.sourcePath,
      startTimeInSourceMs: dbData.startTimeInSourceMs,
      endTimeInSourceMs: dbData.endTimeInSourceMs,
      startTimeOnTrackMs: dbData.startTimeOnTrackMs,
    );
  }

  ClipsCompanion toDbCompanion() {
    return ClipsCompanion(
      id: databaseId == null ? const Value.absent() : Value(databaseId!),
      trackId: Value(trackId),
      name: Value(name),
      type: Value(type.toString().split('.').last),
      sourcePath: Value(sourcePath),
      startTimeInSourceMs: Value(startTimeInSourceMs),
      endTimeInSourceMs: Value(endTimeInSourceMs),
      startTimeOnTrackMs: Value(startTimeOnTrackMs),
    );
  }

  static const double _defaultFrameRate = 30.0;

  static int msToFrames(int ms) {
    return (ms * _defaultFrameRate / 1000).round();
  }

  static int framesToMs(int frames) {
    return (frames * 1000 / _defaultFrameRate).round();
  }

  int get startFrame => msToFrames(startTimeOnTrackMs);
  int get durationFrames => msToFrames(durationMs);
  int get endFrame => startFrame + durationFrames;

  int get startFrameInSource => msToFrames(startTimeInSourceMs);
  int get endFrameInSource => msToFrames(endTimeInSourceMs);
}
