import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/command_history_service.dart';

class ClipCommands {
  static ClipCommand createMoveClipCommand({
    required ClipModel clip,
    required int newTrackId,
    required int newStartTimeOnTrackMs,
    required Function(Map<String, dynamic>) updateFunction,
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
    
    return ClipCommand(oldState, newState, updateFunction);
  }
  
  static ClipCommand createResizeClipCommand({
    required ClipModel clip,
    required int newStartTimeOnTrackMs,
    required int newEndTimeOnTrackMs,
    required int newStartTimeInSourceMs,
    required int newEndTimeInSourceMs,
    required Function(Map<String, dynamic>) updateFunction,
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
    
    return ClipCommand(oldState, newState, updateFunction);
  }
} 