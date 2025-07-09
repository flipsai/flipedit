import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flipedit/models/clip.dart';
import 'dart:developer' as developer;

// Renamed from _DragPreview
class DragPreview extends StatelessWidget {
  final List<ClipModel?> candidateData;
  final double zoom;
  final int frameAtDropPosition;
  final int timeAtDropPositionMs;

  const DragPreview({
    super.key, // Added super.key
    required this.candidateData,
    required this.zoom,
    required this.frameAtDropPosition,
    required this.timeAtDropPositionMs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    // Use the same track height constant
    const trackHeight = 65.0;

    developer.log(
      'DragPreview build - frame: $frameAtDropPosition, ms: $timeAtDropPositionMs, candidates: ${candidateData.length}',
      name: 'DragPreview',
    );

    if (candidateData.isEmpty) {
      return const SizedBox.shrink();
    }

    final draggedClip = candidateData.first;
    if (draggedClip == null) {
      return const SizedBox.shrink();
    }

    final previewLeftPosition = frameAtDropPosition * zoom * 5.0;
    final previewWidth = draggedClip.durationFrames * zoom * 5.0;

    // Use the passed milliseconds for display
    final formattedTime =
        '${(timeAtDropPositionMs / 1000).toStringAsFixed(2)}s';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Position indicator line
        Positioned(
          left: previewLeftPosition,
          top: 0,
          bottom: 0,
          width: 1,
          child: Container(color: theme.colorScheme.primary.withOpacity(0.7)),
        ),
        // Preview rectangle
        Positioned(
          left: previewLeftPosition,
          top: 4, // Add a bit of padding from the top
          height: trackHeight - 8, // Leave some padding at bottom too
          width: previewWidth.clamp(2.0, double.infinity),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colorScheme.primary, width: 2),
            ),
            child: Center(
              child: Text(
                draggedClip.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        // Frame and time information
        Positioned(
          left: previewLeftPosition + previewWidth + 5,
          top: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frame: $frameAtDropPosition',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                Text(
                  'Time: $formattedTime',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
