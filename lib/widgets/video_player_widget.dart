import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flipedit/viewmodels/video_player_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip_transform.dart';
import 'package:flipedit/widgets/player/clip_transform_overlay.dart';
import 'package:flipedit/utils/logger.dart';
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
  late final TimelineViewModel _timelineViewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = VideoPlayerViewModel();
    _timelineViewModel = di<TimelineViewModel>();
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
          // Log error for debugging
          logError('VideoPlayerWidget', 'Timeline player error: $errorMessage');
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: $errorMessage'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Copy error to clipboard for easy sharing
                    Clipboard.setData(ClipboardData(text: errorMessage));
                  },
                  child: const Text('Copy Error'),
                ),
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

            return LayoutBuilder(
              builder: (context, constraints) {
                final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
                const videoSize = Size(1920, 1080); // Default video canvas size
                
                return Stack(
                  children: [
                    // Video texture
                    Texture(textureId: textureId),
                    
                    // Transform overlay for selected clip
                    ValueListenableBuilder<int?>(
                      valueListenable: _timelineViewModel.selectedClipIdNotifier,
                      builder: (context, selectedClipId, _) {
                        if (selectedClipId == null) return const SizedBox.shrink();
                        
                        final selectedClip = _timelineViewModel.clips
                            .where((clip) => clip.databaseId == selectedClipId)
                            .firstOrNull;
                        
                        if (selectedClip == null) return const SizedBox.shrink();
                        
                        return ClipTransformOverlay(
                          clip: selectedClip,
                          videoSize: videoSize,
                          screenSize: screenSize,
                          onTransformChanged: (transform) {
                            _updateClipTransform(selectedClipId, transform);
                          },
                          onTransformStart: () {
                            logDebug('Transform started for clip $selectedClipId', 'VideoPlayerWidget');
                          },
                          onTransformEnd: () {
                            logDebug('Transform ended for clip $selectedClipId', 'VideoPlayerWidget');
                          },
                          onDeselect: () {
                            _timelineViewModel.selectedClipId = null;
                            logDebug('Deselected clip $selectedClipId', 'VideoPlayerWidget');
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _updateClipTransform(int clipId, ClipTransform transform) {
    // Use the existing updateClipPreviewTransform method
    _timelineViewModel.updateClipPreviewTransform(
      clipId,
      transform.x,
      transform.y,
      transform.width,
      transform.height,
    );
  }
}
