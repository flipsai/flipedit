import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

/// A ruler widget that displays frame numbers and tick marks for the timeline
class TimeRuler extends StatelessWidget with WatchItMixin {
  final double zoom;
  final int currentFrame;

  const TimeRuler({
    super.key,
    required this.zoom,
    required this.currentFrame,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    const double frameWidth = 5.0;
    const int framesPerMajorTick = 30;
    const int framesPerMinorTick = 5;

    return Container(
      height: 25,
      color: theme.resources.subtleFillColorSecondary,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: (totalFrames / framesPerMinorTick).ceil() + 1,
        itemBuilder: (context, index) {
          final frameNumber = index * framesPerMinorTick;
          final isMajorTick = frameNumber % framesPerMajorTick == 0;
          final tickHeight = isMajorTick ? 10.0 : 5.0;
          final tickWidth = frameWidth * framesPerMinorTick * zoom;

          return Container(
            width: tickWidth,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: theme.resources.controlStrokeColorDefault,
                ),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    height: tickHeight,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
                if (isMajorTick)
                  Positioned(
                    left: 3,
                    top: 0,
                    child: Text(
                      frameNumber.toString(),
                      style: theme.typography.caption?.copyWith(
                        fontSize: 10,
                        color: theme.resources.textFillColorSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
} 