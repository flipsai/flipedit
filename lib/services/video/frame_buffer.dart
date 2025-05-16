import 'dart:collection';
import 'dart:async';
import '../../models/decoded_frame.dart';

class FrameBuffer {
  final int maxSize;
  final Queue<DecodedFrame> _frames = Queue();
  final Completer<void> _initialBufferReady = Completer();
  final StreamController<int> _bufferSizeController = StreamController.broadcast();
  
  bool _disposed = false;
  
  FrameBuffer({this.maxSize = 10});
  
  Stream<int> get bufferSizeStream => _bufferSizeController.stream;
  int get currentSize => _frames.length;
  bool get isFull => _frames.length >= maxSize;
  bool get isEmpty => _frames.isEmpty;
  
  void addFrames(List<DecodedFrame> frames) {
    if (_disposed) return;
    
    for (final frame in frames) {
      // Remove old frames if buffer is full
      while (_frames.length >= maxSize) {
        final oldFrame = _frames.removeFirst();
        oldFrame.dispose();
      }
      
      _frames.add(frame);
    }
    
    _bufferSizeController.add(_frames.length);
    
    // Signal when buffer is initially ready (half full)
    if (!_initialBufferReady.isCompleted && _frames.length >= maxSize ~/ 2) {
      _initialBufferReady.complete();
    }
  }
  
  DecodedFrame? getFrame(int frameNumber) {
    if (_disposed || _frames.isEmpty) return null;
    
    // Try to find exact frame
    for (final frame in _frames) {
      if (frame.frameNumber == frameNumber) {
        return frame;
      }
    }
    
    // Return closest frame
    DecodedFrame? closestFrame;
    int minDiff = double.infinity.toInt();
    
    for (final frame in _frames) {
      final diff = (frame.frameNumber - frameNumber).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestFrame = frame;
      }
    }
    
    return closestFrame;
  }
  
  DecodedFrame? getNextFrame() {
    if (_disposed || _frames.isEmpty) return null;
    return _frames.removeFirst();
  }
  
  Future<void> waitForInitialBuffer() {
    return _initialBufferReady.future;
  }
  
  void clear() {
    while (_frames.isNotEmpty) {
      final frame = _frames.removeFirst();
      frame.dispose();
    }
    _bufferSizeController.add(0);
  }
  
  void dispose() {
    _disposed = true;
    clear();
    _bufferSizeController.close();
  }
  
  // Get prediction of next frames needed
  List<int> predictNextFrames(int currentFrame, int count) {
    final frames = <int>[];
    for (int i = 1; i <= count; i++) {
      frames.add(currentFrame + i);
    }
    return frames;
  }
}
