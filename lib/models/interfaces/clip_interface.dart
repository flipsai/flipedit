import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Base interface for all clips in the timeline
abstract class IClip {
  /// Unique identifier for the clip
  String get id;

  /// Display name of the clip
  String get name;

  /// Type of clip (video, audio, etc.)
  ClipType get type;

  /// Path to the source media file
  String get filePath;

  /// Start frame in the timeline
  int get startFrame;

  /// Duration of the clip in frames
  int get durationFrames;

  /// Effects applied to this clip
  List<IEffect> get effects;

  /// Additional metadata for the clip
  Map<String, dynamic> get metadata;

  /// Get a frame at the specified position
  /// This should handle all applied effects in the correct order
  Future<Map<String, dynamic>> getProcessedFrame(int framePosition);

  /// Convert clip to JSON for serialization
  Map<String, dynamic> toJson();
}
