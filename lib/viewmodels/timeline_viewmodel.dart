import 'package:flutter/foundation.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';

class TimelineViewModel extends ChangeNotifier {
  final List<Clip> _clips = [];
  List<Clip> get clips => List.unmodifiable(_clips);
  
  double _zoom = 1.0;
  double get zoom => _zoom;
  
  int _currentFrame = 0;
  int get currentFrame => _currentFrame;
  
  int _totalFrames = 0;
  int get totalFrames => _totalFrames;
  
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  
  // Add a clip to the timeline
  void addClip(Clip clip) {
    _clips.add(clip);
    _recalculateTotalFrames();
    notifyListeners();
  }
  
  // Remove a clip from the timeline
  void removeClip(String clipId) {
    _clips.removeWhere((clip) => clip.id == clipId);
    _recalculateTotalFrames();
    notifyListeners();
  }
  
  // Update an existing clip
  void updateClip(String clipId, Clip updatedClip) {
    final index = _clips.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      _clips[index] = updatedClip;
      _recalculateTotalFrames();
      notifyListeners();
    }
  }
  
  // Move clip to a different position on the timeline
  void moveClip(String clipId, int newStartFrame) {
    final index = _clips.indexWhere((clip) => clip.id == clipId);
    if (index >= 0) {
      final clip = _clips[index];
      final updatedClip = clip.copyWith(startFrame: newStartFrame);
      _clips[index] = updatedClip;
      _recalculateTotalFrames();
      notifyListeners();
    }
  }
  
  // Set the current playhead position
  void seekTo(int frame) {
    if (frame >= 0 && frame <= _totalFrames) {
      _currentFrame = frame;
      notifyListeners();
    }
  }
  
  // Toggle playback state
  void togglePlayback() {
    _isPlaying = !_isPlaying;
    notifyListeners();
    
    if (_isPlaying) {
      _startPlayback();
    }
  }
  
  // Set the zoom level
  void setZoom(double newZoom) {
    if (newZoom >= 0.1 && newZoom <= 5.0) {
      _zoom = newZoom;
      notifyListeners();
    }
  }
  
  // Private helpers
  void _recalculateTotalFrames() {
    if (_clips.isEmpty) {
      _totalFrames = 0;
    } else {
      _totalFrames = _clips.map((clip) => clip.startFrame + clip.durationFrames).reduce((a, b) => a > b ? a : b);
    }
  }
  
  void _startPlayback() {
    // In a real implementation, this would set up a timer to advance frames
    // and coordinate with a player service
  }
}
