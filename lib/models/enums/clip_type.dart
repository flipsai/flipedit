enum ClipType {
  video,
  audio,
  image,
  text,
  effect;
  
  // Return the display name of the clip type
  String get displayName {
    switch (this) {
      case ClipType.video:
        return 'Video';
      case ClipType.audio:
        return 'Audio';
      case ClipType.image:
        return 'Image';
      case ClipType.text:
        return 'Text';
      case ClipType.effect:
        return 'Effect';
    }
  }
}
