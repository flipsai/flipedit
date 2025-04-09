import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerController controller;
  final double opacity;
  final VoidCallback? onTap;

  const VideoPlayerWidget({
    super.key,
    required this.controller,
    this.opacity = 1.0,
    this.onTap,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, VideoPlayerValue value, child) {
        return GestureDetector(
          onTap: widget.onTap ?? () {
            if (value.isPlaying) {
              widget.controller.pause();
            } else {
              widget.controller.play();
            }
          },
          child: Opacity(
            opacity: widget.opacity,
            child: Container(
              color: Colors.black,
              child: Center(
                child: value.isInitialized
                    ? AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(widget.controller),
                      )
                    : const CircularProgressIndicator(
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
} 