import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'dart:math' as math;

/// A clip in the timeline track
class TimelineClip extends StatelessWidget with WatchItMixin {
  final Clip clip;
  final int trackIndex;
  
  const TimelineClip({
    super.key,
    required this.clip,
    required this.trackIndex,
  });
  
  @override
  Widget build(BuildContext context) {
    final selectedClipId = watchPropertyValue((EditorViewModel vm) => vm.selectedClipId);
    final isSelected = selectedClipId == clip.id;
    
    final editorViewModel = di<EditorViewModel>();
    
    // Clip background color based on type
    Color clipColor;
    switch (clip.type) {
      case ClipType.video:
        clipColor = const Color(0xFF264F78);
        break;
      case ClipType.audio:
        clipColor = const Color(0xFF498205);
        break;
      case ClipType.image:
        clipColor = const Color(0xFF8764B8);
        break;
      case ClipType.text:
        clipColor = const Color(0xFFC29008);
        break;
      case ClipType.effect:
        clipColor = const Color(0xFFC50F1F);
        break;
    }
    
    return GestureDetector(
      onTap: () {
        editorViewModel.selectClip(clip.id);
      },
      onHorizontalDragUpdate: (details) {
        // This would handle moving the clip in a real implementation
        // You'd need to convert the pixel movement to frames based on zoom level
      },
      child: Container(
        decoration: BoxDecoration(
          color: clipColor,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clip header with title
            Container(
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: clipColor.withAlpha(205),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  topRight: Radius.circular(2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    clip.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Expanded(child: Container()),
                  Text(
                    '${clip.durationFrames}f',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            
            // Clip content - would show thumbnails or waveforms in a real implementation
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: _getClipContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _getClipContent() {
    switch (clip.type) {
      case ClipType.video:
        return const Center(
          child: Icon(
            FluentIcons.video,
            color: Colors.white,
            size: 16,
          ),
        );
      case ClipType.audio:
        return CustomPaint(
          painter: _AudioWaveformPainter(),
        );
      case ClipType.image:
        return const Center(
          child: Icon(
            FluentIcons.photo2,
            color: Colors.white,
            size: 16,
          ),
        );
      case ClipType.text:
        return const Center(
          child: Icon(
            FluentIcons.font,
            color: Colors.white,
            size: 16,
          ),
        );
      case ClipType.effect:
        return const Center(
          child: Icon(
            FluentIcons.filter,
            color: Colors.white,
            size: 16,
          ),
        );
    }
  }
}

/// Paints a simple audio waveform
class _AudioWaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;
    
    // Draw a simple waveform
    final path = Path();
    const amplitude = 10.0;
    const frequency = 0.15;
    
    path.moveTo(0, size.height / 2);
    
    for (var x = 0.0; x < size.width; x++) {
      final y = size.height / 2 + amplitude * math.sin(x * frequency);
      path.lineTo(x, y);
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
