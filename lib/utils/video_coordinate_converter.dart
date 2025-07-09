import 'dart:ui';
import 'package:flipedit/models/clip_transform.dart';
import 'package:flipedit/models/clip.dart';

class VideoCoordinateConverter {
  /// Convert clip video coordinates to screen coordinates
  static Rect videoToScreen(ClipModel clip, Size videoSize, Size screenSize) {
    if (videoSize.width == 0 || videoSize.height == 0) {
      return Rect.zero;
    }
    
    final scaleX = screenSize.width / videoSize.width;
    final scaleY = screenSize.height / videoSize.height;
    
    return Rect.fromLTWH(
      clip.previewPositionX * scaleX,
      clip.previewPositionY * scaleY,
      clip.previewWidth * scaleX,
      clip.previewHeight * scaleY,
    );
  }
  
  /// Convert screen coordinates to video coordinates
  static ClipTransform screenToVideo(Rect screenRect, Size videoSize, Size screenSize) {
    if (screenSize.width == 0 || screenSize.height == 0) {
      return ClipTransform(x: 0, y: 0, width: videoSize.width, height: videoSize.height);
    }
    
    final scaleX = videoSize.width / screenSize.width;
    final scaleY = videoSize.height / screenSize.height;
    
    return ClipTransform(
      x: screenRect.left * scaleX,
      y: screenRect.top * scaleY,
      width: screenRect.width * scaleX,
      height: screenRect.height * scaleY,
    );
  }
  
  /// Clamp rectangle to bounds
  static Rect clampToBounds(Rect rect, Size bounds) {
    final left = rect.left.clamp(0.0, bounds.width);
    final top = rect.top.clamp(0.0, bounds.height);
    final right = rect.right.clamp(0.0, bounds.width);
    final bottom = rect.bottom.clamp(0.0, bounds.height);
    
    return Rect.fromLTRB(left, top, right, bottom);
  }
}