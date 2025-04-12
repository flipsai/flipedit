import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

class PreviewPanel extends StatelessWidget with WatchItMixin {
  const PreviewPanel({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final editorViewModel = di<EditorViewModel>();
    final playerManager = di<VideoPlayerManager>();

    print("[PreviewPanel.build] Rebuilding...");

    final currentVideoUrl = watchValue(
      (EditorViewModel vm) => vm.currentPreviewVideoUrlNotifier,
    );
    print("[PreviewPanel.build] Received URL: $currentVideoUrl");
    const double opacity = 1.0;

    if (currentVideoUrl == null || currentVideoUrl.isEmpty) {
      print("[PreviewPanel.build] No video URL, showing fallback text.");
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

    return Container(
      color: const Color(0xFF546E7A), // FluentUI equivalent of blueGrey
      child: FutureBuilder<(VideoPlayerController, bool)>(
        future: playerManager.getOrCreatePlayerController(currentVideoUrl),
        builder: (context, snapshot) {
          print(
            "PreviewPanel FutureBuilder [$currentVideoUrl]: State=${snapshot.connectionState}",
          );
          if (snapshot.hasError) {
            print(
              "PreviewPanel FutureBuilder [$currentVideoUrl]: ERROR=${snapshot.error}",
            );
          }
          if (snapshot.hasData) {
            final controller = snapshot.data!.$1;
            print(
              "PreviewPanel FutureBuilder [$currentVideoUrl]: Data received. Controller initialized: ${controller.value.isInitialized}",
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: ProgressRing(
                activeColor: Colors.white,
              ),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Icon(
                FluentIcons.error,
                color: Colors.red.withOpacity(opacity),
                size: 24,
              ),
            );
          } else if (snapshot.hasData) {
            final controller = snapshot.data!.$1;
            if (controller.value.isInitialized) {
              print("[PreviewPanel.build] Controller is initialized. Passing to VideoPlayerWidget.");
              return VideoPlayerWidget(
                opacity: opacity,
                controller: controller,
              );
            } else {
              print("[PreviewPanel.build] Controller received but not yet initialized. Showing spinner.");
              return const Center(
                child: ProgressRing(
                  activeColor: Colors.white,
                ),
              );
            }
          } else {
            print(
              "PreviewPanel FutureBuilder [$currentVideoUrl]: Snapshot has no data and no error. State: ${snapshot.connectionState}. Showing fallback error icon.",
            );
            return Center(
              child: Icon(
                FluentIcons.help,
                color: Colors.orange.withOpacity(opacity),
                size: 24,
              ),
            );
          }
        },
      ),
    );
  }
}