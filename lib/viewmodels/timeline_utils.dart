import 'dart:async';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/database/project_database.dart' as project_db;
import 'package:flutter/foundation.dart';

const double kDefaultFrameRate = 30.0;

/// Simple debounce utility
void Function() debounce(VoidCallback func, Duration delay) {
  Timer? debounceTimer;
  return () {
    debounceTimer?.cancel();
    debounceTimer = Timer(delay, func);
  };
}

/// Helper method to convert project database clip to ClipModel
ClipModel clipFromProjectDb(project_db.Clip dbData) {
  return ClipModel(
    databaseId: dbData.id,
    trackId: dbData.trackId,
    name: dbData.name,
    type: ClipType.values.firstWhere(
      (e) => e.toString().split('.').last == dbData.type,
      orElse: () => ClipType.video,
    ),
    sourcePath: dbData.sourcePath,
    startTimeInSourceMs: dbData.startTimeInSourceMs,
    endTimeInSourceMs: dbData.endTimeInSourceMs,
    startTimeOnTrackMs: dbData.startTimeOnTrackMs,
  );
}
