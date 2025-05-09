import 'dart:convert';
import 'dart:ui'; // Import Rect
import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:drift/drift.dart' show Value;

// Import the generated part of project_database which contains the Clip class
import 'package:flipedit/persistence/database/project_database.dart'
    show Clip, ClipsCompanion;

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

  // Preview transformation properties
  final double previewPositionX;
  final double previewPositionY;
  final double previewWidth;
  final double previewHeight;

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
    this.previewPositionX = 0.0,
    this.previewPositionY = 0.0,
    this.previewWidth = 100.0,
    this.previewHeight = 100.0,
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
    double? previewPositionX,
    double? previewPositionY,
    double? previewWidth,
    double? previewHeight,
  }) {
    final finalPreviewPositionX = previewPositionX ?? this.previewPositionX;
    final finalPreviewPositionY = previewPositionY ?? this.previewPositionY;
    final finalPreviewWidth = previewWidth ?? this.previewWidth;
    final finalPreviewHeight = previewHeight ?? this.previewHeight;

    final Map<String, dynamic> baseMetadata = metadata ?? this.metadata;
    final updatedMetadata = Map<String, dynamic>.from(baseMetadata);

    updatedMetadata['preview_position_x'] = finalPreviewPositionX;
    updatedMetadata['preview_position_y'] = finalPreviewPositionY;
    updatedMetadata['preview_width'] = finalPreviewWidth;
    updatedMetadata['preview_height'] = finalPreviewHeight;

    updatedMetadata.remove('preview_scale');
    updatedMetadata.remove('preview_rotation');
    updatedMetadata.remove('preview_flip_x');
    updatedMetadata.remove('preview_flip_y');
    updatedMetadata.remove('previewRect');

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
      metadata: updatedMetadata, // Use the synchronized metadata
      previewPositionX: finalPreviewPositionX, // Use the final value
      previewPositionY: finalPreviewPositionY, // Use the final value
      previewWidth: finalPreviewWidth,         // Use the final value
      previewHeight: finalPreviewHeight,       // Use the final value
    );
  }

  ClipsCompanion toCompanion() {
    return ClipsCompanion(
      id: databaseId == null ? const Value.absent() : Value(databaseId!),
      trackId: Value(trackId),
      name: Value(name),
      type: Value(type.name),
      sourcePath: Value(sourcePath),
      sourceDurationMs: Value(sourceDurationMs),
      startTimeInSourceMs: Value(startTimeInSourceMs),
      endTimeInSourceMs: Value(endTimeInSourceMs),
      startTimeOnTrackMs: Value(startTimeOnTrackMs),
      endTimeOnTrackMs: Value(endTimeOnTrackMs),
      metadata: Value(metadata.isNotEmpty ? jsonEncode(metadata) : null),
      previewPositionX: Value(previewPositionX),
      previewPositionY: Value(previewPositionY),
      previewWidth: Value(previewWidth),
      previewHeight: Value(previewHeight),
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
        dbData.metadata != null
            ? jsonDecode(dbData.metadata!) as Map<String, dynamic>
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
      previewPositionX: dbData.previewPositionX ?? 0.0,
      previewPositionY: dbData.previewPositionY ?? 0.0,
      previewWidth: dbData.previewWidth ?? 100.0,
      previewHeight: dbData.previewHeight ?? 100.0,
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
      metadata: Value(metadata.isNotEmpty ? jsonEncode(metadata) : null),
      previewPositionX: Value(previewPositionX),
      previewPositionY: Value(previewPositionY),
      previewWidth: Value(previewWidth),
      previewHeight: Value(previewHeight),
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

  factory ClipModel.fromJson(Map<String, dynamic> json) {
    // Safely parse ClipType
    ClipType clipType;
    final typeString = json['type'] as String?;
    if (typeString != null) {
      clipType = ClipType.values.firstWhere(
        (e) => e.toString().split('.').last == typeString,
        orElse: () => ClipType.video,
      );
    } else {
      clipType = ClipType.video;
    }

    // Safely parse metadata
    Map<String, dynamic> parsedMetadata = {};
    if (json['metadata'] is Map<String, dynamic>) {
      parsedMetadata = json['metadata'] as Map<String, dynamic>;
    } else if (json['metadata'] is String) {
      // Attempt to decode if it's a JSON string
      try {
        parsedMetadata = jsonDecode(json['metadata'] as String) as Map<String, dynamic>;
      } catch (e) {
        // Log error or handle as appropriate if metadata string is malformed
        print('Error decoding metadata from JSON string: $e');
      }
    }
 
    // Extract preview transform properties from metadata if they exist
    final double posX = (parsedMetadata['preview_position_x'] as num?)?.toDouble() ?? 0.0;
    final double posY = (parsedMetadata['preview_position_y'] as num?)?.toDouble() ?? 0.0;
    final double width = (parsedMetadata['preview_width'] as num?)?.toDouble() ?? 100.0; // Default if not in metadata
    final double height = (parsedMetadata['preview_height'] as num?)?.toDouble() ?? 100.0; // Default if not in metadata

    return ClipModel(
      databaseId: json['databaseId'] as int?,
      trackId: json['trackId'] as int,
      name: json['name'] as String,
      type: clipType,
      sourcePath: json['sourcePath'] as String,
      sourceDurationMs: json['sourceDurationMs'] as int,
      startTimeInSourceMs: json['startTimeInSourceMs'] as int,
      endTimeInSourceMs: json['endTimeInSourceMs'] as int,
      startTimeOnTrackMs: json['startTimeOnTrackMs'] as int,
      endTimeOnTrackMs: json['endTimeOnTrackMs'] as int,
      effects: const [],
      metadata: parsedMetadata,
      previewPositionX: posX,
      previewPositionY: posY,
      previewWidth: width,
      previewHeight: height,
    );
  }
}
