import 'package:flipedit/models/enums/effect_type.dart';

/// Base interface for all effects in the editing pipeline
abstract class IEffect {
  /// Unique identifier for the effect
  String get id;
  
  /// Display name of the effect
  String get name;
  
  /// Type of effect (filter, transform, etc.)
  EffectType get type;
  
  /// Parameters that control the effect's behavior
  Map<String, dynamic> get parameters;
  
  /// Frame where the effect starts (relative to clip start)
  int get startFrame;
  
  /// Duration of the effect in frames
  int get durationFrames;
  
  /// Process frame data using this effect
  /// This is where the actual effect logic would be implemented
  Map<String, dynamic> process(Map<String, dynamic> frameData);
  
  /// Convert effect to JSON for serialization
  Map<String, dynamic> toJson();
}
