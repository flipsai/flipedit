import 'package:fluent_ui/fluent_ui.dart';
// Removed import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
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
  // References to the view models
  late TimelineViewModel _timelineViewModel;
  late TimelineNavigationViewModel _timelineNavigationViewModel;
  // Store the listener function to remove it in dispose
  VoidCallback? _scrollRequestListener;
  // Local state for track label width
  double _trackLabelWidth = 120.0; // Initial width, managed locally

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();

    // Define the listener callback function using the navigation view model
    _scrollRequestListener = () {
      // Access navigationService via the injected viewModel
      final frame = _timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier.value;
      if (frame == null) return; // No request or already handled

      _handleScrollRequest(frame);
    };

    // Access navigationService via the injected viewModel
    _timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier.addListener(_scrollRequestListener!);
  }

  void _handleScrollRequest(int frame) {
     if (!mounted || _viewportWidth <= 0 || !_scrollController.hasClients) {
        logWarning('Timeline', 'Scroll requested for frame $frame but widget/controller not ready.');
        return;
      }
      // Use local state _trackLabelWidth
      const double framePixelWidth = 5.0;
      final double scrollableViewportWidth = _viewportWidth - _trackLabelWidth;
      if (scrollableViewportWidth <= 0) return; // Cannot calculate if viewport is too small

      // Calculate the target offset using _timelineViewModel for logic and _timelineNavigationViewModel for zoom
      final double unclampedTargetOffset = _timelineViewModel.calculateScrollOffsetForFrame(
        frame,
        _timelineNavigationViewModel.zoom, // Zoom from Navigation VM
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
    // Remove the listener from the navigation view model's notifier
    if (_scrollRequestListener != null) {
      // Access navigationService via the injected viewModel
      _timelineNavigationViewModel.navigationService.scrollToFrameRequestNotifier.removeListener(_scrollRequestListener!);
    }
    // Dispose the locally managed scroll controller
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    // Watch properties - Use TimelineNavigationViewModel for nav/playback state
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier);
    final tracks = watchValue((TimelineViewModel vm) => vm.tracksNotifierForView); // Tracks still from TimelineVM

    // Watch navigation state from TimelineNavigationViewModel
    final currentFrame = watchValue((TimelineNavigationViewModel vm) => vm.currentFrameNotifier);
    final zoom = watchValue((TimelineNavigationViewModel vm) => vm.zoomNotifier);
    final totalFrames = watchValue((TimelineNavigationViewModel vm) => vm.totalFramesNotifier);
    // trackLabelWidth is now local state (_trackLabelWidth)

    // Log clips for debugging
    if (clips.isNotEmpty) {
      logDebug( // Use logDebug function
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
                final double contentWidth = totalFrames * zoom * framePixelWidth;
                // Use local _trackLabelWidth for calculations
                final double totalScrollableWidth = math.max(
                  _viewportWidth,
                  contentWidth + _trackLabelWidth,
                );
                final double playheadPosition = currentFrame * zoom * framePixelWidth;

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
                            zoom: zoom, // Use watched zoom
                            availableWidth: _viewportWidth,
                          ),
                        ),

                      // Horizontally Scrollable Container for Ruler and All Tracks
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _scrollController,
                        // Use hasContent helper from ViewModel
                        physics: _timelineViewModel.hasContent ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
                        child: SizedBox(
                          width: totalScrollableWidth, // Define scrollable width
                          // Use AnimatedBuilder to pass scroll offset down reactively
                          child: AnimatedBuilder(
                            animation: _scrollController,
                            builder: (context, _) {
                              final currentScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                              // Inner Stack: Allows positioning Playhead over the Column
                              return Stack(
                                clipBehavior: Clip.none, // Allow playhead marker to draw outside bounds
                                children: [
                                  // Column containing TimeRuler and Tracks List
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // TimeRuler spanning the scrollable width (minus label offset)
                                      if (tracks.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(left: _trackLabelWidth), // Use local width
                                        child: SizedBox(
                                          height: timeRulerHeight,
                                          width: totalScrollableWidth - _trackLabelWidth, // Use local width
                                          // Pass required parameters to TimeRuler
                                          child: TimeRuler(
                                            zoom: zoom,
                                            availableWidth: totalScrollableWidth - _trackLabelWidth,
                                            // Removed scrollOffset as it's not a parameter
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
                                        final scrollOffsetX = _scrollController.offset;
                                        final posX = localPosition.dx - _trackLabelWidth; // Use local width
                                        final calculatedFramePosition = ((posX + scrollOffsetX) / (5.0 * zoom)).floor(); // Use watched zoom
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
                                              // Pass local state/watched values down
                                              child: TimelineTrack(
                                                key: ValueKey('timeline_track_${track.id}'),
                                                track: track,
                                                onDelete: () => _timelineViewModel.deleteTrack(track.id),
                                                trackLabelWidth: _trackLabelWidth, // Pass local state
                                                scrollOffset: currentScrollOffset, // Pass offset from builder
                                              )
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // --- Playhead (Dynamically Positioned based on Navigation VM) ---
                              if (tracks.isNotEmpty)
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: _trackLabelWidth + playheadPosition, // Use local width
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.allScroll,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onHorizontalDragUpdate: (DragUpdateDetails details) {
                                        final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
                                        if (renderBox == null) return;
                                        final Offset origin = renderBox.localToGlobal(Offset.zero);
                                        final double localX = details.globalPosition.dx - origin.dx;
                                        final double scrollOffsetX = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                        final double pxPerFrame = framePixelWidth * zoom; // Use watched zoom

                                        if (pxPerFrame <= 0) return; // Avoid division by zero

                                        double pointerRelX = (localX + scrollOffsetX - _trackLabelWidth).clamp(0.0, double.infinity); // Use local width
                                        final int maxAllowedFrame = totalFrames > 0 ? totalFrames - 1 : 0; // Use watched totalFrames
                                        final int newFrame = (pointerRelX / pxPerFrame).round().clamp(0, maxAllowedFrame);

                                        // Set frame on Navigation VM
                                        _timelineNavigationViewModel.currentFrame = newFrame;

                                        // Auto-scroll logic remains the same, using local _scrollController
                                        const double margin = 20.0;
                                        double newScrollOffset = scrollOffsetX;
                                        if (localX < margin) {
                                          newScrollOffset = (scrollOffsetX - (margin - localX))
                                            .clamp(0.0, _scrollController.position.maxScrollExtent);
                                        } else if (localX > _viewportWidth - margin) {
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

                              // --- Resizer Handle (Uses local state) ---
                              if (tracks.isNotEmpty)
                                Positioned(
                                  top: 0,
                                  bottom: 0,
                                  left: _trackLabelWidth - 3, // Position based on local width
                                  width: 6,
                                  child: GestureDetector(
                                    onHorizontalDragUpdate: (DragUpdateDetails details) {
                                      // Update local state variable and trigger rebuild
                                      setState(() {
                                        _trackLabelWidth = (_trackLabelWidth + details.delta.dx).clamp(50.0, 400.0); // Clamp width
                                      });
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
                          );
                        } // Closes AnimatedBuilder builder
                      ), // Closes AnimatedBuilder
                    ), // Closes SizedBox
                  ), // Closes SingleChildScrollView
                ],
              ), // Closes Stack
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
