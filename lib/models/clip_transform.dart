class ClipTransform {
  final double x;
  final double y;
  final double width;
  final double height;

  const ClipTransform({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  ClipTransform copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return ClipTransform(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  String toString() {
    return 'ClipTransform(x: $x, y: $y, width: $width, height: $height)';
  }
}