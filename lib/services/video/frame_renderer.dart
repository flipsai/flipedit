import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/decoded_frame.dart';
import '../../models/video_texture_model.dart';

class FrameRenderer {
  final VideoTextureModel textureModel;
  final int display;
  
  // Performance tracking
  int _renderCount = 0;
  int _totalRenderTime = 0;
  int _lastFpsUpdate = 0;
  double _currentFps = 0.0;
  
  FrameRenderer({
    required this.textureModel,
    required this.display,
  });
  
  double get currentFps => _currentFps;
  double get averageRenderTime => _renderCount > 0 ? _totalRenderTime / _renderCount : 0;
  
  bool renderFrame(DecodedFrame frame) {
    if (!textureModel.isReady(display)) {
      debugPrint('Texture not ready for display $display');
      return false;
    }
    
    final startTime = DateTime.now().microsecondsSinceEpoch;
    
    try {
      // Direct rendering using FFI
      textureModel.renderFrame(
        display,
        frame.dataPtr,
        frame.dataSize,
        frame.width,
        frame.height,
      );
      
      final endTime = DateTime.now().microsecondsSinceEpoch;
      final renderTime = endTime - startTime;
      
      // Update performance metrics
      _renderCount++;
      _totalRenderTime += renderTime;
      
      // Update FPS every second
      if (endTime - _lastFpsUpdate > 1000000) {
        _currentFps = _renderCount / ((endTime - _lastFpsUpdate) / 1000000.0);
        _renderCount = 0;
        _totalRenderTime = 0;
        _lastFpsUpdate = endTime;
      }
      
      return true;
    } catch (e) {
      debugPrint('Error rendering frame: $e');
      return false;
    }
  }
  
  void reset() {
    _renderCount = 0;
    _totalRenderTime = 0;
    _lastFpsUpdate = DateTime.now().microsecondsSinceEpoch;
    _currentFps = 0.0;
  }
}
