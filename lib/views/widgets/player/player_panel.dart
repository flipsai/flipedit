import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/utils/logger.dart';

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
    return Container();
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
