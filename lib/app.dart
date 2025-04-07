import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/views/screens/editor_screen.dart';
import 'package:flipedit/views/screens/welcome_screen.dart';
import 'package:watch_it/watch_it.dart' hide di;

class FlipEditApp extends StatelessWidget with WatchItMixin {
  FlipEditApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appInitialized = watchPropertyValue((AppViewModel vm) => vm.isInitialized);
    
    return FluentApp(
      title: 'FlipEdit',
      theme: FluentThemeData(
        accentColor: Colors.blue,
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
        focusTheme: FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      darkTheme: FluentThemeData(
        accentColor: Colors.blue,
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
        focusTheme: FocusThemeData(
          glowFactor: 4.0,
        ),
      ),
      home: appInitialized ? const EditorScreen() : const WelcomeScreen(),
    );
  }
}
