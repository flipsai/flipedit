import 'package:flipedit/models/enums/clip_type.dart';

class ProjectAsset {
  final int? databaseId;
  final String name;
  final ClipType type;
  final String sourcePath;
  final int durationMs; // Store duration in milliseconds

  ProjectAsset({
    this.databaseId,
    required this.name,
    required this.type,
    required this.sourcePath,
    required this.durationMs,
  });
}
