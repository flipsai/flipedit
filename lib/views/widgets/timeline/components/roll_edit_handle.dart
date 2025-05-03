import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart'; // Needed for performRollEdit
// Removed RollEditCommand import - command is created in ViewModel now
// Removed watch_it import - VM is passed directly

// Renamed from _RollEditHandle
class RollEditHandle extends StatefulWidget {
  final int leftClipId;
  final int rightClipId;
  final int initialFrame;
  final double zoom;
  final TimelineViewModel viewModel; // Added viewModel parameter

  const RollEditHandle({
    super.key, // Added super.key
    required this.leftClipId,
    required this.rightClipId,
    required this.initialFrame,
    required this.zoom,
    required this.viewModel, // Added viewModel parameter
  });

  @override
  State<RollEditHandle> createState() => _RollEditHandleState();
}

class _RollEditHandleState extends State<RollEditHandle> {
  double _startX = 0;
  int _startFrame = 0;
  int _initialFrame = 0;

  @override
  void initState() {
    super.initState();
    _startFrame = widget.initialFrame;
    _initialFrame = widget.initialFrame;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _startX = details.globalPosition.dx;
        _startFrame = _initialFrame;
      },
      onHorizontalDragUpdate: (details) async {
        final pixelsPerFrame = 5.0 * widget.zoom;
        final frameDelta =
            ((details.globalPosition.dx - _startX) / pixelsPerFrame).round();
        final newBoundary = _startFrame + frameDelta;

        // Removed direct command creation and execution
        // final timelineVm = di<TimelineViewModel>();
        // final cmd = RollEditCommand(...);
        // timelineVm.runCommand(cmd);

        // Call the new ViewModel method (to be created)
        widget.viewModel.performRollEdit(
          leftClipId: widget.leftClipId,
          rightClipId: widget.rightClipId,
          newBoundaryFrame: newBoundary,
        );
      },
      onHorizontalDragEnd: (_) {
        _startX = 0;
        _startFrame = widget.initialFrame;
      },
      onHorizontalDragCancel: () {
        _startX = 0;
        _startFrame = widget.initialFrame;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          decoration: BoxDecoration(
            color: theme.accentColor.normal.withAlpha(70),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.accentColor.normal, width: 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Icon(
              FluentIcons.a_a_d_logo,
              size: 14,
              color: theme.accentColor.darker,
            ),
          ),
        ),
      ),
    );
  }
}
