import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatelessWidget with WatchItMixin {
  final double opacity;
  final VoidCallback? onTap;

  const VideoPlayerWidget({super.key, this.opacity = 1.0, this.onTap});

  @override
  Widget build(BuildContext context) {
    final controller = watchValue(
      (TimelineViewModel vm) => vm.videoPlayerControllerNotifier,
    );

    if (controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('No video loaded', style: TextStyle(color: Colors.white)),
        ),
      );
    }

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
