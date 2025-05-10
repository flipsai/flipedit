import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class TimelineLogicService {
  int calculateFramePosition(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    final adjustedPosition = pixelPosition + scrollOffset;
    final frameWidth = zoom > 0.01 ? (5.0 * zoom) : (5.0 * 0.01);
    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  int frameToMs(int framePosition) {
    return ClipModel.framesToMs(framePosition);
  }

  int calculateMsPositionFromPixels(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    final framePosition = calculateFramePosition(
      pixelPosition,
      scrollOffset,
      zoom,
    );
    return frameToMs(framePosition);
  }

  double calculatePixelOffsetForFrame(int frame, double zoom) {
    final safeZoom = zoom.clamp(0.01, 5.0);
    final frameWidth = 5.0 * safeZoom;
    return frame * frameWidth;
  }

  double calculateScrollOffsetForFrame(int frame, double zoom) {
    return calculatePixelOffsetForFrame(frame, zoom);
  }

  Map<String, dynamic> prepareClipPlacement({
    required List<ClipModel> clips,
    int? clipId,
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int sourceDurationMs,
    required int startTimeOnTrackMs,
    required int endTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) {
    if (endTimeOnTrackMs <= startTimeOnTrackMs) {
      print(
        "Warning: prepareClipPlacement received non-positive track duration. Adjusting.",
      );
      startTimeOnTrackMs = startTimeOnTrackMs;
      endTimeOnTrackMs = startTimeOnTrackMs + 1;
    }
    final newStart = startTimeOnTrackMs;
    final newEnd = endTimeOnTrackMs.clamp(
      startTimeOnTrackMs + 1,
      endTimeOnTrackMs,
    );

    final clampedStartTimeInSourceMs = startTimeInSourceMs.clamp(
      0,
      sourceDurationMs,
    );
    final clampedEndTimeInSourceMs = endTimeInSourceMs.clamp(
      clampedStartTimeInSourceMs,
      sourceDurationMs,
    );

    final neighbors =
        clips
            .where(
              (c) =>
                  c.trackId == trackId &&
                  (clipId == null || c.databaseId != clipId),
            )
            .toList()
          ..sort(
            (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
          );

    List<ClipModel> updatedClips = List<ClipModel>.from(clips);
    List<Map<String, dynamic>> clipUpdates = [];
    List<int> clipsToRemove = [];

    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.endTimeOnTrackMs;

      final bool overlaps = ns < newEnd && ne > newStart;

      if (overlaps) {
        if (ns >= newStart && ne <= newEnd) {
          updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
          if (neighbor.databaseId != null &&
              !clipsToRemove.contains(neighbor.databaseId!)) {
            clipsToRemove.add(neighbor.databaseId!);
          }
        } else if (ns < newStart && ne > newStart) {
          final newNeighborTrackEnd = newStart;
          final trackTrimAmount = ne - newNeighborTrackEnd;
          final newNeighborSourceEnd = (neighbor.endTimeInSourceMs -
                  trackTrimAmount)
              .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

          final updated = neighbor.copyWith(
            endTimeOnTrackMs: newNeighborTrackEnd,
            endTimeInSourceMs: newNeighborSourceEnd,
          );
          final updateIndex = updatedClips.indexWhere(
            (c) => c.databaseId == neighbor.databaseId,
          );
          if (updateIndex != -1) updatedClips[updateIndex] = updated;

          if (neighbor.databaseId != null) {
            final existingUpdateIndex = clipUpdates.indexWhere(
              (u) => u['id'] == neighbor.databaseId!,
            );
            if (existingUpdateIndex == -1) {
              clipUpdates.add({
                'id': neighbor.databaseId!,
                'fields': {
                  'endTimeOnTrackMs': newNeighborTrackEnd,
                  'endTimeInSourceMs': newNeighborSourceEnd,
                },
              });
            } else {
              clipUpdates[existingUpdateIndex]['fields']['endTimeOnTrackMs'] =
                  newNeighborTrackEnd;
              clipUpdates[existingUpdateIndex]['fields']['endTimeInSourceMs'] =
                  newNeighborSourceEnd;
            }
          }
        } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
          updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
          if (neighbor.databaseId != null &&
              !clipsToRemove.contains(neighbor.databaseId!)) {
            clipsToRemove.add(neighbor.databaseId!);
          }
        } else if (ns < newStart && ne > newEnd) {
          final newNeighborTrackEnd = newStart;
          final trackTrimAmount = ne - newNeighborTrackEnd;
          final newNeighborSourceEnd = (neighbor.endTimeInSourceMs -
                  trackTrimAmount)
              .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

          final updated = neighbor.copyWith(
            endTimeOnTrackMs: newNeighborTrackEnd,
            endTimeInSourceMs: newNeighborSourceEnd,
          );
          final updateIndex = updatedClips.indexWhere(
            (c) => c.databaseId == neighbor.databaseId,
          );
          if (updateIndex != -1) updatedClips[updateIndex] = updated;

          if (neighbor.databaseId != null) {
            final existingUpdateIndex = clipUpdates.indexWhere(
              (u) => u['id'] == neighbor.databaseId!,
            );
            if (existingUpdateIndex == -1) {
              clipUpdates.add({
                'id': neighbor.databaseId!,
                'fields': {
                  'endTimeOnTrackMs': newNeighborTrackEnd,
                  'endTimeInSourceMs': newNeighborSourceEnd,
                },
              });
            } else {
              clipUpdates[existingUpdateIndex]['fields']['endTimeOnTrackMs'] =
                  newNeighborTrackEnd;
              clipUpdates[existingUpdateIndex]['fields']['endTimeInSourceMs'] =
                  newNeighborSourceEnd;
            }
          }
        }
      } // End of if (overlaps)
    } // End neighbor loop

    Map<String, dynamic> newClipData = {
      'trackId': trackId,
      'type': type,
      'sourcePath': sourcePath,
      'sourceDurationMs': sourceDurationMs,
      'startTimeOnTrackMs': newStart,
      'endTimeOnTrackMs': newEnd,
      'startTimeInSourceMs': clampedStartTimeInSourceMs,
      'endTimeInSourceMs': clampedEndTimeInSourceMs,
    };

    if (clipId != null) {
      final updateIndex = updatedClips.indexWhere(
        (c) => c.databaseId == clipId,
      );
      if (updateIndex != -1) {
        updatedClips[updateIndex] = updatedClips[updateIndex].copyWith(
          trackId: trackId,
          startTimeOnTrackMs: newStart,
          endTimeOnTrackMs: newEnd,
          startTimeInSourceMs: clampedStartTimeInSourceMs,
          endTimeInSourceMs: clampedEndTimeInSourceMs,
        );
      } else {
        print(
          "Warning: Clip ID $clipId provided for update but not found in list. Adding as new.",
        );
        ClipModel newClipModel = ClipModel(
          databaseId: clipId,
          trackId: trackId,
          name: '',
          type: type,
          sourcePath: sourcePath,
          sourceDurationMs: sourceDurationMs,
          startTimeInSourceMs: clampedStartTimeInSourceMs,
          endTimeInSourceMs: clampedEndTimeInSourceMs,
          startTimeOnTrackMs: newStart,
          endTimeOnTrackMs: newEnd,
          effects: [],
          metadata: {},
        );
        updatedClips.add(newClipModel);
      }
    } else {
      ClipModel newClipModel = ClipModel(
        databaseId: null,
        trackId: trackId,
        name: '',
        type: type,
        sourcePath: sourcePath,
        sourceDurationMs: sourceDurationMs,
        startTimeInSourceMs: clampedStartTimeInSourceMs,
        endTimeInSourceMs: clampedEndTimeInSourceMs,
        startTimeOnTrackMs: newStart,
        endTimeOnTrackMs: newEnd,
        effects: [],
        metadata: {},
      );
      updatedClips.add(newClipModel);
    }

    final finalClipIdsToRemove = clipsToRemove.toSet();
    updatedClips.removeWhere(
      (clip) =>
          clip.databaseId != null &&
          finalClipIdsToRemove.contains(clip.databaseId),
    );

    return {
      'success': true,
      'newClipData': newClipData,
      'clipId': clipId,
      'updatedClips': updatedClips,
      'clipUpdates':
          clipUpdates
              .where((update) => !finalClipIdsToRemove.contains(update['id']))
              .toList(),
      'clipsToRemove': clipsToRemove,
    };
  }

  List<ClipModel> getOverlappingClips(
    List<ClipModel> clips,
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) {
    return clips.where((clip) {
      if (clip.trackId != trackId) return false;
      if (excludeClipId != null && clip.databaseId == excludeClipId) {
        return false;
      }

      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.endTimeOnTrackMs;

      return clipStart < endMs && clipEnd > startMs;
    }).toList();
  }

  List<ClipModel> getPreviewClipsForDrag({
    required List<ClipModel> clips,
    required int clipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    ClipModel? draggedClip;
    try {
      draggedClip = clips.firstWhere((c) => c.databaseId == clipId);
    } catch (e) {
      print("Error: Dragged clip $clipId not found in getPreviewClipsForDrag.");
      return clips; // Return original list if dragged clip isn't found
    }

    final draggedDurationOnTrack = draggedClip.durationOnTrackMs;
    final targetEndTimeOnTrackMs =
        targetStartTimeOnTrackMs + draggedDurationOnTrack;

    final placementResult = prepareClipPlacement(
      clips: clips,
      clipId: clipId,
      trackId: targetTrackId,
      type: draggedClip.type,
      sourcePath: draggedClip.sourcePath,
      sourceDurationMs: draggedClip.sourceDurationMs,
      startTimeOnTrackMs: targetStartTimeOnTrackMs,
      endTimeOnTrackMs: targetEndTimeOnTrackMs,
      startTimeInSourceMs: draggedClip.startTimeInSourceMs,
      endTimeInSourceMs: draggedClip.endTimeInSourceMs,
    );

    if (placementResult['success'] == true) {
      return List<ClipModel>.from(placementResult['updatedClips']);
    } else {
      print("Warning: prepareClipPlacement failed during preview generation.");
      final others = clips.where((c) => c.databaseId != clipId).toList();
      final movedPreview = draggedClip.copyWith(
        trackId: targetTrackId,
        startTimeOnTrackMs: targetStartTimeOnTrackMs,
        endTimeOnTrackMs: targetEndTimeOnTrackMs,
      );
      others.add(movedPreview);
      others.sort(
        (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
      );
      return others;
    }
  }
}
