import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class TimelineViewModel {
  final ValueNotifier<List<Clip>> clipsNotifier = ValueNotifier<List<Clip>>([]);
  List<Clip> get clips => List.unmodifiable(clipsNotifier.value);

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    if (zoomNotifier.value == value || value < 0.1 || value > 5.0) return;
    zoomNotifier.value = value;
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    if (currentFrameNotifier.value == value ||
        value < 0 ||
        value > _totalFrames)
      return;
    currentFrameNotifier.value = value;
  }

  int _totalFrames = 0;
  int get totalFrames => _totalFrames;
  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;
  set isPlaying(bool value) {
    if (isPlayingNotifier.value == value) return;
    isPlayingNotifier.value = value;

    if (isPlayingNotifier.value) {
      _startPlayback();
    }
  }

  // Add a clip to the timeline
  void addClip(Clip clip) {
    final newClips = List<Clip>.from(clipsNotifier.value)..add(clip);
    clipsNotifier.value = newClips;
    _recalculateTotalFrames();
  }

  // Calculate frame position from a drag and drop operation
  int calculateFramePositionFromDrop(
    double localPositionX,
    double scrollOffsetX,
    double zoom,
  ) {
    // Convert screen position to timeline frame
    // Take into account both the local position and scroll offset
    final adjustedPosition = localPositionX + scrollOffsetX;
    final frameWidth = 5.0 * zoom; // 5.0 is the base frame width

    // Calculate frame number, ensuring it's not negative
    // Use floor instead of truncating to ensure proper rounding
    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  // Add a clip at a specific drop position, considering zoom and scroll
  void addClipAtPosition(
    Clip clip, {
    double? localPositionX,
    double? scrollOffsetX,
  }) {
    // Use current frame if no position is specified
    int targetFrame = currentFrame;

    // If position data is provided, calculate the exact frame position
    if (localPositionX != null && scrollOffsetX != null) {
      targetFrame = calculateFramePositionFromDrop(
        localPositionX,
        scrollOffsetX,
        zoom,
      );
    }

    // Create a new clip with the calculated frame position
    final newClip = clip.copyWith(startFrame: targetFrame);
    addClip(newClip);
  }

  // Remove a clip from the timeline
  void removeClip(String clipId) {
    if (clipId.isEmpty) return;

    final initialLength = clipsNotifier.value.length;
    final newClips =
        clipsNotifier.value.where((clip) => clip.id != clipId).toList();

    // Only notify if something was actually removed
    if (newClips.length != initialLength) {
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();
    }
  }

  // Update an existing clip
  void updateClip(String clipId, Clip updatedClip) {
    if (clipId.isEmpty) return;

    final index = clipsNotifier.value.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      final newClips = List<Clip>.from(clipsNotifier.value);
      newClips[index] = updatedClip;
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();
    }
  }

  // Move clip to a different position on the timeline
  void moveClip(String clipId, int newStartFrame) {
    if (clipId.isEmpty || newStartFrame < 0) return;

    final index = clipsNotifier.value.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      final clip = clipsNotifier.value[index];
      if (clip.startFrame == newStartFrame) return; // No change needed

      final updatedClip = clip.copyWith(startFrame: newStartFrame);
      final newClips = List<Clip>.from(clipsNotifier.value);
      newClips[index] = updatedClip;
      clipsNotifier.value = newClips;
      _recalculateTotalFrames();
    }
  }

  // Set the current playhead position
  void seekTo(int frame) {
    currentFrame = frame; // Uses the setter with validation
  }

  // Toggle playback state
  void togglePlayback() {
    isPlaying = !isPlaying; // Uses the setter
  }

  // Set the zoom level
  void setZoom(double newZoom) {
    zoom = newZoom; // Uses the setter with validation
  }

  // Private helpers
  void _recalculateTotalFrames() {
    if (clipsNotifier.value.isEmpty) {
      _totalFrames = 0;
      totalFramesNotifier.value = 0;
    } else {
      _totalFrames = clipsNotifier.value
          .map((clip) => clip.startFrame + clip.durationFrames)
          .reduce((a, b) => a > b ? a : b);
      totalFramesNotifier.value = _totalFrames;
    }
  }

  void _startPlayback() {
    // In a real implementation, this would set up a timer to advance frames
    // and coordinate with a player service
  }
}
