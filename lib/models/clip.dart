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
  /// The total duration of the original source file in milliseconds.
  final int sourceDurationMs;
  /// The timestamp within the source file where this clip starts playing, in milliseconds.
  final int startTimeInSourceMs;
  /// The timestamp within the source file where this clip stops playing, in milliseconds.
  /// This value should be clamped between [startTimeInSourceMs] and [sourceDurationMs].
  final int endTimeInSourceMs;
  /// The timestamp on the timeline track where this clip starts, in milliseconds.
  final int startTimeOnTrackMs;
  /// The timestamp on the timeline track where this clip ends, in milliseconds.
  /// This determines the visual length on the timeline.
  final int endTimeOnTrackMs;
  final List<Effect> effects;
  final Map<String, dynamic> metadata;

  /// Duration of the clip segment taken from the source file.
  int get durationInSourceMs => endTimeInSourceMs - startTimeInSourceMs;
  /// Duration of the clip as it appears on the timeline track.
  int get durationOnTrackMs => endTimeOnTrackMs - startTimeOnTrackMs;


  ClipModel({
    this.databaseId,
    required this.trackId,
    required this.name,
    required this.type,
    required this.sourcePath,
    required this.sourceDurationMs, // Added
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    required this.startTimeOnTrackMs,
    required this.endTimeOnTrackMs, // Added
    this.effects = const [],
    this.metadata = const {},
  }) : assert(endTimeInSourceMs >= startTimeInSourceMs, 'End time must be >= start time in source'),
       assert(endTimeOnTrackMs >= startTimeOnTrackMs, 'End time must be >= start time on track'),
       assert(endTimeInSourceMs <= sourceDurationMs, 'End time in source cannot exceed source duration'),
       assert(startTimeInSourceMs >= 0, 'Start time in source must be non-negative');

  ClipModel copyWith({
    Value<int?>? databaseId,
    int? trackId,
    String? name,
    ClipType? type,
    String? sourcePath,
    int? sourceDurationMs, // Added
    int? startTimeInSourceMs,
    int? endTimeInSourceMs,
    int? startTimeOnTrackMs,
    int? endTimeOnTrackMs, // Added
    List<Effect>? effects,
    Map<String, dynamic>? metadata,
  }) {
    return ClipModel(
      databaseId: databaseId == null ? this.databaseId : databaseId.value,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      type: type ?? this.type,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs, // Added
      startTimeInSourceMs: startTimeInSourceMs ?? this.startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs ?? this.endTimeInSourceMs,
      startTimeOnTrackMs: startTimeOnTrackMs ?? this.startTimeOnTrackMs,
      endTimeOnTrackMs: endTimeOnTrackMs ?? this.endTimeOnTrackMs, // Added
      effects: effects ?? this.effects,
      metadata: metadata ?? this.metadata,
    );
  }

  factory ClipModel.fromDbData(Clip dbData, {int? sourceDurationMs}) {
    // Estimate source duration robustly if not available
    final dbSourceDuration = dbData.sourceDurationMs;
    final estimatedSourceDuration = (dbData.endTimeInSourceMs - dbData.startTimeInSourceMs).clamp(0, 1 << 30); // Ensure non-negative estimate
    final actualSourceDuration = sourceDurationMs // Prefer explicitly passed value
                                ?? dbSourceDuration // Then value from DB
                                ?? estimatedSourceDuration; // Finally, estimate

    // Ensure start time is valid and non-negative
    final startTimeSource = dbData.startTimeInSourceMs.clamp(0, actualSourceDuration);

    // Ensure the upper limit for clamping endTimeInSourceMs is valid
    final validUpperClampLimit = (actualSourceDuration >= startTimeSource) ? actualSourceDuration : startTimeSource;

    return ClipModel(
      databaseId: dbData.id,
      trackId: dbData.trackId,
      name: dbData.name,
      type: ClipType.values.firstWhere(
            (e) => e.toString().split('.').last == dbData.type,
            orElse: () => ClipType.video,
          ),
      sourcePath: dbData.sourcePath,
      sourceDurationMs: actualSourceDuration, // Use retrieved or estimated
      startTimeInSourceMs: startTimeSource, // Use clamped start time
      // Clamp endTimeInSourceMs defensively on load, using the validated upper limit
      endTimeInSourceMs: dbData.endTimeInSourceMs.clamp(startTimeSource, validUpperClampLimit),
      startTimeOnTrackMs: dbData.startTimeOnTrackMs,
      // Use stored endTimeOnTrackMs if available, otherwise estimate using potentially clamped source times
      endTimeOnTrackMs: dbData.endTimeOnTrackMs ?? (dbData.startTimeOnTrackMs + (dbData.endTimeInSourceMs.clamp(startTimeSource, validUpperClampLimit) - startTimeSource)),
    );
  }

  ClipsCompanion toDbCompanion() {
    // Ensure source times are valid before saving
    final clampedEndTimeInSourceMs = endTimeInSourceMs.clamp(startTimeInSourceMs, sourceDurationMs);

    return ClipsCompanion(
      id: databaseId == null ? const Value.absent() : Value(databaseId!),
      trackId: Value(trackId),
      name: Value(name),
      type: Value(type.toString().split('.').last),
      sourcePath: Value(sourcePath),
      sourceDurationMs: Value(sourceDurationMs), // Added
      startTimeInSourceMs: Value(startTimeInSourceMs),
      endTimeInSourceMs: Value(clampedEndTimeInSourceMs), // Use clamped value
      startTimeOnTrackMs: Value(startTimeOnTrackMs),
      endTimeOnTrackMs: Value(endTimeOnTrackMs), // Added
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
  int get durationFrames => msToFrames(durationOnTrackMs); // Use durationOnTrackMs
  int get endFrame => msToFrames(endTimeOnTrackMs); // Use endTimeOnTrackMs

  int get startFrameInSource => msToFrames(startTimeInSourceMs);
  int get endFrameInSource => msToFrames(endTimeInSourceMs);
}
