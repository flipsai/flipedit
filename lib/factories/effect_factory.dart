import 'package:flipedit/models/components/base_effect.dart';
import 'package:flipedit/models/decorators/effects/filter_effect_decorator.dart';
import 'package:flipedit/models/enums/effect_type.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Factory for creating effects and effect decorators
class EffectFactory {
  /// Create a base effect with the specified parameters
  static BaseEffect createBaseEffect({
    required String id,
    required String name,
    required EffectType type,
    Map<String, dynamic> parameters = const {},
    required int startFrame,
    required int durationFrames,
  }) {
    return BaseEffect(
      id: id,
      name: name,
      type: type,
      parameters: parameters,
      startFrame: startFrame,
      durationFrames: durationFrames,
    );
  }
  
  /// Create a filter effect by decorating a base effect
  static IEffect createFilterEffect({
    required String id,
    required String name,
    Map<String, dynamic> parameters = const {},
    required int startFrame,
    required int durationFrames,
    double intensity = 1.0,
    Map<String, double> colorAdjustments = const {
      'brightness': 0.0,
      'contrast': 0.0,
      'saturation': 0.0,
      'hue': 0.0,
    },
  }) {
    // Create the base effect
    final baseEffect = createBaseEffect(
      id: id,
      name: name,
      type: EffectType.filter,
      parameters: parameters,
      startFrame: startFrame,
      durationFrames: durationFrames,
    );
    
    // Decorate with filter functionality
    return FilterEffectDecorator(
      decoratedEffect: baseEffect,
      intensity: intensity,
      colorAdjustments: colorAdjustments,
    );
  }
  
  /// Create an effect from JSON data
  static IEffect createEffectFromJson(Map<String, dynamic> json) {
    // First create a base effect
    final baseEffect = BaseEffect.fromJson(json);
    
    // Check if this is a decorated effect
    if (json.containsKey('decorator')) {
      final decoratorData = json['decorator'] as Map<String, dynamic>;
      final decoratorType = decoratorData['type'];
      
      // Apply the appropriate decorator based on type
      switch (decoratorType) {
        case 'FilterEffectDecorator':
          return FilterEffectDecorator(
            decoratedEffect: baseEffect,
            intensity: decoratorData['intensity'] ?? 1.0,
            colorAdjustments: _parseColorAdjustments(decoratorData['colorAdjustments']),
          );
        // Add cases for other decorator types here
        default:
          return baseEffect;
      }
    }
    
    return baseEffect;
  }
  
  /// Helper to parse color adjustments from JSON
  static Map<String, double> _parseColorAdjustments(dynamic data) {
    if (data == null) {
      return {
        'brightness': 0.0,
        'contrast': 0.0,
        'saturation': 0.0,
        'hue': 0.0,
      };
    }
    
    final Map<String, dynamic> rawData = data as Map<String, dynamic>;
    return rawData.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }
}
