/// Extensions for Duration objects to enhance formatting
extension DurationExtensions on Duration {
  /// Format duration as hours:minutes:seconds
  String get formatted {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }
  
  /// Format duration with milliseconds precision (for detailed timing)
  String get formattedWithMs {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String threeDigits(int n) => n.toString().padLeft(3, '0');
    
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    final milliseconds = inMilliseconds.remainder(1000);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}.${threeDigits(milliseconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}.${threeDigits(milliseconds)}';
    }
  }
  
  /// Format duration as frames, based on a given frame rate
  String formattedAsFrames(int frameRate) {
    if (frameRate <= 0) {
      throw ArgumentError.value(frameRate, 'frameRate', 'Must be greater than 0');
    }
    final totalFrames = (inMilliseconds / (1000 / frameRate)).round();
    return '$totalFrames frames';
  }
  
  /// Convert duration to frame count
  int toFrames(int frameRate) {
    return (inMilliseconds / (1000 / frameRate)).round();
  }
  
  /// Convert duration to a timecode string (HH:MM:SS:FF)
  String toTimecode(int frameRate) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    
    // Calculate frames portion
    final totalSeconds = inMicroseconds / 1000000.0;
    final framePart = ((totalSeconds - totalSeconds.floor()) * frameRate).round();
    
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}:${twoDigits(framePart)}';
  }
}

/// Extensions for converting between frames and duration
extension FrameExtensions on int {
  /// Convert frame count to Duration based on frame rate
  Duration toDuration(int frameRate) {
    final milliseconds = (this * (1000 / frameRate)).round();
    return Duration(milliseconds: milliseconds);
  }
  
  /// Format frame count as a timecode string
  String toTimecode(int frameRate) {
    return toDuration(frameRate).toTimecode(frameRate);
  }
}
