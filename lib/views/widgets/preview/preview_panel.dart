import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart'; // Need WatchItMixin and watch functions

// Use StatelessWidget with WatchItMixin for reactive rebuilds
class PreviewPanel extends StatelessWidget with WatchItMixin {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {

    final aspectRatio = 0.0;

    Widget content;
      content = const Center(
        child: Text(
          'No video at current playback position',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
  

    // The main container and AspectRatio structure
    return Container(
      color: const Color(0xFF546E7A), // Background color
      child: Center(
        child: AspectRatio(
          aspectRatio: (aspectRatio.isFinite && aspectRatio > 0) ? aspectRatio : 16 / 9,
          child: content,
        ),
      ),
    );
  }
}