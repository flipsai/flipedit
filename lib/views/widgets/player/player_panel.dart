import 'package:fluent_ui/fluent_ui.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

class PlayerPanel extends StatelessWidget with WatchItMixin {
  const PlayerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    return Container(
      color: const Color(0xFF333333),
      child: const Center(
        child: Text('No media loaded', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
