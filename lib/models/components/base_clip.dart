import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/interfaces/clip_interface.dart';
import 'package:flipedit/models/interfaces/effect_interface.dart';

/// Base implementation of the IClip interface
class BaseClip implements IClip {
  @override
  final String id;
  
  @override
  final String name;
  
  @override
  final ClipType type;
  
  @override
  final String filePath;
  
  @override
  final int startFrame;
  
  @override
  final int durationFrames;
  
  @override
  final List<IEffect> effects;
  
  @override
  final Map<String, dynamic> metadata;
  
  BaseClip({
    required this.id,
    required this.name,
    required this.type,
    required this.filePath,
    required this.startFrame,
    required this.durationFrames,
    this.effects = const [],
    this.metadata = const {},
  });
  
  @override
  Future<Map<String, dynamic>> getProcessedFrame(int framePosition) async {
    // This would fetch the raw frame data from the source file
    Map<String, dynamic> frameData = await _loadRawFrame(framePosition);
    
    // Apply all effects in sequence
    for (final effect in _getActiveEffectsForFrame(framePosition)) {
      frameData = effect.process(frameData);
    }
    
    return frameData;
  }
  
  // Helper to load the raw frame from the source
  Future<Map<String, dynamic>> _loadRawFrame(int framePosition) async {
    // Implementation would load frame data from file
    // For now we return a placeholder
    return {
      'pixelData': [], // This would be actual pixel data
      'timestamp': framePosition / 30.0, // Assuming 30fps
      'metadata': {}
    };
  }
  
  // Helper to filter effects that apply at the current frame
  List<IEffect> _getActiveEffectsForFrame(int framePosition) {
    final relativePosition = framePosition - startFrame;
    return effects.where((effect) => 
      effect.startFrame <= relativePosition && 
      effect.startFrame + effect.durationFrames > relativePosition
    ).toList();
  }
  
  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'filePath': filePath,
      'startFrame': startFrame,
      'durationFrames': durationFrames,
      'effects': effects.map((effect) => effect.toJson()).toList(),
      'metadata': metadata,
    };
  }
  
  factory BaseClip.fromJson(Map<String, dynamic> json) {
    // Note: This would need to be updated to work with IEffect
    return BaseClip(
      id: json['id'],
      name: json['name'],
      type: ClipType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => ClipType.video,
      ),
      filePath: json['filePath'],
      startFrame: json['startFrame'],
      durationFrames: json['durationFrames'],
      // This would need a factory to create the proper IEffect implementations
      effects: [], 
      metadata: json['metadata'] ?? {},
    );
  }
  
  BaseClip copyWith({
    String? id,
    String? name,
    ClipType? type,
    String? filePath,
    int? startFrame,
    int? durationFrames,
    List<IEffect>? effects,
    Map<String, dynamic>? metadata,
  }) {
    return BaseClip(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      startFrame: startFrame ?? this.startFrame,
      durationFrames: durationFrames ?? this.durationFrames,
      effects: effects ?? this.effects,
      metadata: metadata ?? this.metadata,
    );
  }
}
