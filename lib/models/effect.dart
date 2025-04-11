import 'package:flipedit/models/enums/effect_type.dart';

class Effect {
  final String id;
  final String name;
  final EffectType type;
  final Map<String, dynamic> parameters;
  final List<Effect> childEffects; // For composable effects
  final int startFrame; // Relative to the clip's start
  final int durationFrames;
  
  Effect({
    required this.id,
    required this.name,
    required this.type,
    this.parameters = const {},
    this.childEffects = const [],
    required this.startFrame,
    required this.durationFrames,
  });
  
  Effect copyWith({
    String? id,
    String? name,
    EffectType? type,
    Map<String, dynamic>? parameters,
    List<Effect>? childEffects,
    int? startFrame,
    int? durationFrames,
  }) {
    return Effect(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      parameters: parameters ?? this.parameters,
      childEffects: childEffects ?? this.childEffects,
      startFrame: startFrame ?? this.startFrame,
      durationFrames: durationFrames ?? this.durationFrames,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'parameters': parameters,
      'childEffects': childEffects.map((effect) => effect.toJson()).toList(),
      'startFrame': startFrame,
      'durationFrames': durationFrames,
    };
  }
  
  factory Effect.fromJson(Map<String, dynamic> json) {
    return Effect(
      id: json['id'],
      name: json['name'],
      type: EffectType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => EffectType.filter,
      ),
      parameters: json['parameters'] ?? {},
      childEffects: (json['childEffects'] as List?)
          ?.map((effectJson) => Effect.fromJson(effectJson))
          .toList() ?? [],
      startFrame: json['startFrame'],
      durationFrames: json['durationFrames'],
    );
  }
}
