import 'package:flutter/material.dart';
import 'package:flipedit/services/video_player_service.dart';
import 'package:flipedit/viewmodels/video_player_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatefulWidget with WatchItStatefulWidgetMixin {
  const VideoPlayerWidget({
    super.key,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final VideoPlayerViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VideoPlayerViewModel();
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

            return Texture(textureId: textureId);
          },
        );
      },
    );
  }
}
