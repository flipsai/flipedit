import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/src/rust/common/types.dart';
import 'package:flutter/foundation.dart';

/// Service that manages timeline operations using GStreamer Editing Services (GES)
/// This replaces the manual timeline logic with professional GES operations
class GESTimelineService extends ChangeNotifier {
  int? _timelineHandle;
  bool _isInitialized = false;
  static const double _defaultFrameRate = 30.0;
  static const int _defaultFrameRateNum = 30;
  static const int _defaultFrameRateDen = 1;

  /// Initialize the GES timeline
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      logInfo('Initializing GES timeline service');
      _timelineHandle = gesCreateTimeline().toInt();
      _isInitialized = true;
      logInfo('GES timeline service initialized with handle: $_timelineHandle');
      notifyListeners();
    } catch (e) {
      logError('GESTimelineService', 'Failed to initialize GES timeline: $e');
      throw Exception('Failed to initialize GES timeline: $e');
    }
  }

  /// Dispose of the GES timeline
  @override
  Future<void> dispose() async {
    if (_timelineHandle != null && _isInitialized) {
      try {
        gesDestroyTimeline(handle: BigInt.from(_timelineHandle!));
        logInfo('GES timeline disposed');
      } catch (e) {
        logError('GESTimelineService', 'Error disposing GES timeline: $e');
      }
    }
    _timelineHandle = null;
    _isInitialized = false;
    super.dispose();
  }

  /// Ensure timeline is initialized before operations
  void _ensureInitialized() {
    if (!_isInitialized || _timelineHandle == null) {
      throw Exception('GES timeline service not initialized');
    }
  }

  // ===============================
  // Frame and Time Calculations
  // ===============================

  /// Calculate frame position from pixel position (same interface as original)
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

  /// Convert frame to milliseconds using GES utilities
  int frameToMs(int framePosition) {
    return gesFrameToMs(
      frameNumber: framePosition,
      framerateNum: _defaultFrameRateNum,
      framerateDen: _defaultFrameRateDen,
    ).toInt();
  }

  /// Calculate millisecond position from pixels (same interface as original)
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

  /// Calculate pixel offset for frame (same interface as original)
  double calculatePixelOffsetForFrame(int frame, double zoom) {
    final safeZoom = zoom.clamp(0.01, 5.0);
    final frameWidth = 5.0 * safeZoom;
    return frame * frameWidth;
  }

  /// Calculate scroll offset for frame (same interface as original)
  double calculateScrollOffsetForFrame(int frame, double zoom) {
    return calculatePixelOffsetForFrame(frame, zoom);
  }

  // ===============================
  // GES-Powered Timeline Operations
  // ===============================

  /// Prepare clip placement using GES (replaces complex manual logic)
  Future<Map<String, dynamic>> prepareClipPlacement({
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
  }) async {
    _ensureInitialized();

    try {
      logInfo('Preparing clip placement using GES for track $trackId');

      // Create timeline clip data
      final timelineClip = TimelineClip(
        id: clipId,
        trackId: trackId,
        sourcePath: sourcePath,
        startTimeOnTrackMs: startTimeOnTrackMs,
        endTimeOnTrackMs: endTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
        previewPositionX: 0.0,
        previewPositionY: 0.0,
        previewWidth: 1920.0,
        previewHeight: 1080.0,
      );

      // Use GES to calculate optimal placement
      final placementResult = gesCalculateClipPlacement(
        handle: BigInt.from(_timelineHandle!),
        clipData: timelineClip,
      );

      // Convert overlaps to legacy format for compatibility
      List<Map<String, dynamic>> clipUpdates = [];
      List<int> clipsToRemove = [];

      for (final overlap in placementResult.overlappingClips) {
        switch (overlap.actionType) {
          case 'remove':
            clipsToRemove.add(overlap.clipId);
            break;
          case 'trim_start':
            if (overlap.actionTimeMs != null) {
              clipUpdates.add({
                'id': overlap.clipId,
                'fields': {
                  'startTimeOnTrackMs': overlap.actionTimeMs!.toInt(),
                  'startTimeInSourceMs': _calculateNewSourceStart(
                    clips, overlap.clipId, overlap.actionTimeMs!.toInt()),
                },
              });
            }
            break;
          case 'trim_end':
            if (overlap.actionTimeMs != null) {
              clipUpdates.add({
                'id': overlap.clipId,
                'fields': {
                  'endTimeOnTrackMs': overlap.actionTimeMs!.toInt(),
                  'endTimeInSourceMs': _calculateNewSourceEnd(
                    clips, overlap.clipId, overlap.actionTimeMs!.toInt()),
                },
              });
            }
            break;
        }
      }

      // Create updated clips list by applying GES-calculated changes
      List<ClipModel> updatedClips = List<ClipModel>.from(clips);

      // Remove clips marked for removal
      updatedClips.removeWhere(
        (clip) => clip.databaseId != null && clipsToRemove.contains(clip.databaseId!),
      );

      // Apply updates
      for (final update in clipUpdates) {
        final clipId = update['id'] as int;
        final fields = update['fields'] as Map<String, dynamic>;
        
        final clipIndex = updatedClips.indexWhere((c) => c.databaseId == clipId);
        if (clipIndex != -1) {
          final clip = updatedClips[clipIndex];
          updatedClips[clipIndex] = clip.copyWith(
            startTimeOnTrackMs: fields['startTimeOnTrackMs'],
            endTimeOnTrackMs: fields['endTimeOnTrackMs'],
            startTimeInSourceMs: fields['startTimeInSourceMs'],
            endTimeInSourceMs: fields['endTimeInSourceMs'],
          );
        }
      }

      // Add or update the new/moved clip
      if (clipId != null) {
        final existingIndex = updatedClips.indexWhere((c) => c.databaseId == clipId);
        if (existingIndex != -1) {
          updatedClips[existingIndex] = updatedClips[existingIndex].copyWith(
            trackId: trackId,
            startTimeOnTrackMs: placementResult.startTimeMs.toInt(),
            endTimeOnTrackMs: placementResult.endTimeMs.toInt(),
            startTimeInSourceMs: placementResult.startTimeInSourceMs.toInt(),
            endTimeInSourceMs: placementResult.endTimeInSourceMs.toInt(),
          );
        } else {
          updatedClips.add(ClipModel(
            databaseId: clipId,
            trackId: trackId,
            name: '',
            type: type,
            sourcePath: sourcePath,
            sourceDurationMs: sourceDurationMs,
            startTimeInSourceMs: placementResult.startTimeInSourceMs.toInt(),
            endTimeInSourceMs: placementResult.endTimeInSourceMs.toInt(),
            startTimeOnTrackMs: placementResult.startTimeMs.toInt(),
            endTimeOnTrackMs: placementResult.endTimeMs.toInt(),
          ));
        }
      } else {
        updatedClips.add(ClipModel(
          trackId: trackId,
          name: '',
          type: type,
          sourcePath: sourcePath,
          sourceDurationMs: sourceDurationMs,
          startTimeInSourceMs: placementResult.startTimeInSourceMs.toInt(),
          endTimeInSourceMs: placementResult.endTimeInSourceMs.toInt(),
          startTimeOnTrackMs: placementResult.startTimeMs.toInt(),
          endTimeOnTrackMs: placementResult.endTimeMs.toInt(),
        ));
      }

      final result = {
        'success': placementResult.success,
        'newClipData': {
          'trackId': trackId,
          'type': type,
          'sourcePath': sourcePath,
          'sourceDurationMs': sourceDurationMs,
          'startTimeOnTrackMs': placementResult.startTimeMs.toInt(),
          'endTimeOnTrackMs': placementResult.endTimeMs.toInt(),
          'startTimeInSourceMs': placementResult.startTimeInSourceMs.toInt(),
          'endTimeInSourceMs': placementResult.endTimeInSourceMs.toInt(),
        },
        'clipId': placementResult.clipId,
        'updatedClips': updatedClips,
        'clipUpdates': clipUpdates,
        'clipsToRemove': clipsToRemove,
      };

      logInfo('GES clip placement completed successfully');
      return result;
    } catch (e) {
      logError('GESTimelineService', 'Error in prepareClipPlacement: $e');
      rethrow;
    }
  }

  /// Get overlapping clips using GES (replaces manual overlap detection)
  Future<List<ClipModel>> getOverlappingClips(
    List<ClipModel> clips,
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) async {
    _ensureInitialized();

    try {
      final overlaps = gesFindOverlappingClips(
        handle: BigInt.from(_timelineHandle!),
        trackId: trackId,
        startTimeMs: BigInt.from(startMs),
        endTimeMs: BigInt.from(endMs),
        excludeClipId: excludeClipId,
      );

      // Convert overlap info back to ClipModel list
      final overlappingClips = <ClipModel>[];
      for (final overlap in overlaps) {
        final clip = clips.firstWhere(
          (c) => c.databaseId == overlap.clipId,
          orElse: () => throw Exception('Overlapping clip ${overlap.clipId} not found in clips list'),
        );
        overlappingClips.add(clip);
      }

      return overlappingClips;
    } catch (e) {
      logError('GESTimelineService', 'Error getting overlapping clips: $e');
      return [];
    }
  }

  /// Get preview clips for drag operation using GES
  Future<List<ClipModel>> getPreviewClipsForDrag({
    required List<ClipModel> clips,
    required int clipId,
    required int targetTrackId,
    required int targetStartTimeOnTrackMs,
  }) async {
    try {
      final draggedClip = clips.firstWhere((c) => c.databaseId == clipId);
      final draggedDurationOnTrack = draggedClip.durationOnTrackMs;
      final targetEndTimeOnTrackMs = targetStartTimeOnTrackMs + draggedDurationOnTrack;

      final placementResult = await prepareClipPlacement(
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
        logInfo("Warning: GES clip placement failed during preview generation.");
        // Fallback to simple preview
        final others = clips.where((c) => c.databaseId != clipId).toList();
        final movedPreview = draggedClip.copyWith(
          trackId: targetTrackId,
          startTimeOnTrackMs: targetStartTimeOnTrackMs,
          endTimeOnTrackMs: targetEndTimeOnTrackMs,
        );
        others.add(movedPreview);
        others.sort((a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs));
        return others;
      }
    } catch (e) {
      logError('GESTimelineService', 'Error in getPreviewClipsForDrag: $e');
      // Return original clips as fallback
      return clips;
    }
  }

  // ===============================
  // GES Timeline Management
  // ===============================

  /// Add a clip to the GES timeline
  Future<void> addClipToTimeline(ClipModel clip) async {
    _ensureInitialized();

    try {
      final timelineClip = _clipModelToTimelineClip(clip);
      gesAddClip(
        handle: BigInt.from(_timelineHandle!),
        clipData: timelineClip,
      );
      logInfo('Added clip ${clip.databaseId} to GES timeline');
    } catch (e) {
      logError('GESTimelineService', 'Error adding clip to timeline: $e');
      rethrow;
    }
  }

  /// Move a clip in the GES timeline
  Future<void> moveClipInTimeline(int clipId, int newTrackId, int newStartTimeMs) async {
    _ensureInitialized();

    try {
      gesMoveClip(
        handle: BigInt.from(_timelineHandle!),
        clipId: clipId,
        newTrackId: newTrackId,
        newStartTimeMs: BigInt.from(newStartTimeMs),
      );
      logInfo('Moved clip $clipId to track $newTrackId at ${newStartTimeMs}ms');
    } catch (e) {
      logError('GESTimelineService', 'Error moving clip in timeline: $e');
      rethrow;
    }
  }

  /// Resize a clip in the GES timeline
  Future<void> resizeClipInTimeline(int clipId, int newStartTimeMs, int newEndTimeMs) async {
    _ensureInitialized();

    try {
      gesResizeClip(
        handle: BigInt.from(_timelineHandle!),
        clipId: clipId,
        newStartTimeMs: BigInt.from(newStartTimeMs),
        newEndTimeMs: BigInt.from(newEndTimeMs),
      );
      logInfo('Resized clip $clipId to ${newStartTimeMs}ms - ${newEndTimeMs}ms');
    } catch (e) {
      logError('GESTimelineService', 'Error resizing clip in timeline: $e');
      rethrow;
    }
  }

  /// Remove a clip from the GES timeline
  Future<void> removeClipFromTimeline(int clipId) async {
    _ensureInitialized();

    try {
      gesRemoveClip(
        handle: BigInt.from(_timelineHandle!),
        clipId: clipId,
      );
      logInfo('Removed clip $clipId from GES timeline');
    } catch (e) {
      logError('GESTimelineService', 'Error removing clip from timeline: $e');
      rethrow;
    }
  }

  /// Perform ripple edit using GES
  Future<List<ClipModel>> performRippleEdit(
    List<ClipModel> clips,
    int clipId,
    int newStartTimeMs,
  ) async {
    _ensureInitialized();

    try {
      final rippleResults = gesRippleEdit(
        handle: BigInt.from(_timelineHandle!),
        clipId: clipId,
        newStartTimeMs: BigInt.from(newStartTimeMs),
      );
      
      // Convert results back to ClipModel list
      List<ClipModel> updatedClips = List<ClipModel>.from(clips);

      for (final result in rippleResults) {
        if (result.clipId != null) {
          final clipIndex = updatedClips.indexWhere((c) => c.databaseId == result.clipId);
          if (clipIndex != -1) {
            updatedClips[clipIndex] = updatedClips[clipIndex].copyWith(
              trackId: result.trackId,
              startTimeOnTrackMs: result.startTimeMs.toInt(),
              endTimeOnTrackMs: result.endTimeMs.toInt(),
            );
          }
        }
      }

      logInfo('Ripple edit completed, affected ${rippleResults.length} clips');
      return updatedClips;
    } catch (e) {
      logError('GESTimelineService', 'Error performing ripple edit: $e');
      return clips;
    }
  }

  /// Get timeline data for rendering
  Future<List<TimelineClip>> getTimelineData() async {
    _ensureInitialized();

    try {
      return gesGetTimelineData(handle: BigInt.from(_timelineHandle!));
    } catch (e) {
      logError('GESTimelineService', 'Error getting timeline data: $e');
      return [];
    }
  }

  /// Get timeline duration
  Future<int> getTimelineDurationMs() async {
    _ensureInitialized();

    try {
      final duration = gesGetTimelineDurationMs(handle: BigInt.from(_timelineHandle!));
      return duration.toInt();
    } catch (e) {
      logError('GESTimelineService', 'Error getting timeline duration: $e');
      return 0;
    }
  }

  // ===============================
  // Helper Methods
  // ===============================

  /// Convert ClipModel to TimelineClip for Rust bridge
  TimelineClip _clipModelToTimelineClip(ClipModel clip) {
    return TimelineClip(
      id: clip.databaseId,
      trackId: clip.trackId,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: clip.startTimeOnTrackMs,
      endTimeOnTrackMs: clip.endTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
      previewPositionX: clip.previewPositionX,
      previewPositionY: clip.previewPositionY,
      previewWidth: clip.previewWidth,
      previewHeight: clip.previewHeight,
    );
  }

  /// Calculate new source start time after trim operation
  int _calculateNewSourceStart(List<ClipModel> clips, int clipId, int newTrackStart) {
    try {
      final clip = clips.firstWhere((c) => c.databaseId == clipId);
      final trackTrimAmount = newTrackStart - clip.startTimeOnTrackMs;
      return (clip.startTimeInSourceMs + trackTrimAmount).clamp(0, clip.sourceDurationMs);
    } catch (e) {
      return 0;
    }
  }

  /// Calculate new source end time after trim operation
  int _calculateNewSourceEnd(List<ClipModel> clips, int clipId, int newTrackEnd) {
    try {
      final clip = clips.firstWhere((c) => c.databaseId == clipId);
      final trackTrimAmount = clip.endTimeOnTrackMs - newTrackEnd;
      return (clip.endTimeInSourceMs - trackTrimAmount).clamp(clip.startTimeInSourceMs, clip.sourceDurationMs);
    } catch (e) {
      return 1000; // Default 1 second
    }
  }

  /// Validate clip operation
  Future<bool> validateClipOperation(ClipModel clip) async {
    _ensureInitialized();

    try {
      final timelineClip = _clipModelToTimelineClip(clip);
      return gesValidateClipOperation(
        handle: BigInt.from(_timelineHandle!),
        clipData: timelineClip,
      );
    } catch (e) {
      logError('GESTimelineService', 'Error validating clip operation: $e');
      return false;
    }
  }

  // Getters
  bool get isInitialized => _isInitialized;
  int? get timelineHandle => _timelineHandle;
}