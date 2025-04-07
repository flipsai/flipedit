import 'package:flipedit/models/enums/effect_type.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Abstract decorator for effects
/// This class implements the Decorator Pattern, wrapping an IEffect
/// and allowing layered modifications
abstract class EffectDecorator implements IEffect {
  /// The effect being decorated
  final IEffect decoratedEffect;
  
  /// Create a decorator wrapping the provided effect
  EffectDecorator(this.decoratedEffect);
  
  // Forward all base properties to the decorated effect
  @override
  String get id => decoratedEffect.id;
  
  @override
  String get name => decoratedEffect.name;
  
  @override
  EffectType get type => decoratedEffect.type;
  
  @override
  Map<String, dynamic> get parameters => decoratedEffect.parameters;
  
  @override
  int get startFrame => decoratedEffect.startFrame;
  
  @override
  int get durationFrames => decoratedEffect.durationFrames;
  
  // The process method should be overridden by concrete decorators
  @override
  Map<String, dynamic> process(Map<String, dynamic> frameData) {
    // Apply the wrapped effect's processing first
    final processedData = decoratedEffect.process(frameData);
    // Then apply this decorator's additional processing (in subclasses)
    return applyDecoration(processedData);
  }
  
  /// Apply this decorator's specific processing
  /// Concrete decorators must implement this method
  Map<String, dynamic> applyDecoration(Map<String, dynamic> frameData);
  
  @override
  Map<String, dynamic> toJson() {
    // Include both the decorated effect and this decorator's specific data
    final json = decoratedEffect.toJson();
    json['decorator'] = {
      'type': runtimeType.toString(),
      // Concrete decorators can add specific parameters here
    };
    return json;
  }
}
