import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import '../models/clip.dart';
import '../persistence/database/project_database.dart' show Track;
import '../services/project_database_service.dart';
import '../services/preview_sync_service.dart';
import '../services/canvas_dimensions_service.dart';
import '../utils/logger.dart' as logger;

class TimelineStateViewModel extends ChangeNotifier {
  final String _logTag = 'TimelineStateViewModel';

  final ProjectDatabaseService _projectDatabaseService =
      di<ProjectDatabaseService>();
  final PreviewSyncService _previewSyncService = di<PreviewSyncService>();
  final CanvasDimensionsService _canvasDimensionsService = 
      di<CanvasDimensionsService>();

  final ValueNotifier<List<ClipModel>> clipsNotifier =
      ValueNotifier<List<ClipModel>>([]);
  List<ClipModel> get clips => List.unmodifiable(clipsNotifier.value);

  final ValueNotifier<List<Track>> tracksListNotifier =
      ValueNotifier<List<Track>>([]);
  ValueNotifier<List<Track>> get tracksNotifierForView => tracksListNotifier;
  List<int> get currentTrackIds =>
      tracksListNotifier.value.map((t) => t.id).toList();

  final ValueNotifier<int?> selectedTrackIdNotifier = ValueNotifier<int?>(null);
  int? get selectedTrackId => selectedTrackIdNotifier.value;
  set selectedTrackId(int? value) {
    if (selectedTrackIdNotifier.value != value) {
      logger.logInfo(
        'Track selection changed: ${selectedTrackIdNotifier.value} -> $value',
        _logTag,
      );
      selectedTrackIdNotifier.value = value;
      _syncClipSelectionToTrack(value);
    }
  }

  final ValueNotifier<int?> selectedClipIdNotifier = ValueNotifier<int?>(null);
  int? get selectedClipId => selectedClipIdNotifier.value;
  set selectedClipId(int? value) {
    if (selectedClipIdNotifier.value != value) {
      logger.logInfo(
        'Clip selection changed: ${selectedClipIdNotifier.value} -> $value',
        _logTag,
      );
      selectedClipIdNotifier.value = value;
      _syncTrackSelectionToClip(value);
    }
  }

  bool get hasContent =>
      clipsNotifier.value.isNotEmpty || tracksListNotifier.value.isNotEmpty;

  final List<VoidCallback> _internalListeners = [];

  TimelineStateViewModel() {
    logger.logInfo('Initializing TimelineStateViewModel', _logTag);
    _setupServiceListeners();
    _initialLoad();
  }

  Future<void> refreshClips() async {
    if (_projectDatabaseService.currentDatabase == null) {
      logger.logWarning(
        'Database connection not available, cannot refresh clips.',
        _logTag,
      );
      clipsNotifier.value = []; // Clear clips if DB is gone
      // Update canvas dimensions service about empty timeline
      _canvasDimensionsService.updateHasClipsState(0);
      return;
    }
    logger.logInfo(
      'Refreshing clips using ProjectDatabaseService.getAllTimelineClips()...',
      _logTag,
    );
    List<ClipModel> allClips =
        await _projectDatabaseService.getAllTimelineClips();
    allClips.sort(
      (a, b) => a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs),
    );

    if (!listEquals(clipsNotifier.value, allClips)) {
      clipsNotifier.value = allClips;
      // Update canvas dimensions service about clip count
      _canvasDimensionsService.updateHasClipsState(allClips.length);
      
      _previewSyncService.sendClipsToPreviewServer(); // Sync after update
      logger.logDebug(
        'Clips list updated in ViewModel (${allClips.length} clips). Notifier triggered.',
        _logTag,
      );
    } else {
      logger.logDebug(
        'Refreshed clips list is identical to current ViewModel state. No update needed.',
        _logTag,
      );
    }
  }

  /// Sets the clips list directly and notifies listeners.
  /// Intended for use by commands that have already calculated the new state.
  void setClips(List<ClipModel> newClipsList) {
    // Ensure the list is sorted, as commands might not always provide a sorted list.
    // Sorting here guarantees consistency for listeners and for listEquals.
    newClipsList.sort((a, b) {
      int trackCompare = a.trackId.compareTo(b.trackId);
      if (trackCompare != 0) return trackCompare;
      return a.startTimeOnTrackMs.compareTo(b.startTimeOnTrackMs);
    });

    final bool contentChanged = !listEquals(clipsNotifier.value, newClipsList);
    final bool instanceChanged = !identical(clipsNotifier.value, newClipsList);

    if (contentChanged || instanceChanged) {
      clipsNotifier.value = newClipsList; // ValueNotifier will notify if its criteria are met
      _canvasDimensionsService.updateHasClipsState(newClipsList.length);
      _previewSyncService.sendClipsToPreviewServer(); // Sync with preview server

      logger.logDebug(
        'Clips list set by command. Content changed: $contentChanged, Instance changed: $instanceChanged. (${newClipsList.length} clips). Notifiers triggered.',
        _logTag,
      );
      notifyListeners(); // TimelineStateViewModel (ChangeNotifier) notifies its listeners
    } else {
      // Content and instance are identical. No state change.
      logger.logDebug(
        'Explicitly set clips list is identical in content and instance to current. No update triggered.',
        _logTag,
      );
      // No need to call notifyListeners() if there's truly no change.
      // If a command results in the exact same state, the UI shouldn't need to re-render from this ViewModel's perspective.
    }
  }

  Future<void> loadDataForProject() async {
    logger.logInfo('Syncing state after project load.', _logTag);
    _initialLoad(); // Sync tracks immediately
    await refreshClips(); // Refresh clips for the loaded project
  }

  void _initialLoad() {
    final serviceTracks = _projectDatabaseService.tracksNotifier.value;
    if (!listEquals(tracksListNotifier.value, serviceTracks)) {
      logger.logInfo(
        'Performing initial sync of ${serviceTracks.length} tracks from service to ViewModel',
        _logTag,
      );
      tracksListNotifier.value = List.from(serviceTracks);
    }
  }

  void _setupServiceListeners() {
    tracksListener() {
      final serviceTracks = _projectDatabaseService.tracksNotifier.value;
      if (!listEquals(tracksListNotifier.value, serviceTracks)) {
        logger.logInfo(
          '👂 Tracks list changed in Service. Updating ViewModel (${serviceTracks.length} tracks).',
          _logTag,
        );
        final previouslySelectedTrackId =
            selectedTrackId; // Store before update
        tracksListNotifier.value = List.from(serviceTracks);

        // If the previously selected track was deleted, clear selection
        if (previouslySelectedTrackId != null &&
            !currentTrackIds.contains(previouslySelectedTrackId)) {
          logger.logWarning(
            'Previously selected track $previouslySelectedTrackId no longer exists. Clearing selection.',
            _logTag,
          );
          selectedTrackId =
              null; // This will also clear clip selection via _syncClipSelectionToTrack
        }
        // Refresh clips as track changes might affect them (e.g., deletion)
        refreshClips();
      }
    }

    _projectDatabaseService.tracksNotifier.addListener(tracksListener);
    _internalListeners.add(
      () =>
          _projectDatabaseService.tracksNotifier.removeListener(tracksListener),
    );
  }

  void _syncClipSelectionToTrack(int? trackId) {
    if (trackId != null && selectedClipId != null) {
      ClipModel? selectedClip;
      try {
        selectedClip = clipsNotifier.value.firstWhere(
          (clip) => clip.databaseId == selectedClipId,
        );
      } catch (e) {
        selectedClip = null;
      }
      if (selectedClip != null && selectedClip.trackId != trackId) {
        logger.logInfo(
          'Deselecting clip $selectedClipId as it doesn\'t belong to newly selected track $trackId',
          _logTag,
        );
        // Set directly to avoid re-triggering track selection sync
        if (selectedClipIdNotifier.value != null) {
          selectedClipIdNotifier.value = null;
        }
      }
    } else if (trackId == null && selectedClipId != null) {
      // If track is deselected, deselect clip too
      logger.logInfo(
        'Deselecting clip $selectedClipId because track was deselected',
        _logTag,
      );
      if (selectedClipIdNotifier.value != null) {
        selectedClipIdNotifier.value = null;
      }
    }
  }

  void _syncTrackSelectionToClip(int? clipId) {
    if (clipId != null) {
      try {
        final clip = clipsNotifier.value.firstWhere(
          (c) => c.databaseId == clipId,
        );
        // Set directly to avoid re-triggering clip selection sync
        if (selectedTrackIdNotifier.value != clip.trackId) {
          logger.logInfo(
            'Setting track ${clip.trackId} based on clip selection $clipId',
            _logTag,
          );
          selectedTrackIdNotifier.value = clip.trackId;
        }
      } catch (e) {
        logger.logWarning(
          'Could not find clip with ID $clipId in clips list to update track selection',
          _logTag,
        );
        // If clip not found (maybe due to timing), deselect track for safety? Or leave as is?
        // Leaving as is for now.
      }
    }
    // No action needed if clipId is null (deselecting clip doesn't deselect track)
  }

  @override
  void dispose() {
    logger.logInfo('Disposing TimelineStateViewModel', _logTag);
    for (final removeListener in _internalListeners) {
      removeListener();
    }
    _internalListeners.clear();

    clipsNotifier.dispose();
    tracksListNotifier.dispose();
    selectedTrackIdNotifier.dispose();
    selectedClipIdNotifier.dispose();

    super.dispose();
  }
}
