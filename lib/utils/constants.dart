/// Constants used throughout the FlipEdit application
class AppConstants {
  /// Private constructor to prevent instantiation
  AppConstants._();
  
  /// Application name
  static const String appName = 'FlipEdit';
  
  /// Application version
  static const String appVersion = '0.1.0';
  
  /// Default frame rate (frames per second)
  static const int defaultFrameRate = 30;
  
  /// Maximum number of undo operations
  static const int maxUndoHistory = 50;
  
  /// Default video width
  static const int defaultVideoWidth = 1920;
  
  /// Default video height
  static const int defaultVideoHeight = 1080;
}

/// Constants for file operations
class FileConstants {
  /// Private constructor to prevent instantiation
  FileConstants._();
  
  /// Project file extension
  static const String projectFileExtension = '.fedit';
  
  /// Supported video file extensions
  static const List<String> supportedVideoExtensions = [
    '.mp4', '.mov', '.avi', '.mkv', '.webm'
  ];
  
  /// Supported audio file extensions
  static const List<String> supportedAudioExtensions = [
    '.mp3', '.wav', '.aac', '.flac', '.ogg'
  ];
  
  /// Supported image file extensions
  static const List<String> supportedImageExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tiff'
  ];
}

/// Constants for UI dimensions
class UiConstants {
  /// Private constructor to prevent instantiation
  UiConstants._();
  
  /// Default timeline track height
  static const double trackHeight = 60.0;
  
  /// Default timeline clip minimum width
  static const double clipMinWidth = 30.0;
  
  /// Timeline zoom levels
  static const List<double> zoomLevels = [
    0.25, 0.5, 1.0, 2.0, 4.0, 8.0
  ];
  
  /// Default padding values
  static const double paddingSmall = 4.0;
  static const double paddingMedium = 8.0;
  static const double paddingLarge = 16.0;
  
  /// Default border radius
  static const double borderRadius = 4.0;
}

/// Constants for effect processing
class EffectConstants {
  /// Private constructor to prevent instantiation
  EffectConstants._();
  
  /// Maximum effect processing iterations 
  /// (to prevent infinite loops in effect chains)
  static const int maxEffectIterations = 20;
  
  /// Default transition duration in frames
  static const int defaultTransitionFrames = 15; // 0.5 seconds at 30fps
}
