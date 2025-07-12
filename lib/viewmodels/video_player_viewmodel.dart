import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flipedit/src/rust/common/types.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerViewModel {
  GesTimelinePlayer? _timelinePlayer;
  final ValueNotifier<int?> textureIdNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String?> errorMessageNotifier = ValueNotifier<String?>(null);

  // Convenient getters
  int? get textureId => textureIdNotifier.value;
  String? get errorMessage => errorMessageNotifier.value;

  VideoPlayerViewModel() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Build timeline data from current project
      final timelineData = await buildTimelineData();
      
      if (timelineData.tracks.isEmpty) {
        logInfo('VideoPlayerViewModel', 'No tracks available for timeline initialization');
        return;
      }

      // Acquire Flutter engine handle for zero-copy texture rendering
      final handle = await EngineContext.instance.getEngineHandle();

      // Create GES timeline player with timeline data
      final (player, textureId) = await createGesTimelinePlayer(
        timelineData: timelineData,
        engineHandle: handle,
      );

      _timelinePlayer = player;

      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.registerTimelinePlayer(_timelinePlayer!);

      textureIdNotifier.value = textureId;
      
      logInfo('VideoPlayerViewModel', 'Successfully initialized GES timeline player with ${timelineData.tracks.length} tracks');
    } catch (e) {
      final errMsg = "Failed to initialize timeline player: $e";
      errorMessageNotifier.value = errMsg;
      logError('VideoPlayerViewModel', errMsg);
    }
  }

  Future<TimelineData> buildTimelineData() async {
    final projectDatabaseService = di<ProjectDatabaseService>();
    final tracks = projectDatabaseService.tracksNotifier.value;
    
    List<TimelineTrack> timelineTracks = [];
    
    for (final track in tracks) {
      // Get clips for this track
      final clipRows = await projectDatabaseService.clipDao?.getClipsForTrack(track.id) ?? [];
      
      final clips = clipRows.map((clipRow) => TimelineClip(
        id: clipRow.id,
        trackId: clipRow.trackId,
        sourcePath: clipRow.sourcePath,
        startTimeOnTrackMs: clipRow.startTimeOnTrackMs,
        endTimeOnTrackMs: clipRow.endTimeOnTrackMs ?? clipRow.startTimeOnTrackMs + (clipRow.endTimeInSourceMs - clipRow.startTimeInSourceMs),
        startTimeInSourceMs: clipRow.startTimeInSourceMs,
        endTimeInSourceMs: clipRow.endTimeInSourceMs,
        previewPositionX: clipRow.previewPositionX,
        previewPositionY: clipRow.previewPositionY,
        previewWidth: clipRow.previewWidth,
        previewHeight: clipRow.previewHeight,
      )).toList();
      
      // DEBUG: Log transform values being passed to Rust
      for (final clip in clips) {
        logInfo('VideoPlayerViewModel',
          'Clip ${clip.id} transforms: X=${clip.previewPositionX}, Y=${clip.previewPositionY}, W=${clip.previewWidth}, H=${clip.previewHeight}');
      }
      
      timelineTracks.add(TimelineTrack(
        id: track.id,
        name: track.name,
        clips: clips,
      ));
    }
    
    return TimelineData(tracks: timelineTracks);
  }

  Future<void> togglePlayPause() async {
    if (_timelinePlayer == null) return;

    try {
      final videoPlayerService = di<VideoPlayerService>();
      final isPlaying = videoPlayerService.isPlaying;
      logInfo('VideoPlayerViewModel', 'Toggle play/pause – currently playing: $isPlaying');

      if (isPlaying) {
        await _timelinePlayer!.pause();
        videoPlayerService.setPlayingState(false);
      } else {
        await _timelinePlayer!.play();
        videoPlayerService.setPlayingState(true);
      }
    } catch (e) {
      final errMsg = "Playback error: $e";
      errorMessageNotifier.value = errMsg;
      logError('VideoPlayerViewModel', errMsg);
    }
  }

  Future<void> refreshTimeline() async {
    if (_timelinePlayer == null) return;
    
    try {
      logInfo('VideoPlayerViewModel', 'Refreshing timeline with updated data');
      final timelineData = await buildTimelineData();
      
      // Acquire Flutter engine handle for zero-copy texture rendering
      final handle = await EngineContext.instance.getEngineHandle();
      
      await _timelinePlayer!.loadTimeline(timelineData: timelineData, engineHandle: handle);
    } catch (e) {
      final errMsg = "Failed to refresh timeline: $e";
      errorMessageNotifier.value = errMsg;
      logError('VideoPlayerViewModel', errMsg);
    }
  }

  Future<void> dispose() async {
    try {
      final videoPlayerService = di<VideoPlayerService>();
      videoPlayerService.unregisterTimelinePlayer();
      
      // Await the Rust disposal to ensure it completes on the correct thread
      if (_timelinePlayer != null) {
        await _timelinePlayer!.dispose();
        _timelinePlayer = null;
      }
      
      textureIdNotifier.dispose();
      errorMessageNotifier.dispose();
    } catch (e) {
      logError('VideoPlayerViewModel', 'Error during disposal: $e');
      // Still dispose notifiers even if Rust disposal fails
      textureIdNotifier.dispose();
      errorMessageNotifier.dispose();
    }
  }
} 