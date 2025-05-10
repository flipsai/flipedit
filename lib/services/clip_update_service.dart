import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/command_history_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:watch_it/watch_it.dart';

class ClipUpdateService {
  final CommandHistoryService historyService;
  final ProjectDatabaseService databaseService;
  final ValueNotifier<List<ClipModel>> clipsNotifier;
  
  ClipUpdateService({
    required this.historyService,
    required this.databaseService,
    required this.clipsNotifier,
  });
  
  void updateClipFromCommand(Map<String, dynamic> state) async {
    final clipId = state['clipId'];
    if (clipId == null) return;
    
    final List<ClipModel> updatedClips = List.from(clipsNotifier.value);
    final clipIndex = updatedClips.indexWhere((c) => c.databaseId == clipId);
    
    if (clipIndex == -1) return;
    
    // Create updated clip model
    ClipModel updatedClip = updatedClips[clipIndex];
    
    // Only update the fields that are provided in the state map
    if (state.containsKey('trackId')) {
      updatedClip = updatedClip.copyWith(trackId: state['trackId']);
    }
    
    if (state.containsKey('startTimeOnTrackMs')) {
      updatedClip = updatedClip.copyWith(startTimeOnTrackMs: state['startTimeOnTrackMs']);
    }
    
    if (state.containsKey('endTimeOnTrackMs')) {
      updatedClip = updatedClip.copyWith(endTimeOnTrackMs: state['endTimeOnTrackMs']);
    }
    
    if (state.containsKey('startTimeInSourceMs')) {
      updatedClip = updatedClip.copyWith(startTimeInSourceMs: state['startTimeInSourceMs']);
    }
    
    if (state.containsKey('endTimeInSourceMs')) {
      updatedClip = updatedClip.copyWith(endTimeInSourceMs: state['endTimeInSourceMs']);
    }
    
    // Replace the clip in the list
    updatedClips[clipIndex] = updatedClip;
    
    // Update state
    clipsNotifier.value = updatedClips;
    
    // Update database - convert to fields for database update
    Map<String, dynamic> fields = {};
    if (state.containsKey('trackId')) {
      fields['trackId'] = state['trackId'];
    }
    
    if (state.containsKey('startTimeOnTrackMs')) {
      fields['startTimeOnTrackMs'] = state['startTimeOnTrackMs'];
    }
    
    if (state.containsKey('endTimeOnTrackMs')) {
      fields['endTimeOnTrackMs'] = state['endTimeOnTrackMs'];
    }
    
    if (state.containsKey('startTimeInSourceMs')) {
      fields['startTimeInSourceMs'] = state['startTimeInSourceMs'];
    }
    
    if (state.containsKey('endTimeInSourceMs')) {
      fields['endTimeInSourceMs'] = state['endTimeInSourceMs'];
    }
    
    await databaseService.clipDao?.updateClipFields(clipId, fields);
  }
  
  void moveClip({
    required ClipModel clip,
    required int newTrackId,
    required int newStartTimeOnTrackMs,
  }) {
    final oldState = {
      'clipId': clip.databaseId,
      'trackId': clip.trackId,
      'startTimeOnTrackMs': clip.startTimeOnTrackMs,
      'endTimeOnTrackMs': clip.endTimeOnTrackMs,
    };
    
    final newEndTimeOnTrackMs = newStartTimeOnTrackMs + clip.durationOnTrackMs;
    
    final newState = {
      'clipId': clip.databaseId,
      'trackId': newTrackId,
      'startTimeOnTrackMs': newStartTimeOnTrackMs,
      'endTimeOnTrackMs': newEndTimeOnTrackMs,
    };
    
    final command = ClipCommand(
      oldState,
      newState,
      updateClipFromCommand,
    );
    
    historyService.addCommand(command);
  }
  
  void resizeClip({
    required ClipModel clip,
    required int newStartTimeOnTrackMs,
    required int newEndTimeOnTrackMs,
    required int newStartTimeInSourceMs,
    required int newEndTimeInSourceMs,
  }) {
    final oldState = {
      'clipId': clip.databaseId,
      'startTimeOnTrackMs': clip.startTimeOnTrackMs,
      'endTimeOnTrackMs': clip.endTimeOnTrackMs,
      'startTimeInSourceMs': clip.startTimeInSourceMs,
      'endTimeInSourceMs': clip.endTimeInSourceMs,
    };
    
    final newState = {
      'clipId': clip.databaseId,
      'startTimeOnTrackMs': newStartTimeOnTrackMs,
      'endTimeOnTrackMs': newEndTimeOnTrackMs,
      'startTimeInSourceMs': newStartTimeInSourceMs,
      'endTimeInSourceMs': newEndTimeInSourceMs,
    };
    
    final command = ClipCommand(
      oldState,
      newState,
      updateClipFromCommand,
    );
    
    historyService.addCommand(command);
  }
} 