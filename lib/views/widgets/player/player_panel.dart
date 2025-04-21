import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

class PlayerPanel extends StatelessWidget with WatchItMixin {
  const PlayerPanel({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    final currentVideoUrl = watchValue(
      (EditorViewModel vm) => vm.currentPreviewVideoUrlNotifier,
    );
    logDebug("PlayerPanel Received URL: $currentVideoUrl", 'PlayerPanel');
    const double opacity = 1.0;

    if (currentVideoUrl == null || currentVideoUrl.isEmpty) {
      logDebug("PlayerPanel: No video URL, showing fallback text.", 'PlayerPanel');
      return Container(
        color: const Color(0xFF333333),
        child: const Center(
          child: Text(
            'No media loaded',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final playerFuture = watchFuture(
      (VideoPlayerManager m) => m.getOrCreatePlayerController(currentVideoUrl),
      initialValue: null, // Assuming null works or PlayerManager handles default
    );

     logDebug(
       "PlayerPanel watchFuture [$currentVideoUrl]: State=${playerFuture.connectionState}",
       'PlayerPanel',
     );
     if (playerFuture.hasError) {
        logError(
           "PlayerPanel watchFuture [$currentVideoUrl]: ERROR=${playerFuture.error}",
           playerFuture.error,
           playerFuture.stackTrace,
           'PlayerPanel',
        );
     }
      if (playerFuture.hasData && playerFuture.data != null) {
         final controller = playerFuture.data!.$1;
         logDebug(
           "PlayerPanel watchFuture [$currentVideoUrl]: Data received. Controller initialized: ${controller.value.isInitialized}",
           'PlayerPanel',
         );
      }

    return Container(
      color: const Color(0xFF333333),
      child: _buildContent(playerFuture, opacity, currentVideoUrl),
    );
  }

  // Helper method to build the content based on playerFuture state
  Widget _buildContent(
    AsyncSnapshot<(VideoPlayerController, bool)?> playerFuture,
    double opacity,
    String? currentVideoUrl,
  ) {
    if (playerFuture.connectionState == ConnectionState.waiting || playerFuture.data == null) {
      return const Center(
        child: ProgressRing(
          activeColor: Colors.white,
        ),
      );
    } else if (playerFuture.hasError) {
      logError("PlayerPanel watchFuture Error: ${playerFuture.error}", null, null, 'PlayerPanel');
      return Center(
        child: Icon(
          FluentIcons.error,
          color: Colors.red.withValues(alpha: opacity),
          size: 24,
        ),
      );
    } else if (playerFuture.hasData) {
      final controller = playerFuture.data!.$1;
      if (controller.value.isInitialized) {
        return Column(
          children: [
            Expanded(
              child: VideoPlayerWidget(
                opacity: opacity,
                controller: controller,
              ),
            ),
            _PlayerControls(controller: controller),
          ],
        );
      } else {
        logDebug("PlayerPanel: Controller received but not yet initialized. Showing spinner.", 'PlayerPanel');
        return const Center(
          child: ProgressRing(
            activeColor: Colors.white,
          ),
        );
      }
    } else {
      logWarning(
        "PlayerPanel watchFuture [$currentVideoUrl]: Snapshot has no data and no error. State: ${playerFuture.connectionState}. Showing fallback help icon.",
        'PlayerPanel',
      );
      return Center(
        child: Icon(
          FluentIcons.help,
          color: Colors.orange.withValues(alpha: opacity),
          size: 24,
        ),
      );
    }
  }
}

// New private widget for player controls using WatchItMixin
class _PlayerControls extends StatelessWidget with WatchItMixin {
  final VideoPlayerController controller;

  const _PlayerControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Watch the controller directly. This widget will rebuild when the controller notifies.
    watch(controller); 
    
    // Access the state needed for the UI (e.g., isPlaying)
    final isPlaying = controller.value.isPlaying;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            isPlaying ? FluentIcons.pause : FluentIcons.play,
            color: Colors.white,
          ),
          onPressed: () {
            if (isPlaying) {
              controller.pause();
            } else {
              controller.play();
            }
          },
        ),
        IconButton(
          icon: const Icon(
            FluentIcons.rewind,
            color: Colors.white,
          ),
          onPressed: () {
            controller.seekTo(const Duration(seconds: 0));
          },
        ),
        // TODO: Add more controls like volume, seek bar, etc.
      ],
    );
  }
} 