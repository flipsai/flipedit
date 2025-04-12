import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_service.dart'; // Import ProjectService
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/track_label.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math; // Add math import for max function

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatelessWidget with WatchItMixin {
  const Timeline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it to get ViewModels and Services
    final timelineViewModel = di<TimelineViewModel>();
    final projectService = di<ProjectService>(); // Get ProjectService

    // Watch properties from TimelineViewModel
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final currentFrame = watchValue((TimelineViewModel vm) => vm.currentFrameNotifier);
    final isPlaying = watchValue((TimelineViewModel vm) => vm.isPlayingNotifier);
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue((TimelineViewModel vm) => vm.totalFramesNotifier);

    // Watch tracks list directly from the ProjectService notifier
    final tracks = watchValue((ProjectService ps) => ps.currentProjectTracksNotifier);

    // Scroll controllers
    final trackLabelScrollController = timelineViewModel.trackLabelScrollController;
    final trackContentScrollController = timelineViewModel.trackContentScrollController;

    return Container(
      // Use a standard dark background from the theme resources
      color: theme.resources.cardBackgroundFillColorDefault,
      // Use theme subtle border color
      // border: Border(top: BorderSide(color: theme.resources.controlStrokeColorDefault)),
      child: Column(
        children: [
          // Now uses WatchingWidget, no params needed
          const TimelineControls(),

          // Timeline content
          Expanded(
            child: Row(
              children: [
                // Track labels - Fixed width
                Container(
                  width: 120,
                  color: theme.resources.subtleFillColorTransparent,
                  // Removed ValueListenableBuilder
                  child: ListView.builder(
                    controller: trackLabelScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tracks.length + 1, // Use watched tracks.length
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const SizedBox(height: 25);
                      }
                      final track = tracks[index - 1]; // Use watched tracks list
                      // Use a Row to place the delete button next to the label
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: TrackLabel(
                                label: track.name,
                                icon: track.type == 'video' ? FluentIcons.video : FluentIcons.music_in_collection,
                              ),
                            ),
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: IconButton(
                                icon: const Icon(FluentIcons.delete, size: 12),
                                onPressed: () {
                                  projectService.removeTrack(track.id);
                                },
                                style: ButtonStyle(padding: ButtonState.all(EdgeInsets.zero)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Timeline tracks - Takes remaining space
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double framePixelWidth = 5.0;
                      final double contentWidth = totalFrames * zoom * framePixelWidth;
                      final double minScrollWidth = math.max(constraints.maxWidth, contentWidth);

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: minScrollWidth,
                                child: Column(
                                  children: [
                                    TimeRuler(
                                      zoom: zoom,
                                      currentFrame: currentFrame,
                                      availableWidth: constraints.maxWidth,
                                    ),
                                    Expanded(
                                      // Removed ValueListenableBuilder
                                      child: ListView.builder(
                                        controller: trackContentScrollController,
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        itemCount: tracks.length, // Use watched tracks.length
                                        itemBuilder: (context, index) {
                                          final track = tracks[index]; // Use watched tracks list
                                          final trackClips = clips.where((clip) => clip.trackId == track.id).toList();
                                          return TimelineTrack(
                                            trackIndex: index, // Consider passing track.id directly if needed
                                            clips: trackClips,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 25,
                            bottom: 0,
                            left: currentFrame * zoom * framePixelWidth,
                            width: 2,
                            child: Container(
                              color: theme.accentColor.normal,
                            ),
                          ),
                        ],
                      );
                    },
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
