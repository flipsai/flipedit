enum EffectType {
  backgroundRemoval,
  objectTracking,
  colorCorrection,
  transform,
  filter,
  transition,
  text;
  
  // Return the display name of the effect type
  String get displayName {
    switch (this) {
      case EffectType.backgroundRemoval:
        return 'Background Removal';
      case EffectType.objectTracking:
        return 'Object Tracking';
      case EffectType.colorCorrection:
        return 'Color Correction';
      case EffectType.transform:
        return 'Transform';
      case EffectType.filter:
        return 'Filter';
      case EffectType.transition:
        return 'Transition';
      case EffectType.text:
        return 'Text';
    }
  }
}
