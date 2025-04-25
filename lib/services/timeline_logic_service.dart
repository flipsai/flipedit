import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
// Removed unused imports: project_database_service, watch_it, constants
// Removed Drift import as Value() is not used in copyWith

class TimelineLogicService {
  /// Calculates exact frame position from pixel coordinates on the timeline
  int calculateFramePosition(
    double pixelPosition,
    double scrollOffset,
    double zoom,
  ) {
    final adjustedPosition = pixelPosition + scrollOffset;
    // Prevent division by zero or negative zoom
    final frameWidth = zoom > 0.01 ? (5.0 * zoom) : (5.0 * 0.01);
    final framePosition = (adjustedPosition / frameWidth).floor();
    return framePosition < 0 ? 0 : framePosition;
  }

  /// Converts a frame position to milliseconds
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
    required List<ClipModel> clips, // Pass the current list of clips
    int? clipId, // If updating an existing clip
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int sourceDurationMs,    // Added: The duration of the source media
    required int startTimeOnTrackMs,
    required int endTimeOnTrackMs,    // Added: The desired end time on the track
    required int startTimeInSourceMs, // The desired start time within the source
    required int endTimeInSourceMs,   // The desired end time within the source (will be clamped)
  }) {
    // Ensure track duration is positive
    if (endTimeOnTrackMs <= startTimeOnTrackMs) {
      // Maybe return an error or adjust? For now, let's log and proceed cautiously
      // or potentially adjust endTimeOnTrackMs = startTimeOnTrackMs + 1;
       print("Warning: prepareClipPlacement received non-positive track duration.");
       // Let's enforce minimum 1ms duration for safety
       final adjustedEndTimeOnTrackMs = startTimeOnTrackMs + 1;
       final newStart = startTimeOnTrackMs;
       final newEnd = adjustedEndTimeOnTrackMs;
    } else {
      final newStart = startTimeOnTrackMs;
      final newEnd = endTimeOnTrackMs;
    }
    final newStart = startTimeOnTrackMs;
    final newEnd = endTimeOnTrackMs.clamp(startTimeOnTrackMs + 1, endTimeOnTrackMs); // Ensure end is after start


    // Clamp the provided source times
    final clampedStartTimeInSourceMs = startTimeInSourceMs.clamp(0, sourceDurationMs);
    final clampedEndTimeInSourceMs = endTimeInSourceMs.clamp(clampedStartTimeInSourceMs, sourceDurationMs);


    // 1. Gather and sort neighbors on the target track
    final neighbors =
        clips
            .where(
              (c) =>
                  c.trackId == trackId &&
                  (clipId == null || c.databaseId != clipId), // Exclude the clip being placed if it's an update
            )
            .toList()
          ..sort(
            (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
          );

    // 2. Prepare neighbor modifications
    List<ClipModel> updatedClips = List<ClipModel>.from(clips); // Start with a copy of all clips
    List<Map<String, dynamic>> clipUpdates = []; // DB updates needed for neighbors
    List<int> clipsToRemove = []; // DB deletions needed for neighbors

    for (final neighbor in neighbors) {
      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.endTimeOnTrackMs; // Use explicit track end time

      if (ne <= newStart || ns >= newEnd) continue; // No overlap

      // --- Overlap Logic ---
      if (ns >= newStart && ne <= newEnd) { // Neighbor is fully covered by the new clip
        updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
        if (neighbor.databaseId != null) clipsToRemove.add(neighbor.databaseId!);
      } else if (ns < newStart && ne > newStart && ne <= newEnd) {
        // Neighbor overlaps new clip's start (trim neighbor's end)
        final newNeighborTrackEnd = newStart;
        final trackTrimAmount = ne - newNeighborTrackEnd;
        // Ensure source end doesn't go before source start
        final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
            .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

        final updated = neighbor.copyWith(
          endTimeOnTrackMs: newNeighborTrackEnd, // Use direct param
          endTimeInSourceMs: newNeighborSourceEnd, // Use direct param
        );
        final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
        if(updateIndex != -1) updatedClips[updateIndex] = updated;

        if (neighbor.databaseId != null) {
          clipUpdates.add({
            'id': neighbor.databaseId!,
            'fields': {
              'endTimeOnTrackMs': newNeighborTrackEnd,
              'endTimeInSourceMs': newNeighborSourceEnd,
              },
          });
        }
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
         // Neighbor overlaps new clip's end (trim neighbor's start)
        final newNeighborTrackStart = newEnd;
        final trackTrimAmount = newNeighborTrackStart - ns;
         // Ensure source start doesn't go past source end
        final newNeighborSourceStart = (neighbor.startTimeInSourceMs + trackTrimAmount)
            .clamp(0, neighbor.endTimeInSourceMs);

        final updated = neighbor.copyWith(
          startTimeOnTrackMs: newNeighborTrackStart, // Use direct param
          startTimeInSourceMs: newNeighborSourceStart, // Use direct param
        );
         final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
        if(updateIndex != -1) updatedClips[updateIndex] = updated;

        if (neighbor.databaseId != null) {
          clipUpdates.add({
            'id': neighbor.databaseId!,
            'fields': {
              'startTimeOnTrackMs': newNeighborTrackStart,
              'startTimeInSourceMs': newNeighborSourceStart,
            },
          });
        }
      } else if (ns < newStart && ne > newEnd) {
        // New clip is fully inside neighbor: Trim neighbor's end (simpler than splitting)
         final newNeighborTrackEnd = newStart;
        final trackTrimAmount = ne - newNeighborTrackEnd;
        final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
            .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

        final updated = neighbor.copyWith(
          endTimeOnTrackMs: newNeighborTrackEnd, // Use direct param
          endTimeInSourceMs: newNeighborSourceEnd, // Use direct param
        );
         final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
        if(updateIndex != -1) updatedClips[updateIndex] = updated;

        if (neighbor.databaseId != null) {
          clipUpdates.add({
            'id': neighbor.databaseId!,
            'fields': {
              'endTimeOnTrackMs': newNeighborTrackEnd,
              'endTimeInSourceMs': newNeighborSourceEnd,
            },
          });
        }
      }
    } // End neighbor loop

    // 3. Prepare final clip data for the placed/updated clip
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

    // 4. Update the clip in the optimistic list (updatedClips)
    if (clipId != null) {
      final idx = updatedClips.indexWhere((c) => c.databaseId == clipId);
      if (idx != -1) {
        // Update existing clip in the list
        updatedClips[idx] = updatedClips[idx].copyWith(
          trackId: trackId,
          startTimeOnTrackMs: newStart,
          endTimeOnTrackMs: newEnd,
          startTimeInSourceMs: clampedStartTimeInSourceMs,
          endTimeInSourceMs: clampedEndTimeInSourceMs,
          // sourceDurationMs is assumed not to change during placement
        );
      } else {
        // This case should ideally not happen if clipId is provided, but handle defensively
        print("Warning: Clip ID $clipId provided for update but not found in list.");
         // Add it as a new clip if it wasn't found? Or throw error?
         // For now, let's add it as if it were new.
          ClipModel newClipModel = ClipModel(
              databaseId: clipId, // Use provided ID
              trackId: trackId, name: '', type: type, sourcePath: sourcePath,
              sourceDurationMs: sourceDurationMs,
              startTimeInSourceMs: clampedStartTimeInSourceMs, endTimeInSourceMs: clampedEndTimeInSourceMs,
              startTimeOnTrackMs: newStart, endTimeOnTrackMs: newEnd,
              effects: [], metadata: {},
          );
          updatedClips.add(newClipModel);
      }
    } else {
      // Add new clip to the list
      ClipModel newClipModel = ClipModel(
        databaseId: null, // Will be assigned upon DB insert
        trackId: trackId, name: '', type: type, sourcePath: sourcePath,
        sourceDurationMs: sourceDurationMs,
        startTimeInSourceMs: clampedStartTimeInSourceMs, endTimeInSourceMs: clampedEndTimeInSourceMs,
        startTimeOnTrackMs: newStart, endTimeOnTrackMs: newEnd,
        effects: [], metadata: {},
      );
      updatedClips.add(newClipModel);
    }

    // 5. Return results
    return {
      'success': true,
      'newClipData': newClipData, // Contains final track & (clamped) source times for the placed clip
      'clipId': clipId, // Pass back original ID if provided
      'updatedClips': updatedClips, // Optimistic UI update list (includes placed clip + trimmed neighbors)
      'clipUpdates': clipUpdates, // DB updates needed for neighbors
      'clipsToRemove': clipsToRemove, // DB deletions needed for neighbors
    };
  } // End of prepareClipPlacement

  /// Returns all clips on the same track that overlap with [startMs, endMs). Optionally excludes a clip by ID.
  List<ClipModel> getOverlappingClips(
    List<ClipModel> clips, // Pass the current list of clips
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) {
    return clips.where((clip) {
      if (clip.trackId != trackId) return false;
      if (excludeClipId != null && clip.databaseId == excludeClipId) return false;

      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.endTimeOnTrackMs; // Use explicit end time on track

      // Overlap if ranges intersect: (StartA < EndB) and (EndA > StartB)
      return clipStart < endMs && clipEnd > startMs;
    }).toList();
  } // End of getOverlappingClips

  /// Returns a preview of the timeline clips as if a clip were dragged to a new position, applying trimming logic in-memory only.
  List<ClipModel> getPreviewClipsForDrag({
    required List<ClipModel> clips, // Pass the current list of clips
    required int clipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) {
    final original = clips;
    final dragged = original.firstWhere((c) => c.databaseId == clipId, orElse: () => throw Exception("Dragged clip not found"));

    // Use the dragged clip's track duration for the preview
    final draggedDurationOnTrack = dragged.durationOnTrackMs;
    int newStart = targetStartTimeOnTrackMs;
    int newEnd = targetStartTimeOnTrackMs + draggedDurationOnTrack;

    // Ensure preview duration is positive
    if (newEnd <= newStart) newEnd = newStart +1;


    // Remove the dragged clip from the list to check overlaps with others on the target track
    final others = original.where((c) => c.databaseId != clipId).toList();
    List<ClipModel> preview = []; // Start with empty list

    for (final neighbor in others) {
       // Only consider neighbors on the target track for overlap checks
      if (neighbor.trackId != targetTrackId) {
        preview.add(neighbor); // Keep clips on other tracks as they are
        continue;
      }

      final ns = neighbor.startTimeOnTrackMs;
      final ne = neighbor.endTimeOnTrackMs; // Use explicit end time

      // --- Apply the same trimming logic as prepareClipPlacement for preview ---
      if (ne <= newStart || ns >= newEnd) { // No overlap
        preview.add(neighbor);
      } else if (ns >= newStart && ne <= newEnd) { // Fully covered: remove neighbor from preview
        continue;
      } else if (ns < newStart && ne > newStart && ne <= newEnd) { // Overlap on right: trim neighbor's end
         final newNeighborTrackEnd = newStart;
        final trackTrimAmount = ne - newNeighborTrackEnd;
        final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
            .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);
        preview.add(neighbor.copyWith(
             endTimeOnTrackMs: newNeighborTrackEnd,
             endTimeInSourceMs: newNeighborSourceEnd,
        ));
      } else if (ns >= newStart && ns < newEnd && ne > newEnd) { // Overlap on left: trim neighbor's start
        final newNeighborTrackStart = newEnd;
        final trackTrimAmount = newNeighborTrackStart - ns;
        final newNeighborSourceStart = (neighbor.startTimeInSourceMs + trackTrimAmount)
            .clamp(0, neighbor.endTimeInSourceMs);
         preview.add(neighbor.copyWith(
             startTimeOnTrackMs: newNeighborTrackStart,
             startTimeInSourceMs: newNeighborSourceStart,
         ));
      } else if (ns < newStart && ne > newEnd) { // Dragged clip is fully inside neighbor: trim neighbor's end
        final newNeighborTrackEnd = newStart;
        final trackTrimAmount = ne - newNeighborTrackEnd;
        final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
            .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);
        preview.add(neighbor.copyWith(
             endTimeOnTrackMs: newNeighborTrackEnd,
             endTimeInSourceMs: newNeighborSourceEnd,
        ));
      }
    } // End neighbor loop

    // Add the dragged clip at the preview position
    preview.add(
      dragged.copyWith(
        trackId: targetTrackId,
        startTimeOnTrackMs: newStart,
        endTimeOnTrackMs: newEnd, // Show the preview end time
        // Source times remain unchanged for a move preview
      ),
    );

    // Sort the final preview list by start time
    preview.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );
    return preview;
  } // End of getPreviewClipsForDrag

} // End of TimelineLogicService class