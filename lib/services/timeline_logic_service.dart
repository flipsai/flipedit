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
       print("Warning: prepareClipPlacement received non-positive track duration. Adjusting.");
       startTimeOnTrackMs = startTimeOnTrackMs; // Keep original start
       endTimeOnTrackMs = startTimeOnTrackMs + 1; // Set end 1ms after start
    }
    // Clamp end time to be at least 1ms after start
    final newStart = startTimeOnTrackMs;
    final newEnd = endTimeOnTrackMs.clamp(startTimeOnTrackMs + 1, endTimeOnTrackMs);


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

      // Check for any overlap: (StartA < EndB) and (EndA > StartB)
      final bool overlaps = ns < newEnd && ne > newStart;

      if (overlaps) {
          // --- Original Trim Logic ---
          if (ns >= newStart && ne <= newEnd) { // Neighbor is fully covered
            updatedClips.removeWhere((c) => c.databaseId == neighbor.databaseId);
             if (neighbor.databaseId != null && !clipsToRemove.contains(neighbor.databaseId!)) {
               clipsToRemove.add(neighbor.databaseId!);
            }
          } else if (ns < newStart && ne > newStart && ne <= newEnd) {
            // Neighbor overlaps new clip's start (trim neighbor's end)
            final newNeighborTrackEnd = newStart;
            final trackTrimAmount = ne - newNeighborTrackEnd;
            final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
                .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

            final updated = neighbor.copyWith(
              endTimeOnTrackMs: newNeighborTrackEnd,
              endTimeInSourceMs: newNeighborSourceEnd,
            );
            final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
            if(updateIndex != -1) updatedClips[updateIndex] = updated;

            if (neighbor.databaseId != null) {
              // Add or update existing update instruction
              final existingUpdateIndex = clipUpdates.indexWhere((u) => u['id'] == neighbor.databaseId!);
              if (existingUpdateIndex == -1) {
                clipUpdates.add({
                  'id': neighbor.databaseId!,
                  'fields': {
                    'endTimeOnTrackMs': newNeighborTrackEnd,
                    'endTimeInSourceMs': newNeighborSourceEnd,
                  },
                });
              } else {
                 // If already marked for start trim, merge the updates
                 clipUpdates[existingUpdateIndex]['fields']['endTimeOnTrackMs'] = newNeighborTrackEnd;
                 clipUpdates[existingUpdateIndex]['fields']['endTimeInSourceMs'] = newNeighborSourceEnd;
              }
            }
          } else if (ns >= newStart && ns < newEnd && ne > newEnd) {
            // Neighbor overlaps new clip's end (trim neighbor's start)
            final newNeighborTrackStart = newEnd;
            final trackTrimAmount = newNeighborTrackStart - ns;
            final newNeighborSourceStart = (neighbor.startTimeInSourceMs + trackTrimAmount)
                .clamp(0, neighbor.endTimeInSourceMs);

            final updated = neighbor.copyWith(
              startTimeOnTrackMs: newNeighborTrackStart,
              startTimeInSourceMs: newNeighborSourceStart,
            );
            final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
            if(updateIndex != -1) updatedClips[updateIndex] = updated;

            if (neighbor.databaseId != null) {
               // Add or update existing update instruction
               final existingUpdateIndex = clipUpdates.indexWhere((u) => u['id'] == neighbor.databaseId!);
              if (existingUpdateIndex == -1) {
                  clipUpdates.add({
                    'id': neighbor.databaseId!,
                    'fields': {
                      'startTimeOnTrackMs': newNeighborTrackStart,
                      'startTimeInSourceMs': newNeighborSourceStart,
                    },
                  });
               } else {
                 // If already marked for end trim, merge the updates
                 clipUpdates[existingUpdateIndex]['fields']['startTimeOnTrackMs'] = newNeighborTrackStart;
                 clipUpdates[existingUpdateIndex]['fields']['startTimeInSourceMs'] = newNeighborSourceStart;
               }
            }
          } else if (ns < newStart && ne > newEnd) {
            // New clip is fully inside neighbor: Trim neighbor's end (like first overlap case).
            // TODO: Implement splitting the neighbor into two clips for better accuracy.
            final newNeighborTrackEnd = newStart;
            final trackTrimAmount = ne - newNeighborTrackEnd;
            final newNeighborSourceEnd = (neighbor.endTimeInSourceMs - trackTrimAmount)
                .clamp(neighbor.startTimeInSourceMs, neighbor.sourceDurationMs);

            final updated = neighbor.copyWith(
              endTimeOnTrackMs: newNeighborTrackEnd,
              endTimeInSourceMs: newNeighborSourceEnd,
            );
            final updateIndex = updatedClips.indexWhere((c) => c.databaseId == neighbor.databaseId);
            if(updateIndex != -1) updatedClips[updateIndex] = updated;

            if (neighbor.databaseId != null) {
               // Add or update existing update instruction
               final existingUpdateIndex = clipUpdates.indexWhere((u) => u['id'] == neighbor.databaseId!);
               if (existingUpdateIndex == -1) {
                  clipUpdates.add({
                    'id': neighbor.databaseId!,
                    'fields': {
                      'endTimeOnTrackMs': newNeighborTrackEnd,
                      'endTimeInSourceMs': newNeighborSourceEnd,
                    },
                  });
                } else {
                  // If already marked for start trim, merge the updates
                  clipUpdates[existingUpdateIndex]['fields']['endTimeOnTrackMs'] = newNeighborTrackEnd;
                  clipUpdates[existingUpdateIndex]['fields']['endTimeInSourceMs'] = newNeighborSourceEnd;
               }
            }
          }
      } // End of if (overlaps)
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
      // Find the clip being moved/updated
       final updateIndex = updatedClips.indexWhere((c) => c.databaseId == clipId);
      if (updateIndex != -1) {
        // Apply updates to the existing clip model
        updatedClips[updateIndex] = updatedClips[updateIndex].copyWith(
          trackId: trackId,
          startTimeOnTrackMs: newStart,
          endTimeOnTrackMs: newEnd,
          startTimeInSourceMs: clampedStartTimeInSourceMs,
          endTimeInSourceMs: clampedEndTimeInSourceMs,
          // sourceDurationMs is assumed not to change during placement
        );
      } else {
        // This case should ideally not happen if clipId is provided for an update,
        // but handle defensively: add it as if it were new.
        print("Warning: Clip ID $clipId provided for update but not found in list. Adding as new.");
        ClipModel newClipModel = ClipModel(
          databaseId: clipId, // Use provided ID, but DB insert handles actual ID assignment
          trackId: trackId,
          name: '', // Placeholder name
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
      // Add the new clip model to the list (databaseId will be assigned on insert)
      ClipModel newClipModel = ClipModel(
        databaseId: null,
        trackId: trackId,
        name: '', // Placeholder name
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
      // Ensure the new clip is actually added to the list for the optimistic update
      updatedClips.add(newClipModel);
    }


    // Ensure the 'updatedClips' list reflects removals correctly
    final finalClipIdsToRemove = clipsToRemove.toSet(); // Use Set for efficient lookup
    updatedClips.removeWhere((clip) => clip.databaseId != null && finalClipIdsToRemove.contains(clip.databaseId));


    // 5. Return results
    return {
      'success': true,
      'newClipData': newClipData, // Contains final track & (clamped) source times for the placed clip
      'clipId': clipId, // Pass back original ID if provided
      // Ensure the returned list reflects removals and the addition/update
      'updatedClips': updatedClips,
      // Return only updates for clips *not* marked for removal
      'clipUpdates': clipUpdates.where((update) => !finalClipIdsToRemove.contains(update['id'])).toList(),
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
    // Find the original clip being dragged
    ClipModel? draggedClip;
    try {
       draggedClip = clips.firstWhere((c) => c.databaseId == clipId);
    } catch (e) {
      print("Error: Dragged clip $clipId not found in getPreviewClipsForDrag.");
      return clips; // Return original list if dragged clip isn't found
    }


    // Calculate the preview end time based on the dragged clip's duration on track
    final draggedDurationOnTrack = draggedClip.durationOnTrackMs;
    final targetEndTimeOnTrackMs = targetStartTimeOnTrackMs + draggedDurationOnTrack;


     // Use prepareClipPlacement in a read-only way to calculate the preview state
    final placementResult = prepareClipPlacement(
        clips: clips, // Pass the original full list
        clipId: clipId, // Identify the clip being moved
        trackId: targetTrackId,
        type: draggedClip.type, // Use type from dragged clip
        sourcePath: draggedClip.sourcePath, // Use source path from dragged clip
        sourceDurationMs: draggedClip.sourceDurationMs, // Use duration from dragged clip
        startTimeOnTrackMs: targetStartTimeOnTrackMs, // Target start time
        endTimeOnTrackMs: targetEndTimeOnTrackMs, // Target end time
        startTimeInSourceMs: draggedClip.startTimeInSourceMs, // Keep original source start
        endTimeInSourceMs: draggedClip.endTimeInSourceMs, // Keep original source end
    );


     if (placementResult['success'] == true) {
        // Return the calculated optimistic list which includes the moved clip and adjusted neighbors
        return List<ClipModel>.from(placementResult['updatedClips']);
    } else {
        // If placement fails for preview, return the original list (or handle error)
         print("Warning: prepareClipPlacement failed during preview generation.");
        // Fallback: Manually move the clip without overlap handling for basic preview
         final others = clips.where((c) => c.databaseId != clipId).toList();
         final movedPreview = draggedClip.copyWith(
             trackId: targetTrackId,
             startTimeOnTrackMs: targetStartTimeOnTrackMs,
             endTimeOnTrackMs: targetEndTimeOnTrackMs,
         );
         others.add(movedPreview);
         // Sort by start time for consistent display order
         others.sort((a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs));
         return others;
     }
  } // End of getPreviewClipsForDrag
}