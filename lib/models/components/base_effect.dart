import 'package:flipedit/models/enums/effect_type.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Base implementation of the IEffect interface
class BaseEffect implements IEffect {
  @override
  final String id;
  
  @override
  final String name;
  
  @override
  final EffectType type;
  
  @override
  final Map<String, dynamic> parameters;
  
  @override
  final int startFrame;
  
  @override
  final int durationFrames;
  
  BaseEffect({
    required this.id,
    required this.name,
    required this.type,
    this.parameters = const {},
    required this.startFrame,
    required this.durationFrames,
  });
  
  @override
  Map<String, dynamic> process(Map<String, dynamic> frameData) {
    // Base implementation simply returns the frame unchanged
    // Concrete effects will override this method
    return frameData;
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'parameters': parameters,
      'startFrame': startFrame,
      'durationFrames': durationFrames,
    };
  }
  
  factory BaseEffect.fromJson(Map<String, dynamic> json) {
    return BaseEffect(
      id: json['id'],
      name: json['name'],
      type: EffectType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => EffectType.filter,
      ),
      parameters: json['parameters'] ?? {},
      startFrame: json['startFrame'],
      durationFrames: json['durationFrames'],
    );
  }
  
  BaseEffect copyWith({
    String? id,
    String? name,
    EffectType? type,
    Map<String, dynamic>? parameters,
    int? startFrame,
    int? durationFrames,
  }) {
    return BaseEffect(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
      startFrame: startFrame ?? this.startFrame,
      durationFrames: durationFrames ?? this.durationFrames,
    );
  }
}
