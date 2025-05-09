import 'dart:convert';
import 'dart:ui'; // Import Rect
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:drift/drift.dart' show Value;

// Import the generated part of project_database which contains the Clip class
import 'package:flipedit/persistence/database/project_database.dart'
    show Clip, ClipsCompanion;
import 'package:flutter_box_transform/flutter_box_transform.dart'
    show Flip; // Import Flip

class ClipValidationException implements Exception {
  final List<String> errors;

  ClipValidationException(this.errors);

  @override
  String toString() => 'Invalid clip configuration:\n${errors.join('\n')}';
}

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
    required this.sourceDurationMs,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
    required this.startTimeOnTrackMs,
    required this.endTimeOnTrackMs,
    this.effects = const [],
    this.metadata = const {},
  }) {
    _validateClipTimes(
      startTimeInSourceMs: startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs,
      startTimeOnTrackMs: startTimeOnTrackMs,
      endTimeOnTrackMs: endTimeOnTrackMs,
      sourceDurationMs: sourceDurationMs,
    );
  }

  static void _validateClipTimes({
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
    required int startTimeOnTrackMs,
    required int endTimeOnTrackMs,
    required int sourceDurationMs,
  }) {
    // Auto-correct inverted time ranges
    var correctedStartTimeOnTrack = startTimeOnTrackMs;
    var correctedEndTimeOnTrack = endTimeOnTrackMs;
    if (correctedEndTimeOnTrack < correctedStartTimeOnTrack) {
      final temp = correctedStartTimeOnTrack;
      correctedStartTimeOnTrack = correctedEndTimeOnTrack;
      correctedEndTimeOnTrack = temp;
    }

    var correctedStartTimeInSource = startTimeInSourceMs;
    var correctedEndTimeInSource = endTimeInSourceMs;
    if (correctedEndTimeInSource < correctedStartTimeInSource) {
      final temp = correctedStartTimeInSource;
      correctedStartTimeInSource = correctedEndTimeInSource;
      correctedEndTimeInSource = temp;
    }

    final errors = <String>[];

    if (correctedEndTimeInSource < correctedStartTimeInSource) {
      errors.add(
        'Source end time ($correctedEndTimeInSource) < start time ($correctedStartTimeInSource)',
      );
    }

    if (correctedEndTimeOnTrack < correctedStartTimeOnTrack) {
      errors.add(
        'Track end time ($correctedEndTimeOnTrack) < start time ($correctedStartTimeOnTrack)',
      );
    }

    if (endTimeInSourceMs > sourceDurationMs) {
      errors.add(
        'Source end time ($endTimeInSourceMs) exceeds duration ($sourceDurationMs)',
      );
    }

    if (startTimeInSourceMs < 0) {
      errors.add('Negative source start time: $startTimeInSourceMs');
    }

    if (errors.isNotEmpty) {
      throw ClipValidationException(errors);
    }
  }

  static bool isValidClip({
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
    required int startTimeOnTrackMs,
    required int endTimeOnTrackMs,
    required int sourceDurationMs,
  }) {
    try {
      _validateClipTimes(
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
        startTimeOnTrackMs: startTimeOnTrackMs,
        endTimeOnTrackMs: endTimeOnTrackMs,
        sourceDurationMs: sourceDurationMs,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  ClipModel copyWith({
    Value<int?>? databaseId,
    int? trackId,
    String? name,
    ClipType? type,
    String? sourcePath,
    int? sourceDurationMs,
    int? startTimeInSourceMs,
    int? endTimeInSourceMs,
    int? startTimeOnTrackMs,
    int? endTimeOnTrackMs,
    List<Effect>? effects,
    Map<String, dynamic>? metadata,
  }) {
    return ClipModel(
      databaseId: databaseId == null ? this.databaseId : databaseId.value,
      trackId: trackId ?? this.trackId,
      name: name ?? this.name,
      type: type ?? this.type,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      startTimeInSourceMs: startTimeInSourceMs ?? this.startTimeInSourceMs,
      endTimeInSourceMs: endTimeInSourceMs ?? this.endTimeInSourceMs,
      startTimeOnTrackMs: startTimeOnTrackMs ?? this.startTimeOnTrackMs,
      endTimeOnTrackMs: endTimeOnTrackMs ?? this.endTimeOnTrackMs,
      effects: effects ?? this.effects,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Get the preview rectangle from metadata, or null if not set.
  /// The rectangle is stored as a map with 'left', 'top', 'width', 'height'.
  Rect? get previewRect {
    final rectMap = metadata['previewRect'] as Map<String, dynamic>?;
    if (rectMap == null) return null;
    return Rect.fromLTWH(
      rectMap['left'] as double,
      rectMap['top'] as double,
      rectMap['width'] as double,
      rectMap['height'] as double,
    );
  }

  /// Creates a new ClipModel with the preview rectangle updated in metadata.
  ClipModel copyWithPreviewRect(Rect? rect) {
    final updatedMetadata = Map<String, dynamic>.from(metadata);
    if (rect == null) {
      updatedMetadata.remove('previewRect');
    } else {
      updatedMetadata['previewRect'] = {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }
    return copyWith(metadata: updatedMetadata);
  }

  /// Get the preview flip state from metadata, or Flip.none if not set.
  /// Stored as an integer: 0=none, 1=horizontal, 2=vertical, 3=both.
  Flip get previewFlip {
    final flipInt = metadata['previewFlip'] as int?;
    switch (flipInt) {
      case 1:
        return Flip.horizontal;
      case 2:
        return Flip.vertical;
      default:
        return Flip.none;
    }
  }

  /// Creates a new ClipModel with the preview flip state updated in metadata.
  ClipModel copyWithPreviewFlip(Flip? flip) {
    final updatedMetadata = Map<String, dynamic>.from(metadata);
    if (flip == null || flip == Flip.none) {
      updatedMetadata.remove('previewFlip');
    } else {
      int? flipInt; // Use nullable int
      if (flip == Flip.horizontal) flipInt = 1;
      if (flip == Flip.vertical) flipInt = 2;

      if (flipInt != null) {
        updatedMetadata['previewFlip'] = flipInt;
      } else {
        // Ensure removal if it becomes Flip.none again
        updatedMetadata.remove('previewFlip');
      }
    }
    return copyWith(metadata: updatedMetadata);
  }

  factory ClipModel.fromDbData(Clip dbData, {int? sourceDurationMs}) {
    // Estimate source duration robustly if not available
    final dbSourceDuration = dbData.sourceDurationMs;
    final estimatedSourceDuration = (dbData.endTimeInSourceMs -
            dbData.startTimeInSourceMs)
        .clamp(0, 1 << 30); // Ensure non-negative estimate
    final actualSourceDuration =
        sourceDurationMs // Prefer explicitly passed value
        ??
        dbSourceDuration // Then value from DB
        ??
        estimatedSourceDuration; // Finally, estimate

    // Ensure start time is valid and non-negative
    final startTimeSource = dbData.startTimeInSourceMs.clamp(
      0,
      actualSourceDuration,
    );

    // Ensure the upper limit for clamping endTimeInSourceMs is valid
    final validUpperClampLimit =
        (actualSourceDuration >= startTimeSource)
            ? actualSourceDuration
            : startTimeSource;

    final Map<String, dynamic> loadedMetadata =
        dbData.metadataJson != null
            ? jsonDecode(dbData.metadataJson!) as Map<String, dynamic>
            : const {};

    return ClipModel(
      databaseId: dbData.id,
      trackId: dbData.trackId,
      name: dbData.name,
      type: ClipType.values.firstWhere(
        (e) => e.toString().split('.').last == dbData.type,
        orElse: () => ClipType.video,
      ),
      sourcePath: dbData.sourcePath,
      sourceDurationMs: actualSourceDuration,
      startTimeInSourceMs: startTimeSource,
      endTimeInSourceMs: dbData.endTimeInSourceMs.clamp(
        startTimeSource,
        validUpperClampLimit,
      ),
      startTimeOnTrackMs: dbData.startTimeOnTrackMs,
      endTimeOnTrackMs:
          dbData.endTimeOnTrackMs ??
          (dbData.startTimeOnTrackMs +
              (dbData.endTimeInSourceMs.clamp(
                    startTimeSource,
                    validUpperClampLimit,
                  ) -
                  startTimeSource)),
      metadata: loadedMetadata,
    );
  }

  ClipsCompanion toDbCompanion() {
    // Ensure source times are valid before saving
    final clampedEndTimeInSourceMs = endTimeInSourceMs.clamp(
      startTimeInSourceMs,
      sourceDurationMs,
    );

    return ClipsCompanion(
      id: databaseId == null ? const Value.absent() : Value(databaseId!),
      trackId: Value(trackId),
      name: Value(name),
      type: Value(type.toString().split('.').last),
      sourcePath: Value(sourcePath),
      sourceDurationMs: Value(sourceDurationMs),
      startTimeInSourceMs: Value(startTimeInSourceMs),
      endTimeInSourceMs: Value(clampedEndTimeInSourceMs),
      startTimeOnTrackMs: Value(startTimeOnTrackMs),
      endTimeOnTrackMs: Value(endTimeOnTrackMs),
      metadataJson: Value(metadata.isNotEmpty ? jsonEncode(metadata) : null),
    );
  }

  static const double _defaultFrameRate = 30.0;

  // Define a constant for the frame duration in milliseconds
  static const double _msPerFrame =
      1000.0 / _defaultFrameRate; // 33.33... ms per frame at 30fps

  static int msToFrames(int ms) {
    // Use floor division for more consistent frame alignment
    // This ensures we never jump ahead to the next frame prematurely
    return (ms / _msPerFrame).floor();
  }

  static int framesToMs(int frames) {
    // Use exact multiplication to ensure consistent frame boundaries
    // This gives us precisely 33.33... ms per frame
    return (frames * _msPerFrame).round();
  }

  // Helper method to ensure a time value is aligned to frame boundaries
  static int alignToFrameBoundary(int ms) {
    // First, convert to frames (rounds down to nearest frame)
    final int frames = msToFrames(ms);
    // Then convert back to milliseconds (gives exact frame boundary time)
    return framesToMs(frames);
  }

  // Helper to get the next frame boundary after a given time
  static int nextFrameBoundary(int ms) {
    // Convert to frames, add 1, then convert back to ms
    final int frames = msToFrames(ms);
    return framesToMs(frames + 1);
  }

  // Helper to get the previous frame boundary before a given time
  static int previousFrameBoundary(int ms) {
    // Convert to frames, subtract 1, then convert back to ms
    final int frames = msToFrames(ms);
    return framesToMs(frames - 1 < 0 ? 0 : frames - 1);
  }

  int get startFrame => msToFrames(startTimeOnTrackMs);
  int get durationFrames => msToFrames(durationOnTrackMs);
  int get endFrame => msToFrames(endTimeOnTrackMs);

  int get startFrameInSource => msToFrames(startTimeInSourceMs);
  int get endFrameInSource => msToFrames(endTimeInSourceMs);
  Map<String, dynamic> toJson() {
    // Debug log for metadata conversion to json
    print('ClipModel.toJson: Converting clip ${databaseId} to JSON');
    print('ClipModel.toJson: metadata content: $metadata');
    if (metadata.containsKey('previewRect')) {
      print('ClipModel.toJson: previewRect found: ${metadata['previewRect']}');
    } else {
      print('ClipModel.toJson: No previewRect found in metadata');
    }
    
    // Select fields relevant for the preview server
    return {
      'databaseId': databaseId,
      'trackId': trackId,
      'name': name,
      'type': type.toString().split('.').last, // Send enum name as string
      'sourcePath': sourcePath,
      'sourceDurationMs': sourceDurationMs,
      'startTimeInSourceMs': startTimeInSourceMs,
      'endTimeInSourceMs': endTimeInSourceMs,
      'startTimeOnTrackMs': startTimeOnTrackMs,
      'endTimeOnTrackMs': endTimeOnTrackMs,
      'metadata': metadata,
    };
  }
}
