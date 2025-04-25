import 'dart:async';

import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/models/enums/edit_mode.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart' as logger;

import 'package:flipedit/viewmodels/timeline_utils.dart';
import 'package:watch_it/watch_it.dart';
import 'commands/timeline_command.dart';
import 'commands/add_clip_command.dart';
import 'package:flipedit/services/undo_redo_service.dart';

class TimelineViewModel {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final UndoRedoService _undoRedoService = di<UndoRedoService>();

  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);

  List<int> currentTrackIds = [];

  final ValueNotifier<double> zoomNotifier = ValueNotifier<double>(1.0);
  double get zoom => zoomNotifier.value;
  set zoom(double value) {
    if (zoomNotifier.value == value || value < 0.1 || value > 5.0) return;
    zoomNotifier.value = value;
  }

  final ValueNotifier<int> currentFrameNotifier = ValueNotifier<int>(0);
  int get currentFrame => currentFrameNotifier.value;
  set currentFrame(int value) {
    final totalFrames = _calculateTotalFrames();
    final clampedValue = value.clamp(0, totalFrames);
    if (currentFrameNotifier.value == clampedValue) return;
    currentFrameNotifier.value = clampedValue;
  }

  final ValueNotifier<int> totalFramesNotifier = ValueNotifier<int>(0);

  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  final ScrollController trackContentHorizontalScrollController =
      ScrollController();

  // Added back Notifier for the width of the track label area
  final ValueNotifier<double> trackLabelWidthNotifier = ValueNotifier(120.0);

  final ValueNotifier<EditMode> currentEditMode = ValueNotifier(
    EditMode.select,
  );

  Timer? _frameUpdateTimer;

  // Helper to set edit mode and notify
  void setEditMode(EditMode mode) {
    if (currentEditMode.value != mode) {
      currentEditMode.value = mode;
    }
  }

  Timer? _playbackTimer;
  StreamSubscription? _controllerPositionSubscription;

  StreamSubscription? _clipStreamSubscription;

  late final VoidCallback _debouncedFrameUpdate;

  /// Executes a timeline command and refreshes undo stack
  Future<void> runCommand(TimelineCommand cmd) async {
    await cmd.execute();
    await _undoRedoService.init();
  }

  /// Undoes the last operation via service
  Future<void> undo() async {
    await _undoRedoService.undo();
  }

  /// Redoes the last undone operation via service
  Future<void> redo() async {
    await _undoRedoService.redo();
  }

  /// Notifiers for UI binding
  ValueNotifier<bool> get canUndoNotifier => _undoRedoService.canUndo;
  ValueNotifier<bool> get canRedoNotifier => _undoRedoService.canRedo;

  // Expose project database for commands
  ProjectDatabaseService get projectDatabaseService => _projectDatabaseService;

  /// Starts playback from the current frame position
  Future<void> startPlayback() async {
    if (isPlayingNotifier.value) return; // Already playing

    isPlayingNotifier.value = true;
    logger.logInfo('▶️ Starting playback from frame $currentFrame', _logTag);

    // Start timer for playback
    _startPlaybackTimer();
  }

  // Removed method to update current frame based on engine position during playback
  // as playhead is now fixed

  /// Stops playback
  void stopPlayback() {
    if (!isPlayingNotifier.value) return; // Not playing

    isPlayingNotifier.value = false;
    logger.logInfo('⏹️ Stopping playback at frame $currentFrame', _logTag);

    _stopPlaybackTimer();
  }

  Future<void> loadClipsForProject(int projectId) async {
    logger.logInfo('🔄 Loading clips for project $projectId', _logTag);

    final success = await _projectDatabaseService.loadProject(projectId);
    if (!success) {
      logger.logError('❌ Failed to load project $projectId', _logTag);
      clipsNotifier.value = [];
      recalculateAndUpdateTotalFrames();
      return;
    }

    final tracks = _projectDatabaseService.tracksNotifier.value;
    currentTrackIds = tracks.map((t) => t.id).toList();
    logger.logInfo(
      '📊 Loaded ${tracks.length} tracks with IDs: $currentTrackIds',
      _logTag,
    );

    if (tracks.isEmpty) {
      logger.logInfo('⚠️ No tracks found for project $projectId', _logTag);
      clipsNotifier.value = [];
      recalculateAndUpdateTotalFrames();
      return;
    }

    await refreshClips();
  }

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
          
    // 2. Prepare neighbor modifications (no database operations)
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
    int clampRight = 1 << 30;
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
  
  /// Updates the UI state after clip placement (called by commands after persistence)
  void updateClipsAfterPlacement(List<ClipModel> updatedClips) {
    clipsNotifier.value = updatedClips;
    recalculateAndUpdateTotalFrames();
  }
  
  /// Legacy method for backward compatibility - delegates to command pattern
  Future<bool> placeClipOnTrack({
    int? clipId, // If updating an existing clip
    required int trackId,
    required ClipType type,
    required String sourcePath,
    required int startTimeOnTrackMs,
    required int startTimeInSourceMs,
    required int endTimeInSourceMs,
  }) async {
    if (_projectDatabaseService.clipDao == null) {
      logger.logError('Clip DAO not initialized', _logTag);
      return false;
    }
    
    // For new clips, use the command pattern
    if (clipId == null) {
      final clipData = ClipModel(
        databaseId: null,
        trackId: trackId,
        name: '',
        type: type,
        sourcePath: sourcePath,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
        startTimeOnTrackMs: startTimeOnTrackMs,
        effects: [],
        metadata: {},
      );
      
      // Create an instance of the AddClipCommand class (imported at the top of the file)
      final command = AddClipCommand(
        vm: this,
        clipData: clipData,
        trackId: trackId,
        // Pass the required startTimeOnTrackMs from the method's arguments
        startTimeOnTrackMs: startTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );
      
      await runCommand(command);
      return true;
    } else {
      // For existing clips, use the old direct approach for now
      // This could be refactored to use a MoveClipCommand or similar
      final placement = prepareClipPlacement(
        clipId: clipId,
        trackId: trackId,
        type: type,
        sourcePath: sourcePath,
        startTimeOnTrackMs: startTimeOnTrackMs,
        startTimeInSourceMs: startTimeInSourceMs,
        endTimeInSourceMs: endTimeInSourceMs,
      );
      
      if (!placement['success']) return false;
      
      // Apply updates to database
      for (final update in placement['clipUpdates']) {
        await _projectDatabaseService.clipDao!.updateClipFields(
          update['id'],
          update['fields'],
          log: false,
        );
      }
      
      // Remove clips
      for (final id in placement['clipsToRemove']) {
        await _projectDatabaseService.clipDao!.deleteClip(id);
      }
      
      // Update existing clip
      await _projectDatabaseService.clipDao!.updateClipFields(
        clipId,
        {
          'trackId': trackId,
          'startTimeOnTrackMs': placement['newClipData']['startTimeOnTrackMs'],
          'startTimeInSourceMs': placement['newClipData']['startTimeInSourceMs'],
          'endTimeInSourceMs': placement['newClipData']['endTimeInSourceMs'],
        },
        log: true,
      );
      
      // Update UI
      clipsNotifier.value = placement['updatedClips'];
      recalculateAndUpdateTotalFrames();
      
      await _undoRedoService.init();
      logger.logInfo('Moved/resized clip $clipId (optimistic update)', _logTag);
      return true;
    }
  }

  /// Handles dropping a clip onto an empty timeline by creating a new track and placing the clip.
  Future<bool> handleClipDropToEmptyTimeline({
    required ClipModel clip,
    required int startTimeOnTrackMs,
  }) async {
    final databaseService = _projectDatabaseService;
    final newTrackId = await databaseService.addTrack(
      name: 'Track 1',
      type: clip.type.name,
    );
    if (newTrackId == null) {
      logger.logError('Failed to create new track', _logTag);
      return false;
    }
    logger.logInfo('New track created with ID: $newTrackId', _logTag);

    final success = await placeClipOnTrack(
      trackId: newTrackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
    );
    if (success) {
      logger.logInfo(
        'Clip "${clip.name}" added to new track $newTrackId',
        _logTag,
      );
    } else {
      logger.logError('Failed to add clip to new track $newTrackId', _logTag);
    }
    return success;
  }

  /// Updates the name of a track.
  Future<bool> updateTrackName(int trackId, String newName) async {
    final success = await _projectDatabaseService.updateTrackName(
      trackId,
      newName,
    );
    if (success) {
      logger.logInfo('Track $trackId renamed to "$newName"', _logTag);
    } else {
      logger.logError('Failed to rename track $trackId', _logTag);
    }
    return success;
  }

  /// Handles dropping a clip onto a track at the specified start time.
  Future<bool> handleClipDrop({
    required ClipModel clip,
    required int trackId,
    required int startTimeOnTrackMs,
  }) async {
    final success = await placeClipOnTrack(
      trackId: trackId,
      type: clip.type,
      sourcePath: clip.sourcePath,
      startTimeOnTrackMs: startTimeOnTrackMs,
      startTimeInSourceMs: clip.startTimeInSourceMs,
      endTimeInSourceMs: clip.endTimeInSourceMs,
    );
    if (success) {
      logger.logInfo(
        'Clip "${clip.name}" added to track $trackId at $startTimeOnTrackMs ms',
        _logTag,
      );
    } else {
      logger.logError('Failed to add clip to track $trackId', _logTag);
    }
    return success;
  }

  Future<void> refreshClips() async {
    if (_projectDatabaseService.clipDao == null) return;
    // Aggregate all clips from all tracks
    final tracks = _projectDatabaseService.tracksNotifier.value;
    List<ClipModel> allClips = [];
    for (final track in tracks) {
      final dbClips = await _projectDatabaseService.clipDao!.getClipsForTrack(
        track.id,
      );
      allClips.addAll(dbClips.map(clipFromProjectDb));
    }
    allClips.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );
    clipsNotifier.value = allClips;
    recalculateAndUpdateTotalFrames(); // Updated call
  }

  void _startPlaybackTimer() {
    _stopPlaybackTimer();
    if (isPlayingNotifier.value) {
      _playbackTimer = Timer.periodic(
        Duration(milliseconds: (1000 / kDefaultFrameRate).round()),
        (_) {
          // Removed _updateFrameFromEngine() as playhead is now fixed
          _debouncedFrameUpdate();
        },
      );
    }
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _frameUpdateTimer?.cancel();
    _frameUpdateTimer = null;
  }

  int _calculateTotalFrames() {
    if (clipsNotifier.value.isEmpty) {
      return 0;
    }
    int maxEndTimeMs = 0;
    for (final clip in clipsNotifier.value) {
      final clipEndTimeMs = clip.startTimeOnTrackMs + clip.durationMs;
      if (clipEndTimeMs > maxEndTimeMs) {
        maxEndTimeMs = clipEndTimeMs;
      }
    }
    return ClipModel.msToFrames(maxEndTimeMs);
  }

  // Made public for commands to call when necessary
  void recalculateAndUpdateTotalFrames() {
    final newTotalFrames = _calculateTotalFrames();
    if (totalFramesNotifier.value != newTotalFrames) {
      totalFramesNotifier.value = newTotalFrames;
      if (currentFrame > newTotalFrames) {
        currentFrame = newTotalFrames;
      }
    }
  }

  /// Update the width of the track label area (Added back)
  void updateTrackLabelWidth(double newWidth) {
    // Add constraints if needed, e.g., minimum/maximum width
    trackLabelWidthNotifier.value = newWidth.clamp(
      50.0,
      300.0,
    ); // Example constraints
  }

  void onDispose() {
    logger.logInfo('Disposing TimelineViewModel', _logTag);
    clipsNotifier.dispose();
    zoomNotifier.dispose();
    currentFrameNotifier.dispose();
    totalFramesNotifier.dispose();
    isPlayingNotifier.dispose();
    trackLabelWidthNotifier.dispose(); // Added back disposal
    currentEditMode.dispose();

    trackContentHorizontalScrollController.dispose();

    _stopPlaybackTimer();
    _controllerPositionSubscription?.cancel();
    _clipStreamSubscription?.cancel();
  }

  /// Trims, removes, or splits clips that overlap with [startMs, endMs) on [trackId]. Optionally excludes a clip by ID.
  Future<void> trimOrRemoveOverlappingClips(
    int trackId,
    int startMs,
    int endMs, [
    int? excludeClipId,
  ]) async {
    final overlapping = getOverlappingClips(
      trackId,
      startMs,
      endMs,
      excludeClipId,
    );
    for (final clip in overlapping) {
      final clipStart = clip.startTimeOnTrackMs;
      final clipEnd = clip.startTimeOnTrackMs + clip.durationMs;
      // Fully covered: remove
      if (clipStart >= startMs && clipEnd <= endMs) {
        // Use direct DAO call + recalculate for internal utility method
        await _projectDatabaseService.clipDao!.deleteClip(clip.databaseId!);
        recalculateAndUpdateTotalFrames(); // Ensure total frames are updated
      } else if (clipStart < endMs && clipEnd > endMs) {
        // Overlap on left: trim neighbor's end (neighbor is to the right of the new clip)
        if (clip.databaseId != null) {
          final neighborClip = clip; // Use a clearer variable name
          final amountToTrimMs =
              endMs -
              neighborClip
                  .startTimeOnTrackMs; // Calculate trim amount explicitly

          // Ensure we don't trim more than the clip's duration
          if (amountToTrimMs >= neighborClip.durationMs) {
            // If the overlap implies the entire neighbor clip should be removed
            await _projectDatabaseService.clipDao!.deleteClip(
              neighborClip.databaseId!,
            );
            // Log this removal for clarity
            logger.logInfo(
              'Neighbor clip ${neighborClip.databaseId} fully overlapped and removed.',
              _logTag,
            );
          } else if (amountToTrimMs > 0) {
            // Only update if there's actually something to trim
            final newStartTimeInSourceMs =
                neighborClip.startTimeInSourceMs + amountToTrimMs;
            final newStartTimeOnTrackMs =
                endMs; // Set the neighbor's start time to the new clip's end time

            await _projectDatabaseService.clipDao!.updateClipFields(
              neighborClip.databaseId!,
              {
                'startTimeInSourceMs': newStartTimeInSourceMs,
                'startTimeOnTrackMs':
                    newStartTimeOnTrackMs, // Update track start time
              },
              log: false,
            );
            // Log the update
            logger.logDebug(
              'Neighbor clip ${neighborClip.databaseId} trimmed (left): new track start $newStartTimeOnTrackMs ms, new source start $newStartTimeInSourceMs ms.',
              _logTag,
            );
          } else {
            // Log if no trim was needed (e.g., endMs exactly matched clipStart)
            logger.logDebug(
              'Neighbor clip ${neighborClip.databaseId} touches new clip end, no trim needed.',
              _logTag,
            );
          }
        }
      } else if (clipStart < startMs && clipEnd > startMs) {
        // Overlap on right: trim neighbor's end
        await _projectDatabaseService.clipDao!.updateClipFields(
          clip.databaseId!,
          {
            'endTimeInSourceMs':
                clip.startTimeInSourceMs + (startMs - clipStart),
          },
          log: false,
        );
      } else if (clipStart < endMs && clipEnd > endMs) {
        // Overlap on left: trim neighbor's start
        await _projectDatabaseService.clipDao!
            .updateClipFields(clip.databaseId!, {
              'startTimeInSourceMs':
                  clip.startTimeInSourceMs + (endMs - clipStart),
              'startTimeOnTrackMs': endMs,
            }, log: false);
      }
    }
    // await refreshClips(); // Removed immediate refresh - rely on stream
  }

  /// Returns all clips on the same track that overlap with [startMs, endMs). Optionally excludes a clip by ID.
  List<ClipModel> getOverlappingClips(
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
