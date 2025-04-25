import 'package:flipedit/services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/utils/constants.dart'; // Assuming kDefaultFrameRate might be needed or is implicitly used by ClipModel methods

class TimelineLogicService {
  /// Calculates exact frame position from pixel coordinates on the timeline
  int calculateFramePosition(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    final adjustedPosition = pixelPosition + scrollOffset;
    final frameWidth = 5.0 * zoom; // 5px per frame at 1.0 zoom

    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  /// Converts a frame position to milliseconds (based on standard 30fps)
  int frameToMs(int framePosition) {
    return ClipModel.framesToMs(framePosition);
  }

  /// Calculates millisecond position directly from pixel coordinates
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

  /// Calculates placement for a clip on a track, handling overlaps with neighbors
  /// Returns placement information without performing database operations
  Map<String, dynamic> prepareClipPlacement({
    required List<ClipModel> clips, // Added clips parameter
    int? clipId, // If updating an existing clip
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) {
    final newClipDuration = endTimeInSourceMs - startTimeInSourceMs;
    int newStart = startTimeOnTrackMs;
    int newEnd = startTimeOnTrackMs + newClipDuration;

    // 1. Gather and sort neighbors
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

    // 2. Prepare neighbor modifications (no database operations here)
    List<ClipModel> updatedClips = List<ClipModel>.from(clips);
    List<Map<String, dynamic>> clipUpdates = [];
    List<int> clipsToRemove = [];

    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;

      if (ne <= newStart || ns >= newEnd) continue; // No overlap

      if (ns >= newStart && ne <= newEnd) {
        // Fully covered: mark for removal
        updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
        clipsToRemove.add(neighbor.databaseId!);
      } else if (ns < newStart && ne > newStart && ne <= newEnd) {
        // Overlap on right: trim neighbor's end to the intersection
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] = updated;

        clipUpdates.add({
          'id': neighbor.databaseId!,
          'fields': {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        });
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
        // Overlap on left: trim neighbor's start to the intersection
        final updated = neighbor.copyWith(
          startTimeInSourceMs: neighbor.startTimeInSourceMs + (newEnd - ns),
          startTimeOnTrackMs: newEnd,
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] = updated;

        clipUpdates.add({
          'id': neighbor.databaseId!,
          'fields': {
            'startTimeInSourceMs': neighbor.startTimeInSourceMs + (newEnd - ns),
            'startTimeOnTrackMs': newEnd,
          },
        });
      } else if (ns < newStart && ne > newEnd) {
        // Moved clip is fully inside neighbor: trim neighbor's end to newStart (left part remains)
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] = updated;

        clipUpdates.add({
          'id': neighbor.databaseId!,
          'fields': {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        });
      }
      // NEW CASE: If the left neighbor's end overlaps the new start, trim its end to newStart
      else if (ne > newStart && ne <= newEnd && ns < newStart) {
        final updated = neighbor.copyWith(
          endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
        );
        updatedClips[updatedClips.indexWhere(
              (c) => c.databaseId == neighbor.databaseId,
            )] = updated;

        clipUpdates.add({
          'id': neighbor.databaseId!,
          'fields': {'endTimeInSourceMs': neighbor.startTimeInSourceMs + (newStart - ns)},
        });
      }
    }

    // 3. Clamp new clip to available space
    int clampLeft = 0;
    int clampRight = 1 << 30; // Using bit shift for a large integer
    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;
      if (ne <= newStart) {
        if (ne > clampLeft) clampLeft = ne;
      }
      if (ns >= newEnd) {
        if (ns < clampRight) clampRight = ns;
      }
    }
    newStart = newStart.clamp(clampLeft, clampRight - 1);
    newEnd = (newStart + newClipDuration).clamp(clampLeft + 1, clampRight);

    if (newEnd <= newStart) {
      return {'success': false};
    }

    // 4. Prepare new clip data
    Map<String, dynamic> newClipData = {
      'trackId': trackId,
      'type': type,
      'sourcePath': sourcePath,
      'startTimeOnTrackMs': newStart,
      'startTimeInSourceMs': startTimeInSourceMs,
      'endTimeInSourceMs': startTimeInSourceMs + (newEnd - newStart),
    };

    // For updating existing clip
    if (clipId != null) {
      final idx = updatedClips.indexWhere((c) => c.databaseId == clipId);
      if (idx != -1) {
        updatedClips[idx] = updatedClips[idx].copyWith(
          trackId: trackId,
          startTimeOnTrackMs: newStart,
          startTimeInSourceMs: startTimeInSourceMs,
          endTimeInSourceMs: startTimeInSourceMs + (newEnd - newStart),
        );
      }
    } else {
      // For new clip, prepare model for optimistic UI update
      ClipModel newClipModel = ClipModel(
        databaseId: -1, // Temporary ID, will be replaced with actual DB ID
        trackId: trackId,
        name: '',
        type: type,
        sourcePath: sourcePath,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: startTimeInSourceMs + (newEnd - newStart),
        startTimeOnTrackMs: newStart,
        effects: [],
        metadata: {},
      );
      updatedClips.add(newClipModel);
    }

    return {
      'success': true,
      'newClipData': newClipData,
      'clipId': clipId,
      'updatedClips': updatedClips,
      'clipUpdates': clipUpdates,
      'clipsToRemove': clipsToRemove,
    };
  }

  /// Returns all clips on the same track that overlap with [startMs, endMs). Optionally excludes a clip by ID.
  List<ClipModel> getOverlappingClips(
    List<ClipModel> clips, // Added clips parameter
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) {
    return clips.where((clip) {
      if (clip.trackId != trackId) return false;
      if (excludeClipId != null && clip.databaseId == excludeClipId)
        return false;
      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.startTimeOnTrackMs + clip.durationMs;
      // Overlap if ranges intersect
      return clipStart < endMs && clipEnd > startMs;
    }).toList();
  }

  /// Returns a preview of the timeline clips as if a clip were dragged to a new position, applying trimming logic in-memory only.
  List<ClipModel> getPreviewClipsForDrag({
    required List<ClipModel> clips, // Added clips parameter
    required int clipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    final original = clips;
    final dragged = original.firstWhere((c) => c.databaseId == clipId);
    final newClipDuration = dragged.durationMs;
    int newStart = targetStartTimeOnTrackMs;
    int newEnd = targetStartTimeOnTrackMs + newClipDuration;
    // Remove the dragged clip from the list
    final others = original.where((c) => c.databaseId != clipId).toList();
    List<ClipModel> preview = [];
    for (final neighbor in others) {
      if (neighbor.trackId != targetTrackId) {
        preview.add(neighbor);
        continue;
      }
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.startTimeOnTrackMs + neighbor.durationMs;
      if (ne <= newStart || ns >= newEnd) {
        preview.add(neighbor);
      } else if (ns >= newStart && ne <= newEnd) {
        // Fully covered: remove
        continue;
      } else if (ns < newStart && ne > newStart && ne <= newEnd) {
        // Overlap on right: trim neighbor's end
        preview.add(
          neighbor.copyWith(
            endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
          ),
        );
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
        // Overlap on left: trim neighbor's start
        preview.add(
          neighbor.copyWith(
            startTimeInSourceMs: neighbor.startTimeInSourceMs + (newEnd - ns),
            startTimeOnTrackMs: newEnd,
          ),
        );
      } else if (ns < newStart && ne > newEnd) {
        // Dragged clip is fully inside neighbor: only left part remains (trim at newStart)
        preview.add(
          neighbor.copyWith(
            endTimeInSourceMs: neighbor.startTimeInSourceMs + (newStart - ns),
          ),
        );
      }
    }
    // Add the dragged clip at the preview position
    preview.add(
      dragged.copyWith(
        trackId: targetTrackId,
        startTimeOnTrackMs: newStart,
        // Optionally update startTimeInSourceMs/endTimeInSourceMs if you want to preview source trim
      ),
    );
    // Sort by start time
    preview.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );
    return preview;
  }
}