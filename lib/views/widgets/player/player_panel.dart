import 'package:flipedit/views/widgets/player/player_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
// import 'package:flipedit/viewmodels/preview_viewmodel.dart'; // No longer used
import 'package:flipedit/viewmodels/player/native_player_viewmodel.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {

  @override
  void initState() {
    super.initState();
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    return ValueListenableBuilder<int>(
      valueListenable: di.get<TimelineNavigationViewModel>().totalFramesNotifier,
      builder: (context, totalFrames, _) {
        final bool hasActiveProject = totalFrames > 0;
        Widget content;

        if (!hasActiveProject) {
          content = const Center(
            child: Text('No media loaded', style: TextStyle(color: Colors.white)),
          );
        } else {
          content = Container(
            color: const Color(0xFF333333),
            child: Stack(
              children: [
              PlayerTest()
              ],
            ),
          );
        }

        return material.Material(
          color: const Color(0xFF333333),
          child: content,
        );
      },
    );
  }
}

// Simple ChangeNotifierProvider for the native player viewmodel
class ChangeNotifierProvider<T extends ChangeNotifier> extends InheritedNotifier<T> {
  const ChangeNotifierProvider({
    super.key,
    required T notifier,
    required super.child,
  }) : super(notifier: notifier);
}
