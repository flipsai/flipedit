import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:watch_it/watch_it.dart';

/// A track in the timeline which contains clips
class TimelineTrack extends StatelessWidget with WatchItMixin {
  final int trackIndex;
  final List<Clip> clips;
  
  const TimelineTrack({
    super.key,
    required this.trackIndex,
    required this.clips,
  });
  
  @override
  Widget build(BuildContext context) {
    final zoom = watchPropertyValue((TimelineViewModel vm) => vm.zoom);
    
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Draw the track background with frame indicators
          Positioned.fill(
            child: _TrackBackground(zoom: zoom),
          ),
          
          // Draw clips on the track
          ...clips.map((clip) => Positioned(
            left: clip.startFrame * zoom * 5, // 5 pixels per frame at zoom 1.0
            top: 0,
            height: 60,
            width: clip.durationFrames * zoom * 5,
            child: TimelineClip(
              clip: clip,
              trackIndex: trackIndex,
            ),
          )),
        ],
      ),
    );
  }
}

class _TrackBackground extends StatelessWidget {
  final double zoom;
  
  const _TrackBackground({required this.zoom});
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrackBackgroundPainter(zoom: zoom),
    );
  }
}

class _TrackBackgroundPainter extends CustomPainter {
  final double zoom;
  
  const _TrackBackgroundPainter({required this.zoom});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[130]!
      ..strokeWidth = 1;
    
    // Draw vertical frame markers every 10 frames
    for (var i = 0; i <= size.width / (10 * zoom * 5); i++) {
      final x = i * 10 * zoom * 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is _TrackBackgroundPainter) {
      return oldDelegate.zoom != zoom;
    }
    return true;
  }
}
