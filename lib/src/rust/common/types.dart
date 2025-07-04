// This file is automatically generated, so please do not edit it.
// @generated by `flutter_rust_bridge`@ 2.7.0.

// ignore_for_file: invalid_use_of_internal_member, unused_import, unnecessary_import

import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

class FrameData {
  final Uint8List data;
  final int width;
  final int height;

  const FrameData({
    required this.data,
    required this.width,
    required this.height,
  });

  @override
  int get hashCode => data.hashCode ^ width.hashCode ^ height.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrameData &&
          runtimeType == other.runtimeType &&
          data == other.data &&
          width == other.width &&
          height == other.height;
}

class TimelineClip {
  final int? id;
  final int trackId;
  final String sourcePath;
  final int startTimeOnTrackMs;
  final int endTimeOnTrackMs;
  final int startTimeInSourceMs;
  final int endTimeInSourceMs;

  const TimelineClip({
    this.id,
    required this.trackId,
    required this.sourcePath,
    required this.startTimeOnTrackMs,
    required this.endTimeOnTrackMs,
    required this.startTimeInSourceMs,
    required this.endTimeInSourceMs,
  });

  @override
  int get hashCode =>
      id.hashCode ^
      trackId.hashCode ^
      sourcePath.hashCode ^
      startTimeOnTrackMs.hashCode ^
      endTimeOnTrackMs.hashCode ^
      startTimeInSourceMs.hashCode ^
      endTimeInSourceMs.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineClip &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          trackId == other.trackId &&
          sourcePath == other.sourcePath &&
          startTimeOnTrackMs == other.startTimeOnTrackMs &&
          endTimeOnTrackMs == other.endTimeOnTrackMs &&
          startTimeInSourceMs == other.startTimeInSourceMs &&
          endTimeInSourceMs == other.endTimeInSourceMs;
}

class TimelineData {
  final List<TimelineTrack> tracks;

  const TimelineData({required this.tracks});

  @override
  int get hashCode => tracks.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineData &&
          runtimeType == other.runtimeType &&
          tracks == other.tracks;
}

class TimelineTrack {
  final int id;
  final String name;
  final List<TimelineClip> clips;

  const TimelineTrack({
    required this.id,
    required this.name,
    required this.clips,
  });

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ clips.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineTrack &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          clips == other.clips;
}
