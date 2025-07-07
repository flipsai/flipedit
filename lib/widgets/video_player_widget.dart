import 'package:flutter/material.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/video_player_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatefulWidget with WatchItStatefulWidgetMixin {
  final String leftVideoPath;
  final String rightVideoPath;

  const VideoPlayerWidget({
    super.key,
    required this.leftVideoPath,
    required this.rightVideoPath,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final VideoPlayerViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VideoPlayerViewModel(
      leftVideoPath: widget.leftVideoPath,
      rightVideoPath: widget.rightVideoPath,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _viewModel.errorMessageNotifier,
      builder: (context, errorMessage, _) {
        if (errorMessage != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: $errorMessage'),
              ],
            ),
          );
        }

        return ValueListenableBuilder<int?>(
          valueListenable: _viewModel.textureIdNotifier,
          builder: (context, textureId, __) {
            if (textureId == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // Get the video player service using watch_it
            final videoPlayerService = di<VideoPlayerService>();
            
            return Column(
              children: [
                Expanded(
                  child: Texture(textureId: textureId),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: videoPlayerService.isPlayingNotifier,
                      builder: (context, isPlaying, child) {
                        return IconButton(
                          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: _viewModel.togglePlayPause,
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    // Display position information
                    ValueListenableBuilder<double>(
                      valueListenable: videoPlayerService.positionSecondsNotifier,
                      builder: (context, position, child) {
                        final minutes = (position ~/ 60).toString().padLeft(2, '0');
                        final seconds = (position % 60).toInt().toString().padLeft(2, '0');
                        return Text(
                          '$minutes:$seconds',
                          style: Theme.of(context).textTheme.bodyMedium,
                        );
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
