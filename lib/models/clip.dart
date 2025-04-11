import 'package:flipedit/models/effect.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class Clip {
  final String id;
  final String name;
  final ClipType type;
  final String filePath;
  final int startFrame;
  final int durationFrames;
  final int trackIndex;
  final List<Effect> effects;
  final Map<String, dynamic> metadata;

  Clip({
    required this.id,
    required this.name,
    required this.type,
    required this.filePath,
    required this.startFrame,
    required this.durationFrames,
    required this.trackIndex,
    this.effects = const [],
    this.metadata = const {},
  });

  Clip copyWith({
    String? id,
    String? name,
    ClipType? type,
    String? filePath,
    int? startFrame,
    int? durationFrames,
    int? trackIndex,
    List<Effect>? effects,
    Map<String, dynamic>? metadata,
  }) {
    return Clip(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      startFrame: startFrame ?? this.startFrame,
      durationFrames: durationFrames ?? this.durationFrames,
      trackIndex: trackIndex ?? this.trackIndex,
      effects: effects ?? this.effects,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'filePath': filePath,
      'startFrame': startFrame,
      'durationFrames': durationFrames,
      'trackIndex': trackIndex,
      'effects': effects.map((effect) => effect.toJson()).toList(),
      'metadata': metadata,
    };
  }

  factory Clip.fromJson(Map<String, dynamic> json) {
    return Clip(
      id: json['id'],
      name: json['name'],
      type: ClipType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => ClipType.video,
      ),
      filePath: json['filePath'],
      startFrame: json['startFrame'],
      durationFrames: json['durationFrames'],
      trackIndex: json['trackIndex'] ?? 0,
      effects:
          (json['effects'] as List?)
              ?.map((effectJson) => Effect.fromJson(effectJson))
              ?.toList() ??
          [],
      metadata: json['metadata'] ?? {},
    );
  }
}
