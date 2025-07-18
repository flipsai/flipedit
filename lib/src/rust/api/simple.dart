// This file is automatically generated, so please do not edit it.
// @generated by `flutter_rust_bridge`@ 2.7.0.

// ignore_for_file: invalid_use_of_internal_member, unused_import, unnecessary_import

import '../common/types.dart';
import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

// These types are ignored because they are not used by any `pub` functions: `ACTIVE_VIDEOS`
// These function are ignored because they are on traits that is not defined in current crate (put an empty `#[frb]` on it to unignore): `deref`, `initialize`

String greet({required String name}) =>
    RustLib.instance.api.crateApiSimpleGreet(name: name);

/// Create a new video texture using irondash for zero-copy rendering
PlatformInt64 createVideoTexture({
  required int width,
  required int height,
  required PlatformInt64 engineHandle,
}) => RustLib.instance.api.crateApiSimpleCreateVideoTexture(
  width: width,
  height: height,
  engineHandle: engineHandle,
);

/// Update video frame data for all irondash textures
bool updateVideoFrame({required FrameData frameData}) =>
    RustLib.instance.api.crateApiSimpleUpdateVideoFrame(frameData: frameData);

/// Get the number of active irondash textures
BigInt getTextureCount() =>
    RustLib.instance.api.crateApiSimpleGetTextureCount();

/// Play a basic MP4 video and return irondash texture id
PlatformInt64 playBasicVideo({
  required String filePath,
  required PlatformInt64 engineHandle,
}) => RustLib.instance.api.crateApiSimplePlayBasicVideo(
  filePath: filePath,
  engineHandle: engineHandle,
);

PlatformInt64 playDualVideo({
  required String filePathLeft,
  required String filePathRight,
  required PlatformInt64 engineHandle,
}) => RustLib.instance.api.crateApiSimplePlayDualVideo(
  filePathLeft: filePathLeft,
  filePathRight: filePathRight,
  engineHandle: engineHandle,
);

/// Create and load a direct pipeline timeline player with timeline data (GStreamer-only implementation)
Future<(GesTimelinePlayer, PlatformInt64)> createGesTimelinePlayer({
  required TimelineData timelineData,
  required PlatformInt64 engineHandle,
}) => RustLib.instance.api.crateApiSimpleCreateGesTimelinePlayer(
  timelineData: timelineData,
  engineHandle: engineHandle,
);

/// Get video duration in milliseconds using GStreamer
/// This is a reliable way to get video duration without depending on fallback estimations
BigInt getVideoDurationMs({required String filePath}) =>
    RustLib.instance.api.crateApiSimpleGetVideoDurationMs(filePath: filePath);

// Rust type: RustOpaqueMoi<flutter_rust_bridge::for_generated::RustAutoOpaqueInner<GESTimelinePlayer>>
abstract class GesTimelinePlayer implements RustOpaqueInterface {
  /// Create texture for this player
  Future<PlatformInt64> createTexture({required PlatformInt64 engineHandle});

  @override
  Future<void> dispose();

  int? getDurationMs();

  FrameData? getLatestFrame();

  BigInt getLatestTextureId();

  int getPositionMs();

  TextureFrame? getTextureFrame();

  bool isPlaying();

  bool isSeekable();

  Future<void> loadTimeline({required TimelineData timelineData});

  factory GesTimelinePlayer() =>
      RustLib.instance.api.crateApiSimpleGesTimelinePlayerNew();

  Future<void> pause();

  Future<void> play();

  Future<void> seekToPosition({required int positionMs});

  Stream<FrameData> setupFrameStream();

  Stream<(double, BigInt)> setupPositionStream();

  Stream<int> setupSeekCompletionStream();

  Future<void> stop();

  /// Update a specific clip's transform properties without reloading the entire timeline
  Future<void> updateClipTransform({
    required int clipId,
    required double previewPositionX,
    required double previewPositionY,
    required double previewWidth,
    required double previewHeight,
  });

  /// Update position from GStreamer pipeline - call this regularly for smooth playhead updates
  void updatePosition();
}

// Rust type: RustOpaqueMoi<flutter_rust_bridge::for_generated::RustAutoOpaqueInner<TimelinePlayer>>
abstract class TimelinePlayer implements RustOpaqueInterface {
  @override
  Future<void> dispose();

  FrameData? getLatestFrame();

  /// Get the latest texture ID for GPU-based rendering
  BigInt getLatestTextureId();

  int getPositionMs();

  /// Get texture frame data for GPU-based rendering
  TextureFrame? getTextureFrame();

  bool isPlaying();

  Future<void> loadTimeline({required TimelineData timelineData});

  factory TimelinePlayer() =>
      RustLib.instance.api.crateApiSimpleTimelinePlayerNew();

  Future<void> pause();

  Future<void> play();

  Future<void> setPositionMs({required int positionMs});

  Future<void> stop();

  /// Test method to verify timeline logic - set position and check if frame should be shown
  bool testTimelineLogic({required int positionMs});
}

// Rust type: RustOpaqueMoi<flutter_rust_bridge::for_generated::RustAutoOpaqueInner<VideoPlayer>>
abstract class VideoPlayer implements RustOpaqueInterface {
  @override
  Future<void> dispose();

  /// Extract frame at specific position for preview without seeking main pipeline
  Future<void> extractFrameAtPosition({required double seconds});

  /// Get current position and frame - Flutter can call this periodically
  (double, BigInt) getCurrentPositionAndFrame();

  double getDurationSeconds();

  double getFrameRate();

  FrameData? getLatestFrame();

  /// Get the latest texture ID for GPU-based rendering
  BigInt getLatestTextureId();

  double getPositionSeconds();

  /// Get texture frame data for GPU-based rendering
  TextureFrame? getTextureFrame();

  BigInt getTotalFrames();

  (int, int) getVideoDimensions();

  bool hasAudio();

  bool isPlaying();

  bool isSeekable();

  Future<void> loadVideo({required String filePath});

  factory VideoPlayer() => RustLib.instance.api.crateApiSimpleVideoPlayerNew();

  static VideoPlayer newPlayer() =>
      RustLib.instance.api.crateApiSimpleVideoPlayerNewPlayer();

  Future<void> pause();

  Future<void> play();

  /// Seek to final position with pause/resume control - used when releasing slider
  Future<double> seekAndPauseControl({
    required double seconds,
    required bool wasPlayingBefore,
  });

  Future<void> seekToFrame({required BigInt frameNumber});

  Stream<FrameData> setupFrameStream();

  Stream<(double, BigInt)> setupPositionStream();

  Future<void> stop();

  /// Force synchronization between pipeline state and internal state
  Future<bool> syncPlayingState();

  Future<void> testPipeline({required String filePath});
}
