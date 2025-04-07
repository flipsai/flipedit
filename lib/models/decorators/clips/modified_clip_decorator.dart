import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/interfaces/clip_interface.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// A decorator for clips that adds modifications without changing the base clip
class ModifiedClipDecorator implements IClip {
  /// The clip being decorated
  final IClip decoratedClip;
  
  /// Custom override for clip duration
  final int? customDurationFrames;
  
  /// Speed factor (1.0 = normal speed, 0.5 = half speed, 2.0 = double speed)
  final double speedFactor;
  
  /// Additional effects applied by this decorator
  final List<IEffect> additionalEffects;
  
  ModifiedClipDecorator({
    required this.decoratedClip,
    this.customDurationFrames,
    this.speedFactor = 1.0,
    this.additionalEffects = const [],
  });
  
  // Forward base properties to decorated clip
  @override
  String get id => decoratedClip.id;
  
  @override
  String get name => decoratedClip.name;
  
  @override
  ClipType get type => decoratedClip.type;
  
  @override
  String get filePath => decoratedClip.filePath;
  
  @override
  int get startFrame => decoratedClip.startFrame;
  
  // Override duration if custom duration is specified
  @override
  int get durationFrames => customDurationFrames ?? decoratedClip.durationFrames;
  
  // Combine base effects with additional effects from this decorator
  @override
  List<IEffect> get effects => [
    ...decoratedClip.effects,
    ...additionalEffects,
  ];
  
  @override
  Map<String, dynamic> get metadata => decoratedClip.metadata;
  
  @override
  Future<Map<String, dynamic>> getProcessedFrame(int framePosition) async {
    // Calculate source frame based on speed factor
    final adjustedPosition = (framePosition * speedFactor).round();
    
    // Get the frame from the decorated clip
    final frameData = await decoratedClip.getProcessedFrame(adjustedPosition);
    
    // Apply additional effects from this decorator
    Map<String, dynamic> processedData = Map<String, dynamic>.from(frameData);
    for (final effect in additionalEffects) {
      if (isEffectActiveAtFrame(effect, framePosition)) {
        processedData = effect.process(processedData);
      }
    }
    
    return processedData;
  }
  
  /// Check if the effect should be applied at the current frame
  bool isEffectActiveAtFrame(IEffect effect, int framePosition) {
    final relativePosition = framePosition - startFrame;
    return effect.startFrame <= relativePosition && 
           effect.startFrame + effect.durationFrames > relativePosition;
  }
  
  @override
  Map<String, dynamic> toJson() {
    final json = decoratedClip.toJson();
    json['decorator'] = {
      'type': 'ModifiedClipDecorator',
      'customDurationFrames': customDurationFrames,
      'speedFactor': speedFactor,
      'additionalEffects': additionalEffects.map((e) => e.toJson()).toList(),
    };
    return json;
  }
}
