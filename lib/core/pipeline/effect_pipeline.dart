import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Manages the application of multiple effects in a processing pipeline
class EffectPipeline {
  /// Effects in the pipeline, in order of application
  final List<IEffect> effects;
  
  EffectPipeline({
    this.effects = const [],
  });
  
  /// Process frame data through all effects in the pipeline
  Map<String, dynamic> processFrame(Map<String, dynamic> frameData, int framePosition) {
    Map<String, dynamic> processedData = Map<String, dynamic>.from(frameData);
    
    // Apply each active effect in sequence
    for (final effect in effects) {
      if (isEffectActiveAtFrame(effect, framePosition)) {
        processedData = effect.process(processedData);
      }
    }
    
    return processedData;
  }
  
  /// Check if an effect should be applied at the given frame position
  bool isEffectActiveAtFrame(IEffect effect, int framePosition) {
    return effect.startFrame <= framePosition && 
           effect.startFrame + effect.durationFrames > framePosition;
  }
  
  /// Add an effect to the pipeline
  EffectPipeline addEffect(IEffect effect) {
    final newEffects = List<IEffect>.from(effects)..add(effect);
    return EffectPipeline(effects: newEffects);
  }
  
  /// Remove an effect from the pipeline
  EffectPipeline removeEffect(String effectId) {
    final newEffects = effects.where((effect) => effect.id != effectId).toList();
    return EffectPipeline(effects: newEffects);
  }
  
  /// Create a pipeline with reordered effects
  EffectPipeline reorderEffects(List<String> effectIds) {
    // Create a map of effect IDs to effects
    final effectMap = {for (var effect in effects) effect.id: effect};
    
    // Create a new list based on the provided order
    final newEffects = effectIds
        .where((id) => effectMap.containsKey(id))
        .map((id) => effectMap[id]!)
        .toList();
    
    return EffectPipeline(effects: newEffects);
  }
}
