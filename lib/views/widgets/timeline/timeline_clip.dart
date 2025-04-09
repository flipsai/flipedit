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
    // Use watch_it's data binding to observe the selectedClipId property
    final selectedClipId = watchValue((EditorViewModel vm) => vm.selectedClipIdNotifier);
    final isSelected = selectedClipId == clip.id;
    
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
        di<EditorViewModel>().selectedClipId = clip.id;
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
            
            // Clip content
            Expanded(
              child: _buildClipContent(clipColor),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildClipContent(Color clipColor) {
    switch (clip.type) {
      case ClipType.video:
        // For video, show a thumbnail or placeholder
        return Container(
          color: clipColor.withAlpha(150),
          child: Center(
            child: Icon(
              FluentIcons.video,
              size: 14,
              color: Colors.white.withAlpha(150),
            ),
          ),
        );
      
      case ClipType.audio:
        // For audio, show a waveform
        return CustomPaint(
          painter: _AudioWaveformPainter(
            color: Colors.white.withAlpha(150),
          ),
          child: Container(),
        );
        
      case ClipType.image:
        // For image, show a placeholder
        return Container(
          color: clipColor.withAlpha(150),
          child: Center(
            child: Icon(
              FluentIcons.picture,
              size: 14,
              color: Colors.white.withAlpha(150),
            ),
          ),
        );
        
      case ClipType.text:
        // For text, show a text icon
        return Container(
          color: clipColor.withAlpha(150),
          child: Center(
            child: Icon(
              FluentIcons.text_document,
              size: 14,
              color: Colors.white.withAlpha(150),
            ),
          ),
        );
        
      case ClipType.effect:
        // For effects, show an effect icon
        return Container(
          color: clipColor.withAlpha(150),
          child: Center(
            child: Icon(
              FluentIcons.filter,
              size: 14,
              color: Colors.white.withAlpha(150),
            ),
          ),
        );
    }
  }
}

/// Paints a simple audio waveform
class _AudioWaveformPainter extends CustomPainter {
  final Color color;
  
  _AudioWaveformPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    
    // Generate a simple random waveform
    final random = math.Random(42); // Fixed seed for consistent waveform
    
    double x = 0;
    double y = size.height / 2;
    path.moveTo(x, y);
    
    while (x < size.width) {
      x += 2;
      y = size.height / 2 + (random.nextDouble() * 2 - 1) * size.height / 3;
      path.lineTo(x, y);
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
