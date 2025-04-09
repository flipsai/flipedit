import 'package:flutter/material.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:flipedit/views/widgets/video_player_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:watch_it/watch_it.dart';

class PreviewPanel extends StatelessWidget {
  final List<String> videoUrls;
  final List<double> opacities;

  const PreviewPanel({
    super.key,
    required this.videoUrls,
    required this.opacities,
  }) : assert(videoUrls.length == opacities.length);

  @override
  Widget build(BuildContext context) {
    final playerManager = di<VideoPlayerManager>();
    
    if (videoUrls.isEmpty) {
      return Container(
        color: Colors.blueGrey, 
        child: const Center(child: Text('No videos to display', style: TextStyle(color: Colors.white))), 
      );
    }

    return Container(
      color: Colors.blueGrey, 
      child: Stack(
        children: List.generate(videoUrls.length, (index) {
            final videoUrl = videoUrls[index];
            final opacity = opacities[index];

            return FutureBuilder<(VideoPlayerController, bool)>(
              future: playerManager.getOrCreatePlayerController(videoUrl),
              builder: (context, snapshot) {
                // --- DEBUG PRINTS START (Optional: update or remove) ---
                print("PreviewPanel FutureBuilder [$index: $videoUrl]: State=${snapshot.connectionState}");
                if (snapshot.hasError) {
                  print("PreviewPanel FutureBuilder [$index: $videoUrl]: ERROR=${snapshot.error}");
                }
                if (snapshot.hasData) {
                  // Data is now a VideoPlayerController
                  final controller = snapshot.data!.$1;
                  print("PreviewPanel FutureBuilder [$index: $videoUrl]: Data received. Controller initialized: ${controller.value.isInitialized}");
                }
                // --- DEBUG PRINTS END ---

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: Colors.white.withOpacity(0.5)));
                } else if (snapshot.hasError) {
                  return Center(
                    child: Icon(Icons.error_outline, color: Colors.redAccent.withOpacity(opacity)),
                  );
                } else if (snapshot.hasData) {
                  // Pass the controller to VideoPlayerWidget
                  final controller = snapshot.data!.$1;
                  // VideoPlayerWidget's internal ValueListenableBuilder handles the loading/initialized state
                  return VideoPlayerWidget(
                    controller: controller,
                    opacity: opacity, 
                  );
                } else {
                  // Should not happen
                   print("PreviewPanel FutureBuilder [$index: $videoUrl]: Snapshot has no data and no error, connection state is ${snapshot.connectionState}. Showing fallback.");
                  return Center(child: Icon(Icons.question_mark, color: Colors.orangeAccent.withOpacity(opacity)));
                }
              },
            );
          }
        ),
      ),
    );
  }
} 