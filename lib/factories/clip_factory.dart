import 'package:flipedit/factories/effect_factory.dart';
import 'package:flipedit/models/components/base_clip.dart';
import 'package:flipedit/models/decorators/clips/modified_clip_decorator.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/interfaces/clip_interface.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Factory for creating clips and clip decorators
class ClipFactory {
  /// Create a base clip with the specified parameters
  static BaseClip createBaseClip({
    required String id,
    required String name,
    required ClipType type,
    required String filePath,
    required int startFrame,
    required int durationFrames,
    List<IEffect> effects = const [],
    Map<String, dynamic> metadata = const {},
  }) {
    return BaseClip(
      id: id,
      name: name,
      type: type,
      filePath: filePath,
      startFrame: startFrame,
      durationFrames: durationFrames,
      effects: effects,
      metadata: metadata,
    );
  }
  
  /// Create a modified clip by decorating a base clip
  static IClip createModifiedClip({
    required IClip baseClip,
    int? customDurationFrames,
    double speedFactor = 1.0,
    List<IEffect> additionalEffects = const [],
  }) {
    return ModifiedClipDecorator(
      decoratedClip: baseClip,
      customDurationFrames: customDurationFrames,
      speedFactor: speedFactor,
      additionalEffects: additionalEffects,
    );
  }
  
  /// Create a speed-modified clip
  static IClip createSpeedModifiedClip({
    required IClip baseClip,
    required double speedFactor,
  }) {
    // Calculate new duration based on speed
    final newDuration = (baseClip.durationFrames / speedFactor).round();
    
    return ModifiedClipDecorator(
      decoratedClip: baseClip,
      customDurationFrames: newDuration,
      speedFactor: speedFactor,
    );
  }
  
  /// Create a clip from JSON data
  static IClip createClipFromJson(Map<String, dynamic> json) {
    // Parse effects first
    final List<IEffect> effects = [];
    if (json.containsKey('effects') && json['effects'] is List) {
      for (final effectJson in json['effects']) {
        try {
          final effect = EffectFactory.createEffectFromJson(effectJson);
          effects.add(effect);
        } catch (e) {
          print('Error parsing effect: $e');
          // Continue with other effects
        }
      }
    }
    
    // Create the base clip
    final baseClip = BaseClip(
      id: json['id'],
      name: json['name'],
      type: ClipType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => ClipType.video,
      ),
      filePath: json['filePath'],
      startFrame: json['startFrame'],
      durationFrames: json['durationFrames'],
      effects: effects,
      metadata: json['metadata'] ?? {},
    );
    
    // Check if this is a decorated clip
    if (json.containsKey('decorator')) {
      final decoratorData = json['decorator'] as Map<String, dynamic>;
      final decoratorType = decoratorData['type'];
      
      // Apply the appropriate decorator based on type
      switch (decoratorType) {
        case 'ModifiedClipDecorator':
          // Parse additional effects
          final List<IEffect> additionalEffects = [];
          if (decoratorData.containsKey('additionalEffects') && 
              decoratorData['additionalEffects'] is List) {
            for (final effectJson in decoratorData['additionalEffects']) {
              try {
                final effect = EffectFactory.createEffectFromJson(effectJson);
                additionalEffects.add(effect);
              } catch (e) {
                print('Error parsing additional effect: $e');
                // Continue with other effects
              }
            }
          }
          
          return ModifiedClipDecorator(
            decoratedClip: baseClip,
            customDurationFrames: decoratorData['customDurationFrames'],
            speedFactor: (decoratorData['speedFactor'] as num?)?.toDouble() ?? 1.0,
            additionalEffects: additionalEffects,
          );
        // Add cases for other decorator types here
        default:
          return baseClip;
      }
    }
    
    return baseClip;
  }
  
  /// Create a clip with effects applied
  static IClip createClipWithEffects({
    required String id,
    required String name,
    required ClipType type,
    required String filePath,
    required int startFrame,
    required int durationFrames,
    required List<IEffect> effects,
    Map<String, dynamic> metadata = const {},
  }) {
    return BaseClip(
      id: id,
      name: name,
      type: type,
      filePath: filePath,
      startFrame: startFrame,
      durationFrames: durationFrames,
      effects: effects,
      metadata: metadata,
    );
  }
  
  /// Create a cropped clip
  static IClip createCroppedClip({
    required IClip baseClip,
    required int newStartFrame,
    required int newDurationFrames,
  }) {
    // Create a modified clip with adjusted timings
    return ModifiedClipDecorator(
      decoratedClip: baseClip,
      customDurationFrames: newDurationFrames,
      // Adjust effects to match the new timing
      additionalEffects: [], // We keep the original effects but could add crop-specific ones
    );
  }
}
