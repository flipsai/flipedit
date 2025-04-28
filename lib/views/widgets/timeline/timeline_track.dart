import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/persistence/database/project_database.dart'; // Import for Track data class definition
// Removed incorrect track table import
// Removed persistence import
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Added import
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flutter/widgets.dart' as fw;
import "dart:developer" as developer;
// Removed unused: import 'package:flipedit/viewmodels/commands/roll_edit_command.dart';
import 'components/track_background.dart'; // Import new component
import 'components/drag_preview.dart'; // Import new component
import 'components/roll_edit_handle.dart'; // Import new component
// Removed AddClipCommand import, handled by ViewModel

class TimelineTrack extends StatefulWidget with WatchItStatefulWidgetMixin {
  final Track track;
  final VoidCallback onDelete;
  final double trackLabelWidth;
  final double scrollOffset; // Added scroll offset parameter

  const TimelineTrack({
    super.key,
    required this.track,
    required this.onDelete,
    required this.trackLabelWidth,
    required this.scrollOffset, // Added scroll offset parameter
  });

  @override
  State<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends State<TimelineTrack> {
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late final ValueNotifier<Offset?> _hoverPositionNotifier = ValueNotifier(null);
  final GlobalKey _trackContentKey = GlobalKey();

  late TimelineViewModel _timelineViewModel;
  late TimelineNavigationViewModel _timelineNavigationViewModel; // Added
  // Removed TimelineLogicService instance

  @override
  void initState() {
    super.initState();
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>(); // Initialize
    // Removed TimelineLogicService initialization
    _textController = TextEditingController(text: widget.track.name);
    _focusNode = FocusNode();

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _submitRename();
      }
    });

    // Force a refresh of clips when mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineViewModel.refreshClips();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.removeListener(() { });
    _focusNode.dispose();
    _hoverPositionNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TimelineTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the track name changes from the parent widget AND we are not currently editing,
    // update the text controller to reflect the external change.
    if (widget.track.name != oldWidget.track.name && !_isEditing) {
      developer.log('Track name updated externally from "${oldWidget.track.name}" to "${widget.track.name}"');
      _textController.text = widget.track.name;
    }
  }
 
  void _enterEditingMode() {
    setState(() {
      _isEditing = true;
      _textController.text = widget.track.name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _focusNode.requestFocus();
       _textController.selection = TextSelection(
           baseOffset: 0,
           extentOffset: _textController.text.length,
       );
    });
  }

  void _submitRename() {
    developer.log('Attempting to submit rename for track ${widget.track.id}...');
    final newName = _textController.text.trim();
    if (mounted && _isEditing) {
      developer.log('Mounted and isEditing: true. New name: "$newName"');
      final oldName = widget.track.name; // Store old name
      if (newName.isNotEmpty && newName != oldName) {
        developer.log('New name is valid. Calling timelineViewModel.updateTrackName...');
        _timelineViewModel.updateTrackName(widget.track.id, newName);
      }
      setState(() {
        _isEditing = false;
        developer.log('Exiting editing mode.');
      });
    } else {
      developer.log('Not submitting: mounted=$mounted, isEditing=$_isEditing');
    }
  }

  // Updated to use the passed scrollOffset
  double getHorizontalScrollOffset() {
    // The parent (Timeline) now passes the scroll offset directly
    // No need to access ViewModel or check controller clients here
    return widget.scrollOffset;
  }

  /// Calculates the preview frame position using the ViewModel.
  int _calculateFramePositionForPreview(double previewRawX, double zoom) {
    final scrollOffsetX = getHorizontalScrollOffset();
    // Use ViewModel method for calculation
    final framePosition = _timelineViewModel.calculateFramePositionForOffset(
      previewRawX,
      scrollOffsetX,
      zoom,
    );

    // Debugging
    developer.log(
      '🔍 Preview position: raw=$previewRawX, scroll=$scrollOffsetX, frame=$framePosition',
      name: 'TimelineTrack'
    );
    
    return framePosition;
  }

  // Helper method to update hover position
  void _updateHoverPosition(Offset? position) {
    if (_hoverPositionNotifier.value != position) {
      setState(() {
        _hoverPositionNotifier.value = position;
      });
    }
  }

  // Removed _handleClipDrop - logic moved to ViewModel's initiateClipDrop

  // Add method to select this track
  void _handleTrackSelection() {
    // This will automatically handle deselecting clips on other tracks
    // through the logic we added in the TimelineViewModel
    _timelineViewModel.selectedTrackId = widget.track.id;
  }

  @override
  Widget build(BuildContext context) {
    // Watch zoom from TimelineNavigationViewModel
    final double zoom = watchValue((TimelineNavigationViewModel vm) => vm.zoomNotifier);
    final theme = FluentTheme.of(context);
    const trackHeight = 65.0;

    // Watch only the clips for this track
    final clips = watchValue((TimelineViewModel vm) => vm.clipsNotifier)
        .where((clip) => clip.trackId == widget.track.id)
        .toList();
        
    // Watch the selected track ID
    final selectedTrackId = watchValue((TimelineViewModel vm) => vm.selectedTrackIdNotifier);
    final isSelected = selectedTrackId == widget.track.id;

    // Log clips for debugging
    if (clips.isNotEmpty) {
      developer.log(
        '📼 Building TimelineTrack "${widget.track.name}" with ${clips.length} clips',
        name: 'TimelineTrack'
      );
      developer.log(
        '📼 First clip: ${clips.first.name}, startFrame: ${clips.first.startFrame}',
        name: 'TimelineTrack'
      );
    } else {
      developer.log(
        '📼 Building TimelineTrack "${widget.track.name}" with NO CLIPS',
        name: 'TimelineTrack'
      );
    }

    return GestureDetector(
      onTap: _handleTrackSelection,
      child: SizedBox(
        height: trackHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: widget.trackLabelWidth,
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: isSelected 
                  ? theme.accentColor.withOpacity(0.2)
                  : theme.resources.subtleFillColorTertiary,
                border: Border(
                  right: BorderSide(
                    color: theme.resources.controlStrokeColorDefault,
                  ),
                  // Add a left border highlight when selected
                  left: isSelected 
                    ? BorderSide(color: theme.accentColor, width: 3.0)
                    : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Add drag handle at the left
                  ReorderableDragStartListener(
                    index: 0, // Use default index, the actual indices are handled in Timeline component
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(
                          FluentIcons.more_vertical,
                          size: 12,
                          color: theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: _enterEditingMode,
                      child: _isEditing
                          ? TextBox(
                              controller: _textController,
                              focusNode: _focusNode,
                              placeholder: 'Track Name',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.0,
                                vertical: 4.0,
                              ),
                              style: theme.typography.body,
                              decoration: WidgetStateProperty.all(BoxDecoration(
                                color: theme.resources.controlFillColorDefault,
                                borderRadius: BorderRadius.circular(4.0),
                              )),
                              onSubmitted: (_) => _submitRename(),
                            )
                          : Text(
                              widget.track.name,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.body,
                            ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.delete, size: 14),
                    onPressed: widget.onDelete,
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(inherit: false)
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: DragTarget<ClipModel>(
                key: _trackContentKey,
                onAcceptWithDetails: (details) async {
                  final draggedClip = details.data;
                  developer.log('✅ Clip drop detected: ${draggedClip.name}', name: 'TimelineTrack');
                  final RenderBox? renderBox =
                      _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox == null) {
                    developer.log('❌ Error: renderBox is null in onAcceptWithDetails', name: 'TimelineTrack');
                    return;
                  }
                  final localPosition = renderBox.globalToLocal(details.offset);
                  final scrollOffsetX = getHorizontalScrollOffset();
                  
                  // Calculate the target frame and time using ViewModel methods
                  final targetFrame = _timelineViewModel.calculateFramePositionForOffset(
                      localPosition.dx, scrollOffsetX, zoom);
                  final targetStartTimeOnTrackMs = _timelineViewModel.frameToMs(targetFrame);
              
                  // Use the refactored ViewModel method to handle the drop
                  await _timelineViewModel.handleClipDrop(
                    clip: draggedClip,
                    trackId: widget.track.id,
                    startTimeOnTrackMs: targetStartTimeOnTrackMs,
                  );

                  _updateHoverPosition(null); // Clear hover state after drop
                },
                onWillAcceptWithDetails: (details) {
                  final RenderBox? renderBox =
                      _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final localPosition = renderBox.globalToLocal(details.offset);
                    _updateHoverPosition(localPosition);
                  }
                  return true;
                },
                onMove: (details) {
                  final RenderBox? renderBox =
                      _trackContentKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox != null) {
                    final localPosition = renderBox.globalToLocal(details.offset);
                    _updateHoverPosition(localPosition);
                  }
                },
                onLeave: (_) {
                  _updateHoverPosition(null);
                },
                builder: (context, candidateData, rejectedData) {
                  int frameForPreview = -1;
                  final currentHoverPos = _hoverPositionNotifier.value;
                  int timeForPreviewMs = -1; // Calculate milliseconds for preview

                  if (currentHoverPos != null && candidateData.isNotEmpty) {
                    frameForPreview = _calculateFramePositionForPreview(currentHoverPos.dx, zoom);
                    // Calculate milliseconds using ViewModel
                    timeForPreviewMs = _timelineViewModel.frameToMs(frameForPreview);
                  }

                  return Container(
                    height: trackHeight,
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: isSelected
                        ? theme.accentColor.withOpacity(0.1)
                        : candidateData.isNotEmpty
                          ? theme.accentColor.lightest.withValues(alpha: 0.3)
                          : theme.resources.subtleFillColorSecondary,
                    ),
                    child: Stack(
                      clipBehavior: fw.Clip.hardEdge,
                      children: [
                        // Background grid with frame markings
                        Positioned.fill(child: TrackBackground(zoom: zoom)), // Use new component

                        // Display existing clips on this track, or preview if dragging
                        if (candidateData.isNotEmpty && frameForPreview >= 0)
                          // Get preview clips from ViewModel
                          ..._getPreviewClipsFromViewModel(candidateData.first!, frameForPreview, zoom, trackHeight)
                        else
                          // Display actual clips from ViewModel for this track
                          ...clips.whereType<ClipModel>().map((clip) {
                            final leftPosition = clip.startFrame * zoom * 5.0;
                            final clipWidth = clip.durationFrames * zoom * 5.0;
                            return Positioned(
                              left: leftPosition,
                              top: 0,
                              height: trackHeight,
                              width: clipWidth.clamp(4.0, double.infinity),
                              child: TimelineClip(
                                key: ValueKey(clip.databaseId ?? clip.sourcePath),
                                clip: clip,
                                trackId: widget.track.id,
                              ),
                            );
                          }),

                        // Show preview overlay when dragging
                        if (frameForPreview >= 0 && timeForPreviewMs >= 0)
                          DragPreview( // Use new component
                            candidateData: candidateData,
                            zoom: zoom,
                            frameAtDropPosition: frameForPreview,
                            timeAtDropPositionMs: timeForPreviewMs, // Pass milliseconds
                          ),
                        // --- Roll Edit Handles (only when not dragging onto track) ---
                        if (candidateData.isEmpty)
                          ..._buildRollEditHandles(clips, zoom, _timelineViewModel, trackHeight),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gets preview clip widgets using the ViewModel's preview calculation logic.
  List<Widget> _getPreviewClipsFromViewModel(
    ClipModel draggedClip,
    int frameForPreview,
    double zoom,
    double trackHeight,
  ) {
    if (draggedClip.databaseId == null) {
      debugPrint('Warning: draggedClip.databaseId is null. Skipping preview.');
      return [];
    }

    // Calculate target start time in ms using ViewModel
    final targetStartTimeOnTrackMs = _timelineViewModel.frameToMs(frameForPreview);

    // Get preview clips from ViewModel
    final previewClips = _timelineViewModel.getDragPreviewClips(
      draggedClipId: draggedClip.databaseId!,
      targetTrackId: widget.track.id,
      targetStartTimeOnTrackMs: targetStartTimeOnTrackMs,
    )
    // Filter again just to be safe, ensuring only clips for *this* track are shown in its preview
    .where((clip) => clip.trackId == widget.track.id)
    .whereType<ClipModel>() // Ensure correct type
    .toList();

    return previewClips.map((clip) {
      final leftPosition = clip.startFrame * zoom * 5.0;
      final clipWidth = clip.durationFrames * zoom * 5.0;
      return Positioned(
        left: leftPosition,
        top: 0,
        height: trackHeight,
        width: clipWidth.clamp(4.0, double.infinity),
        child: TimelineClip(
          key: ValueKey('preview_${clip.databaseId ?? clip.sourcePath}'),
          clip: clip,
          trackId: widget.track.id,
        ),
      );
    }).toList();
  }
  /// Builds the RollEditHandle widgets for adjacent clips on the track.
  List<Widget> _buildRollEditHandles(
    List<ClipModel> trackClips,
    double zoom,
    TimelineViewModel viewModel,
    double trackHeight,
  ) {
    final List<Widget> handles = [];
    // Ensure clips are sorted by start time for reliable adjacency checks
    final sortedClips = List<ClipModel>.from(trackClips)
      ..sort((a, b) => a.startFrame.compareTo(b.startFrame));

    for (int i = 0; i < sortedClips.length - 1; i++) {
      final leftClip = sortedClips[i];
      final rightClip = sortedClips[i + 1];

      // Check if clips are directly adjacent and have valid IDs
      // TODO: Add check for compatible clip types if necessary for roll edits
      if (leftClip.endFrame == rightClip.startFrame &&
          leftClip.databaseId != null &&
          rightClip.databaseId != null) {
        final boundaryFrame = leftClip.endFrame;
        // Calculate position based on the frame number and zoom
        // The handle should visually center on the boundary, so offset slightly
        final handleWidth = 20.0; // Standard width for the handle
        final leftPosition = (boundaryFrame * zoom * 5.0) - (handleWidth / 2);

        handles.add(Positioned(
          key: ValueKey('roll_handle_${leftClip.databaseId}_${rightClip.databaseId}'), // Add key for stability
          left: leftPosition,
          top: 0,
          bottom: 0,
          width: handleWidth, // Define a width for the handle's touch area
          child: RollEditHandle(
            leftClipId: leftClip.databaseId!,
            rightClipId: rightClip.databaseId!,
            initialFrame: boundaryFrame,
            zoom: zoom,
            viewModel: viewModel,
          ),
        ));
      }
    }
    return handles;
  }
}

// Removed nested classes: _DragPreview, _TrackBackground, _RollEditHandle, _RollEditHandleState
// They are now in separate files under lib/views/widgets/timeline/components/

