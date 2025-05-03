import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'painters/video_frames_painter.dart';

/// Widget for rendering the content of a timeline clip based on its type
class ClipContentRenderer extends StatelessWidget {
  final ClipModel clip;
  final Color clipColor;
  final Color contrastColor;
  final FluentThemeData theme;

  const ClipContentRenderer({
    super.key,
    required this.clip,
    required this.clipColor,
    required this.contrastColor,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final contentColor = contrastColor.withAlpha(200);
    final contentBackgroundColor = clipColor.withAlpha(170);
    final fileName = clip.sourcePath.split('/').last;
    final fileNameNoExt =
        fileName.contains('.')
            ? fileName.substring(0, fileName.lastIndexOf('.'))
            : fileName;
    const double fixedClipHeight = 65.0;

    switch (clip.type) {
      case ClipType.video:
      default:
        return SizedBox(
          height: fixedClipHeight,
          child: Stack(
            children: [
              Container(
                height: fixedClipHeight,
                decoration: BoxDecoration(
                  color: contentBackgroundColor,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      clipColor.withAlpha(170),
                      clipColor.withAlpha(140),
                    ],
                  ),
                ),
              ),
              CustomPaint(
                painter: VideoFramesPainter(color: contentColor.withAlpha(30)),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.video, size: 16, color: contentColor),
                    if (clip.durationFrames > 20)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          fileNameNoExt,
                          style: theme.typography.caption?.copyWith(
                            color: contentColor,
                            fontSize: 8,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}
