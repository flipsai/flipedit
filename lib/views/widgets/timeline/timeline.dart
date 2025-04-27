import 'package:fluent_ui/fluent_ui.dart';
// Removed import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/components/time_ruler.dart';
import 'package:flipedit/views/widgets/timeline/components/timeline_controls.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math; // Add math import for max function
import 'package:flipedit/utils/logger.dart'; // Import for logging functions
import 'package:flipedit/models/clip.dart'; // Import ClipModel
import 'dart:developer' as developer; // Import for developer logging
import 'package:flipedit/views/widgets/timeline/components/timeline_playhead.dart';

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatefulWidget with WatchItStatefulWidgetMixin { // Mixin moved here
  // Parameters for snapping and aspect ratio lock removed - now handled by EditorViewModel

  const Timeline({
    super.key,
  });

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> { // Mixin removed here
  // Store the viewport width for use in the listener
  double _viewportWidth = 0;
  // Create and manage the scroll controller locally
  final ScrollController _scrollController = ScrollController();
  // Reference to the view model
  late TimelineViewModel _timelineViewModel;
  // Store the listener function to remove it in dispose
  VoidCallback? _scrollRequestListener;

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>();

    // Define the listener callback function
    _scrollRequestListener = () {
      final frame = _timelineViewModel.navigationService.scrollToFrameRequestNotifier.value;
      if (frame == null) return; // No request or already handled

      _handleScrollRequest(frame);
    };

    _timelineViewModel.navigationService.scrollToFrameRequestNotifier.addListener(_scrollRequestListener!);
  }

  void _handleScrollRequest(int frame) {
     if (!mounted || _viewportWidth <= 0 || !_scrollController.hasClients) {
        logWarning('Timeline', 'Scroll requested for frame $frame but widget/controller not ready.');
        return;
      }
      final trackLabelWidth = _timelineViewModel.trackLabelWidthNotifier.value;
      const double framePixelWidth = 5.0; // Matches build method
      final double scrollableViewportWidth = _viewportWidth - trackLabelWidth;
      if (scrollableViewportWidth <= 0) return; // Cannot calculate if viewport is too small

      // Calculate the target offset to scroll to
      final double unclampedTargetOffset = _timelineViewModel.calculateScrollOffsetForFrame(
        frame,
        _timelineViewModel.zoom, // Get zoom from ViewModel
      );
      final double maxOffset = _scrollController.position.maxScrollExtent;
      final double targetOffset = unclampedTargetOffset.clamp(0.0, maxOffset);

      logInfo('Timeline', 'Executing scroll to frame $frame (target: $targetOffset)');
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 150), // Consistent smooth duration
        curve: Curves.easeOut,
      );
  }


  @override
  void dispose() {
    // Remove the listener from the notifier
    if (_scrollRequestListener != null) {
      _timelineViewModel.navigationService.scrollToFrameRequestNotifier.removeListener(_scrollRequestListener!);
    }
    // Dispose the locally managed scroll controller
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Watch properties using watchItMixin helpers for StatefulWidgets
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

    // Watch tracks list from the TimelineViewModel
    final tracks = watchValue(
      (TimelineViewModel vm) => vm.tracksNotifierForView,
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

    // Use the stored scroll controller
    // final trackContentHorizontalScrollController = _scrollController; // Already have _scrollController

    const double timeRulerHeight = 25.0;
    const double trackItemSpacing = 4.0;

    return Container(
      color: theme.resources.cardBackgroundFillColorDefault,
      child: Column(
        children: [
          // TimelineControls no longer requires snapping/aspect ratio parameters
          TimelineControls(),

          // Unified Timeline Content Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const double framePixelWidth = 5.0;
                // Store the viewport width when LayoutBuilder provides it
                _viewportWidth = constraints.maxWidth;
                final double contentWidth =
                    totalFrames * zoom * framePixelWidth;
                final double totalScrollableWidth = math.max(
                  _viewportWidth, // Use stored/updated viewport width
                  contentWidth + trackLabelWidth,
                );
                final double playheadPosition =
                    currentFrame * zoom * framePixelWidth;

                return ClipRect(
                  // Clip horizontal overflow
                  child: Stack(
                    children: [
                      // Show TimeRuler at the top when no tracks exist
                      if (tracks.isEmpty)
                        SizedBox(
                          height: timeRulerHeight,
                          width: _viewportWidth,
                          child: TimeRuler(
                            zoom: zoom,
                            availableWidth: _viewportWidth,
                          ),
                        ),
                      
                      // Horizontally Scrollable Container for Ruler and All Tracks
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _scrollController, // Use stored controller
                        // Use the canScroll helper from ViewModel
                        physics: _timelineViewModel.canScroll ? ClampingScrollPhysics() : NeverScrollableScrollPhysics(),
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
                                  // Only show TimeRuler inside the scrollable view when tracks exist
                                  if (tracks.isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(left: trackLabelWidth),
                                    child: SizedBox(
                                      height: timeRulerHeight,
                                      width: totalScrollableWidth - trackLabelWidth, // Set to scrollable width
                                      child: TimeRuler(
                                        zoom: zoom,
                                        availableWidth: totalScrollableWidth - trackLabelWidth, // Pass scrollable width
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
                                        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                                        if (renderBox == null) {
                                          developer.log('❌ Error: renderBox is null in Timeline Area onAccept', name: 'Timeline');
                                          return;
                                        }
                                        final localPosition = renderBox.globalToLocal(details.offset - Offset(0, timeRulerHeight + trackItemSpacing));
                                        final scrollOffsetX = _scrollController.offset; // Use local controller
                                        final posX = localPosition.dx - trackLabelWidth;
                                        final calculatedFramePosition = ((posX + scrollOffsetX) / (5.0 * zoom)).floor();
                                        final framePosition = math.max(0, calculatedFramePosition);
                                        final framePositionMs = framePosition * (1000 / 30);

                                        developer.log(
                                          '📏 Drop Position (Timeline Area): local=$localPosition, scroll=$scrollOffsetX, frame=$framePosition, ms=$framePositionMs',
                                          name: 'Timeline'
                                        );

                                        // Use stored view model reference
                                        await _timelineViewModel.handleClipDropToEmptyTimeline(
                                          clip: draggedClip,
                                          startTimeOnTrackMs: framePositionMs.toInt(),
                                        );
                                        
                                        // After creating the track, select it if it's the first one
                                        final tracks = _timelineViewModel.tracksNotifierForView.value;
                                        if (tracks.isNotEmpty) {
                                          // Select the first track - it should be the one we just created
                                          _timelineViewModel.selectedTrackId = tracks.first.id;
                                          developer.log('✅ Selected newly created track ${tracks.first.id}', name: 'Timeline');
                                          
                                          // Also select the clip once it's created - find it using refreshClips
                                          Future.delayed(const Duration(milliseconds: 100), () {
                                            _timelineViewModel.refreshClips().then((_) {
                                              // Find the clip that was just added to this track
                                              final clips = _timelineViewModel.clips.where((c) => c.trackId == tracks.first.id).toList();
                                              if (clips.isNotEmpty) {
                                                _timelineViewModel.selectedClipId = clips.first.databaseId;
                                                developer.log('✅ Selected newly created clip ${clips.first.databaseId}', name: 'Timeline');
                                              }
                                            });
                                          });
                                        }
                                        
                                        developer.log('✅ Clip "${draggedClip.name}" added to new track at frame $framePosition', name: 'Timeline');
                                      },
                                      builder: (context, candidateData, rejectedData) {
                                        // Build the list of tracks inside the DragTarget builder
                                        
                                        // If no tracks and not dragging, show a message
                                        if (tracks.isEmpty && candidateData.isEmpty) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(FluentIcons.error, size: 24),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'No tracks in project',
                                                  style: theme.typography.bodyLarge,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Drag media here to create a track',
                                                  style: theme.typography.body?.copyWith(
                                                    color: theme.resources.textFillColorSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        
                                        // If tracks exist or we're showing drop preview, use ReorderableListView
                                        return ReorderableListView.builder(
                                          padding: const EdgeInsets.symmetric(vertical: trackItemSpacing),
                                          onReorder: (oldIndex, newIndex) async {
                                            // Avoid processing if indices are out of range
                                            if (oldIndex < 0 || oldIndex >= tracks.length || 
                                                newIndex < 0 || newIndex > tracks.length) {
                                              developer.log('Invalid track indices: $oldIndex -> $newIndex', name: 'Timeline');
                                              return;
                                            }
                                            
                                            // ReorderableListView will give us an index that accounts for
                                            // the item being removed and inserted, so we need to adjust.
                                            if (oldIndex < newIndex) {
                                              newIndex -= 1;
                                            }
                                            
                                            developer.log('Track reordering: $oldIndex -> $newIndex', name: 'Timeline');
                                            
                                            if (oldIndex != newIndex) {
                                              try {
                                                await _timelineViewModel.reorderTracks(oldIndex, newIndex);
                                              } catch (e) {
                                                developer.log('Error reordering tracks: $e', name: 'Timeline');
                                              }
                                            }
                                          },
                                          buildDefaultDragHandles: false, // Disable default drag handles
                                          itemCount: tracks.length,
                                          itemBuilder: (context, index) {
                                            final track = tracks[index];
                                            // TimelineTrack itself handles internal label/content split
                                            return Padding(
                                              key: ValueKey('track_${track.id}'), // Key for ReorderableListView
                                              padding: const EdgeInsets.only(bottom: trackItemSpacing),
                                              // Use AnimatedBuilder to pass down the current scroll offset reactively
                                              child: AnimatedBuilder(
                                                animation: _scrollController,
                                                builder: (context, child) {
                                                   return TimelineTrack(
                                                     key: ValueKey('timeline_track_${track.id}'), // Add unique key for the TimelineTrack itself
                                                     track: track,
                                                     // Call ViewModel method instead of direct service call
                                                     onDelete: () => _timelineViewModel.deleteTrack(track.id),
                                                     trackLabelWidth: trackLabelWidth, // Pass width
                                                     scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0.0, // Pass offset
                                                   );
                                                },
                                              )
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // --- Playhead (Dynamically Positioned) ---
                              // Only show the playhead when tracks exist
                              if (tracks.isNotEmpty)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                // Position based on currentFrame, zoom, and trackLabelWidth
                                left: trackLabelWidth + playheadPosition,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.allScroll,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onHorizontalDragUpdate: (DragUpdateDetails details) {
                                      final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                      final Offset origin = renderBox.localToGlobal(Offset.zero);
                                      final double localX = details.globalPosition.dx - origin.dx;
                                      // Use local controller reference
                                      final double scrollOffsetX = _scrollController.offset;
                                      final double pxPerFrame = framePixelWidth * zoom;
                                      double pointerRelX = (localX + scrollOffsetX - trackLabelWidth).clamp(0.0, double.infinity);
                                      // Calculate max allowed frame with a safety margin to prevent the playhead
                                      // from going too far to the right where it becomes hard to see or interact with
                                      final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : 0;
                                      final int newFrame = (pointerRelX / pxPerFrame).round().clamp(0, maxAllowedFrame);
                                      _timelineViewModel.currentFrame = newFrame;
                                      // Auto-scroll when playhead near edges
                                      const double margin = 20.0;
                                      // final ScrollController scrollController = _scrollController; // Already have _scrollController
                                      double newScrollOffset = scrollOffsetX;
                                      if (localX < margin) {
                                        newScrollOffset = (scrollOffsetX - (margin - localX))
                                          .clamp(0.0, _scrollController.position.maxScrollExtent);
                                      } else if (localX > _viewportWidth - margin) { // Use stored viewport width
                                        newScrollOffset = (scrollOffsetX + (localX - (_viewportWidth - margin)))
                                          .clamp(0.0, _scrollController.position.maxScrollExtent);
                                      }
                                      if (newScrollOffset != scrollOffsetX) {
                                        _scrollController.jumpTo(newScrollOffset);
                                      }
                                    },
                                    child: const TimelinePlayhead(),
                                  ),
                                ),
                              ),
                              
                              // --- Resizer Handle ---
                              // Only show the resizer handle when tracks exist
                              if (tracks.isNotEmpty)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                left: trackLabelWidth - 3, // Position based on label width
                                width: 6,
                                child: GestureDetector(
                                  onHorizontalDragUpdate: (DragUpdateDetails details) {
                                    // Update notifier value directly and clamp
                                    final currentWidth = _timelineViewModel.trackLabelWidthNotifier.value;
                                    final newWidth = (currentWidth + details.delta.dx).clamp(50.0, 400.0); // Clamp width
                                    _timelineViewModel.trackLabelWidthNotifier.value = newWidth;
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
