import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/persistence/database/app_database.dart'; // Import Track
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

    // Watch tracks notifier from ProjectService
    final tracksNotifier = projectService.currentProjectTracksNotifier; // Correct: Access directly from service instance

    // Scroll controllers
    final trackLabelScrollController = timelineViewModel.trackLabelScrollController;
    final trackContentScrollController = timelineViewModel.trackContentScrollController;

    // Determine track count differently - maybe from a dedicated track list in a ViewModel
    // For now, let's derive it from unique track IDs present in the clips
    final uniqueTrackIds = clips.map((clip) => clip.trackId).toSet();
    final trackCount = uniqueTrackIds.isNotEmpty ? uniqueTrackIds.length : 1; // Default to 1 track if no clips
    // It's better to get tracks from a dedicated source (e.g., ProjectService or TrackDao)

    const double trackHeaderWidth = 100.0; // Placeholder width, remove LayoutService dependency

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
                  child: ValueListenableBuilder<List<Track>>( // Wrap with ValueListenableBuilder
                    valueListenable: tracksNotifier, // Listen to the notifier
                    builder: (context, tracks, _) { // Use the actual list value
                      return ListView.builder(
                        controller: trackLabelScrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: tracks.length + 1, // Use tracks.length
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return const SizedBox(height: 25);
                          }
                          final track = tracks[index - 1]; // Use tracks[index-1]
                          // Use a Row to place the delete button next to the label
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0), // Add some padding
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
                                  width: 20, // Constrain button width
                                  height: 20, // Constrain button height
                                  child: IconButton(
                                    icon: const Icon(FluentIcons.delete, size: 12),
                                    onPressed: () {
                                      projectService.removeTrack(track.id);
                                    },
                                    style: ButtonStyle(padding: ButtonState.all(EdgeInsets.zero)), // Remove default padding
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                  ),
                ),

                // Timeline tracks - Takes remaining space
                Expanded(
                  child: LayoutBuilder(
                    // Wrap with LayoutBuilder
                    builder: (context, constraints) {
                      // Calculate content width based on total frames and zoom
                      const double framePixelWidth = 5.0;
                      final double contentWidth =
                          totalFrames * zoom * framePixelWidth;

                      // Calculate minimum width needed for the scrollable area
                      final double minScrollWidth = math.max(
                        constraints.maxWidth, // Width of the viewport
                        contentWidth, // Width required by all frames
                      );

                      return Stack(
                        children: [
                          // Scrollable tracks area
                          Positioned.fill(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              // controller: ScrollController(), // Consider adding if programmatic scroll is needed
                              child: SizedBox(
                                // Set width to ensure it fills viewport or content, whichever is larger
                                width: minScrollWidth,
                                child: Column(
                                  children: [
                                    // Time ruler - Pass available width
                                    TimeRuler(
                                      zoom: zoom,
                                      currentFrame: currentFrame,
                                      availableWidth:
                                          constraints
                                              .maxWidth, // Pass viewport width
                                    ),

                                    // Tracks container - Use ListView.builder and ValueListenableBuilder
                                    Expanded(
                                      child: ValueListenableBuilder<List<Track>>( // Wrap with ValueListenableBuilder
                                        valueListenable: tracksNotifier, // Listen to the notifier
                                        builder: (context, tracks, _) {
                                          return ListView.builder(
                                            controller:
                                                trackContentScrollController, // Use content controller
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ), // Consistent padding
                                            itemCount: tracks.length, // Match track count
                                            itemBuilder: (context, index) {
                                              final track = tracks[index];
                                              // Filter clips for this specific track (using track.id)
                                              // TODO: Update Clip model/logic to include trackId
                                             final trackClips = clips.where((clip) => clip.trackId == track.id).toList();

                                              return TimelineTrack(
                                                trackIndex: index, // Keep trackIndex for layout/clip assignment for now
                                                clips: trackClips, // Pass filtered clips
                                              );
                                            },
                                          );
                                        }
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Current frame indicator (playhead)
                          Positioned(
                            top:
                                25, // Adjust top position to be below the ruler (ruler height is 25)
                            bottom: 0,
                            // Calculate position based on frame and zoom
                            left:
                                currentFrame *
                                zoom *
                                framePixelWidth, // Use constant
                            width: 2,
                            child: Container(
                              // Use theme accent color for the playhead
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
