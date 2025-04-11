import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatelessWidget {
  final double opacity;
  final VoidCallback? onTap;
  final VideoPlayerController controller;

  const VideoPlayerWidget({
    super.key, 
    this.opacity = 1.0, 
    this.onTap,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, VideoPlayerValue value, child) {
        return GestureDetector(
          onTap: onTap,
          child: Opacity(
            opacity: opacity,
            child: Container(
              color: Colors.black,
              child: Center(
                child:
                    value.isInitialized
                        ? AspectRatio(
                          aspectRatio: value.aspectRatio,
                          child: VideoPlayer(controller),
                        )
                        : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
        );
      },
    );
  }
}
