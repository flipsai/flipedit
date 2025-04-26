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
  // TODO: Need a way to get the actual source duration here.
  // Maybe fetch ProjectAsset metadata based on sourcePath?
  // Or pass it from the caller if available.
  // For now, estimating it based on existing times or using a default.
  // This estimation is crude and should be improved.
  int estimatedSourceDuration = dbData.sourceDurationMs ?? (dbData.endTimeInSourceMs - dbData.startTimeInSourceMs);
  if (estimatedSourceDuration < 0) estimatedSourceDuration = 0; // Ensure non-negative

  // Use the ClipModel factory constructor that handles DB data and potential missing fields
  return ClipModel.fromDbData(dbData, sourceDurationMs: estimatedSourceDuration);
}
