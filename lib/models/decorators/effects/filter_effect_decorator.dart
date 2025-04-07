import 'package:flipedit/models/decorators/abstract_decorator.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// A decorator that applies a filter effect to an underlying effect
class FilterEffectDecorator extends EffectDecorator {
  /// Filter intensity from 0.0 to 1.0
  final double intensity;
  
  /// Filter color modification
  final Map<String, double> colorAdjustments;
  
  FilterEffectDecorator({
    required IEffect decoratedEffect,
    this.intensity = 1.0,
    this.colorAdjustments = const {
      'brightness': 0.0,
      'contrast': 0.0,
      'saturation': 0.0,
      'hue': 0.0,
    },
  }) : super(decoratedEffect);
  
  @override
  Map<String, dynamic> applyDecoration(Map<String, dynamic> frameData) {
    // In a real implementation, this would apply color adjustments to the frame
    // This is a placeholder implementation
    final result = Map<String, dynamic>.from(frameData);
    
    // Add the filter parameters to the frame metadata for downstream processing
    if (!result.containsKey('filters')) {
      result['filters'] = [];
    }
    
    result['filters'].add({
      'type': 'color_adjustment',
      'intensity': intensity,
      'adjustments': colorAdjustments,
    });
    
    return result;
  }
  
  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['decorator']['intensity'] = intensity;
    json['decorator']['colorAdjustments'] = colorAdjustments;
    return json;
  }
}
