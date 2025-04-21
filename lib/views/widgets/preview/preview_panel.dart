import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

class PreviewPanel extends StatelessWidget with WatchItMixin {
  const PreviewPanel({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding...");

    final currentVideoUrl = watchValue(
      (EditorViewModel vm) => vm.currentPreviewVideoUrlNotifier,
    );
    logDebug("Received URL: $currentVideoUrl");
    const double opacity = 1.0;

    if (currentVideoUrl == null || currentVideoUrl.isEmpty) {
      logDebug("No video URL, showing fallback text.");
      return Container(
        color: const Color(0xFF546E7A), // FluentUI equivalent of blueGrey
        child: Center(
          child: Text(
            'No video loaded or at current frame',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final playerFuture = watchFuture(
      (VideoPlayerManager m) => m.getOrCreatePlayerController(currentVideoUrl),
      // Provide a default value. The type needs to match the Future's result.
      // Using null for the controller and false for the bool initially.
      initialValue: null, 
    );

    logDebug(
      "PreviewPanel watchFuture [$currentVideoUrl]: State=${playerFuture.connectionState}",
    );
    if (playerFuture.hasError) {
       logError(
          "PreviewPanel watchFuture [$currentVideoUrl]: ERROR=${playerFuture.error}",
          playerFuture.error,
          playerFuture.stackTrace,
       );
    }
    if (playerFuture.hasData && playerFuture.data != null) {
       final controller = playerFuture.data!.$1;
       logDebug(
         "PreviewPanel watchFuture [$currentVideoUrl]: Data received. Controller initialized: ${controller.value.isInitialized}",
       );
    }

    return Container(
      color: const Color(0xFF546E7A), // FluentUI equivalent of blueGrey
      child: _buildContent(playerFuture, opacity, currentVideoUrl),
    );
  }

  // Helper method to build the content based on playerFuture state
  Widget _buildContent(AsyncSnapshot<(VideoPlayerController, bool)?> playerFuture, double opacity, String? currentVideoUrl) {
    if (playerFuture.connectionState == ConnectionState.waiting || playerFuture.data == null) {
      return const Center(
        child: ProgressRing(
          activeColor: Colors.white,
        ),
      );
    } else if (playerFuture.hasError) {
      return Center(
        child: Icon(
          FluentIcons.error,
          color: Colors.red.withOpacity(opacity),
          size: 24,
        ),
      );
    } else if (playerFuture.hasData) {
      final controller = playerFuture.data!.$1;
      if (controller.value.isInitialized) {
        logDebug("Controller is initialized. Passing to VideoPlayerWidget.");
        return VideoPlayerWidget(
          opacity: opacity,
          controller: controller,
        );
      } else {
        logDebug("Controller received but not yet initialized. Showing spinner.");
        return const Center(
          child: ProgressRing(
            activeColor: Colors.white,
          ),
        );
      }
    } else {
      logWarning(
        "PreviewPanel watchFuture [$currentVideoUrl]: Snapshot has no data and no error. State: ${playerFuture.connectionState}. Showing fallback help icon.",
      );
      return Center(
        child: Icon(
          FluentIcons.help,
          color: Colors.orange.withOpacity(opacity),
          size: 24,
        ),
      );
    }
  }
}