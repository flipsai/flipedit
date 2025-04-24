import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/services/project_database_service.dart'; // Replace ProjectService import
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math; // Add math import for max function
import 'package:flipedit/utils/logger.dart'; // Import for logging functions
import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'dart:developer' as developer; // Import for developer logging

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatelessWidget with WatchItMixin {
    const Timeline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Use watch_it to get ViewModels and Services
    final timelineViewModel = di<TimelineViewModel>();
    final databaseService = di<ProjectDatabaseService>(); // Get ProjectDatabaseService

    // Watch properties from TimelineViewModel
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final currentFrame = watchValue(
      (TimelineViewModel vm) => vm.currentFrameNotifier,
    );
    final zoom = watchValue((TimelineViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue(
      (TimelineViewModel vm) => vm.totalFramesNotifier,
    );
    final trackLabelWidth = watchValue(
      (TimelineViewModel vm) => vm.trackLabelWidthNotifier,
    );

    // Watch tracks list from the DatabaseService
    final tracks = watchValue(
      (ProjectDatabaseService ps) => ps.tracksNotifier,
    );
    
    // Log clips for debugging
    if (clips.isNotEmpty) {
      logDebug(
        'Timeline',
        '🧩 Timeline build with ${clips.length} clips, ${tracks.length} tracks, totalFrames: $totalFrames'
      );
    }
    
    // Removed the addPostFrameCallback that forced refresh, as it caused loops.
    // Relying on database streams and initial load logic in ViewModel now.

    // Only horizontal scroll controller needed from ViewModel now
    final trackContentHorizontalScrollController =
        timelineViewModel.trackContentHorizontalScrollController;

    const double timeRulerHeight = 25.0;
    const double trackItemSpacing = 4.0;

    return Container(
      color: theme.resources.cardBackgroundFillColorDefault,
      child: Column(
        children: [
          // Now uses WatchingWidget, no params needed
          const TimelineControls(),

          // Unified Timeline Content Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double framePixelWidth = 5.0;
                final double contentWidth =
                    totalFrames * zoom * framePixelWidth;
                final double totalScrollableWidth = math.max(
                  constraints.maxWidth,
                  contentWidth + trackLabelWidth,
                );
                final double playheadPosition =
                    currentFrame * zoom * framePixelWidth;

                return ClipRect(
                  // Clip horizontal overflow
                  child: Stack(
                    children: [
                      // Horizontally Scrollable Container for Ruler and All Tracks
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: trackContentHorizontalScrollController,
                        child: SizedBox(
                          width: totalScrollableWidth, // Define scrollable width
                          // Inner Stack: Allows positioning Playhead over the Column
                          child: Stack(
                            clipBehavior: Clip.none, // Allow playhead marker to draw outside bounds
                            children: [
                              // Column containing TimeRuler and Tracks List
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // TimeRuler spanning the scrollable width (minus label offset)
                                  Padding(
                                    padding: EdgeInsets.only(left: trackLabelWidth),
                                    child: SizedBox(
                                      height: timeRulerHeight,
                                      width: totalScrollableWidth - trackLabelWidth,
                                      child: TimeRuler(
                                        zoom: zoom,
                                        availableWidth: math.max(
                                          0,
                                          constraints.maxWidth - trackLabelWidth,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Vertically arranged Tracks (within DragTarget for empty drop)
                                  Expanded(
                                    child: DragTarget<ClipModel>(
                                      onWillAcceptWithDetails: (details) {
                                        final accept = tracks.isEmpty;
                                        developer.log('Timeline Area onWillAccept: $accept (tracks: ${tracks.length})', name: 'Timeline');
                                        return accept;
                                      },
                                      onAcceptWithDetails: (details) async {
                                        developer.log('Timeline Area onAccept: Drop accepted (tracks were empty)', name: 'Timeline');
                                        final draggedClip = details.data;
                                        // ... (rest of accept logic for empty drop) ...
                                         // 1. Create a new track
                                        final newTrackId = await databaseService.addTrack(
                                          name: 'Track 1',
                                          type: draggedClip.type.name // Pass the clip type as the track type
                                        );
                                        if (newTrackId == null) {
                                           developer.log('❌ Failed to create new track', name: 'Timeline');
                                           return;
                                        }
                                        developer.log('✅ New track created with ID: $newTrackId', name: 'Timeline');

                                        // 2. Calculate drop position
                                        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                                        if (renderBox == null) {
                                           developer.log('❌ Error: renderBox is null in Timeline Area onAccept', name: 'Timeline');
                                           return;
                                        }
                                        final localPosition = renderBox.globalToLocal(details.offset - Offset(0, timeRulerHeight + trackItemSpacing));
                                        final scrollOffsetX = timelineViewModel.trackContentHorizontalScrollController.offset;
                                        final posX = localPosition.dx - trackLabelWidth;
                                        final calculatedFramePosition = ((posX + scrollOffsetX) / (5.0 * zoom)).floor();
                                        final framePosition = math.max(0, calculatedFramePosition);
                                        final framePositionMs = framePosition * (1000 / 30);

                                        developer.log(
                                          '📏 Drop Position (Timeline Area): local=$localPosition, scroll=$scrollOffsetX, frame=$framePosition, ms=$framePositionMs',
                                          name: 'Timeline'
                                        );

                                        // 3. Add the clip
                                        await timelineViewModel.placeClipOnTrack(
                                          trackId: newTrackId,
                                          type: draggedClip.type,
                                          sourcePath: draggedClip.sourcePath,
                                          startTimeOnTrackMs: framePositionMs.toInt(),
                                          startTimeInSourceMs: draggedClip.startTimeInSourceMs,
                                          endTimeInSourceMs: draggedClip.endTimeInSourceMs,
                                        );
                                        developer.log('✅ Clip "${draggedClip.name}" added to new track $newTrackId at frame $framePosition', name: 'Timeline');
                                      },
                                      builder: (context, candidateData, rejectedData) {
                                        // Build the list of tracks inside the DragTarget builder
                                        // Apply padding here for the label space
                                        // Removed Padding wrapper around ListView
                                        return ListView.builder(
                                            padding: const EdgeInsets.symmetric(vertical: trackItemSpacing),
                                            itemCount: tracks.length,
                                            itemBuilder: (context, index) {
                                              final track = tracks[index];
                                              // TimelineTrack itself handles internal label/content split
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: trackItemSpacing),
                                                child: TimelineTrack(
                                                  track: track,
                                                  onDelete: () => databaseService.deleteTrack(track.id),
                                                  trackLabelWidth: trackLabelWidth, // Pass width
                                                ),
                                              );
                                            },
                                          );
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // --- Playhead (Simple Container, Positioned within this Inner Stack) ---
                              Builder(
                                builder: (context) {
                                   // Define playhead visual properties
                                  const double playheadLineWidth = 2.0;
                                  final Color playheadColor = theme.accentColor.normal; // Or theme.accentColor.darker, etc.

                                  // Calculate position relative to the start of the scrollable content area (time 0)
                                  // playheadPosition already represents this (currentFrame * zoom * framePixelWidth)
                                  final double playheadPosInContent = playheadPosition;

                                  // The left offset is calculated from the start of the scrollable content (0)
                                  // We need to add the trackLabelWidth because the playhead visually aligns
                                  // with the track area, which starts *after* the labels.
                                  // Subtract half the line width to center the line visually on the frame's start pixel.
                                  double playheadLeftOffset = trackLabelWidth + playheadPosInContent - (playheadLineWidth / 2.0);

                                  // Clamp to prevent visually going under the label area if scrolled fully left
                                  playheadLeftOffset = playheadLeftOffset.clamp(trackLabelWidth, double.infinity);

                                  return Positioned(
                                    top: 0,
                                    bottom: 0,
                                    left: playheadLeftOffset,
                                    width: playheadLineWidth, // Use the defined line width
                                    child: Container(color: playheadColor), // Simple container as the playhead line
                                  );
                                }
                              ),

                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: trackLabelWidth - 3, // Position based on label width
                                width: 6,
                                child: GestureDetector(
                                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                                    // Update width via ViewModel
                                    timelineViewModel.updateTrackLabelWidth(
                                      trackLabelWidth + details.delta.dx,
                                    );
                                  },
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.resizeLeftRight,
                                    child: Container(
                                      color: theme.resources.subtleFillColorSecondary,
                                      alignment: Alignment.center,
                                      child: Container(
                                        width: 1.5,
                                        color: theme.resources.controlStrokeColorDefault,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
