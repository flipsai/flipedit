import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/views/widgets/preview/composite_preview_panel.dart';

/// PreviewPanel displays the current timeline frame's video(s).
/// This is now a wrapper around CompositePreviewPanel which combines videos into a single player.
class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const CompositePreviewPanel();
  }
}
