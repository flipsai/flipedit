import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/views/widgets/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

class PlayerPanel extends StatelessWidget with WatchItMixin {
  const PlayerPanel({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final editorViewModel = di<EditorViewModel>();
    final playerManager = di<VideoPlayerManager>();

    print("[PlayerPanel.build] Rebuilding...");

    final currentVideoUrl = watchValue(
      (EditorViewModel vm) => vm.currentPreviewVideoUrlNotifier,
    );
    print("[PlayerPanel.build] Received URL: $currentVideoUrl");
    const double opacity = 1.0;

    // Add playback controls
    Widget buildControls(VideoPlayerController controller) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              controller.value.isPlaying 
                ? FluentIcons.pause 
                : FluentIcons.play,
              color: Colors.white,
            ),
            onPressed: () {
              if (controller.value.isPlaying) {
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
        ],
      );
    }

    if (currentVideoUrl == null || currentVideoUrl.isEmpty) {
      print("[PlayerPanel.build] No video URL, showing fallback text.");
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

    return Container(
      color: const Color(0xFF333333),
      child: FutureBuilder<(VideoPlayerController, bool)>(
        future: playerManager.getOrCreatePlayerController(currentVideoUrl),
        builder: (context, snapshot) {
          print(
            "PlayerPanel FutureBuilder [$currentVideoUrl]: State=${snapshot.connectionState}",
          );
          
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
              return Column(
                children: [
                  Expanded(
                    child: VideoPlayerWidget(
                      opacity: opacity,
                      controller: controller,
                    ),
                  ),
                  buildControls(controller),
                ],
              );
            } else {
              return const Center(
                child: ProgressRing(
                  activeColor: Colors.white,
                ),
              );
            }
          } else {
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