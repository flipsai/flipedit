import 'package:flipedit/models/clip.dart';

class Project {
  final String id;
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime lastModifiedAt;
  final List<Clip> clips;
  final Map<String, dynamic> settings;
  
  Project({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
    required this.lastModifiedAt,
    this.clips = const [],
    this.settings = const {},
  });
  
  Project copyWith({
    String? id,
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    List<Clip>? clips,
    Map<String, dynamic>? settings,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      clips: clips ?? this.clips,
      settings: settings ?? this.settings,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'createdAt': createdAt.toIso8601String(),
      'lastModifiedAt': lastModifiedAt.toIso8601String(),
      'clips': clips.map((clip) => clip.toJson()).toList(),
      'settings': settings,
    };
  }
  
  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      path: json['path'],
      createdAt: DateTime.parse(json['createdAt']),
      lastModifiedAt: DateTime.parse(json['lastModifiedAt']),
      clips: (json['clips'] as List).map((clipJson) => Clip.fromJson(clipJson)).toList(),
      settings: json['settings'] ?? {},
    );
  }
}
