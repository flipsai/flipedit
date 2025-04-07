import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/models/enums/clip_type.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/views/widgets/timeline/timeline_clip.dart';
import 'package:flipedit/views/widgets/timeline/timeline_track.dart';
import 'package:watch_it/watch_it.dart';

/// Main timeline widget that shows clips and tracks
/// Similar to the timeline in video editors like Premiere Pro or Final Cut
class Timeline extends StatelessWidget with WatchItMixin {
  const Timeline({super.key});

  @override
  Widget build(BuildContext context) {
    final timelineViewModel = di<TimelineViewModel>();
    final clips = watchPropertyValue((TimelineViewModel vm) => vm.clips);
    final currentFrame = watchPropertyValue((TimelineViewModel vm) => vm.currentFrame);
    final isPlaying = watchPropertyValue((TimelineViewModel vm) => vm.isPlaying);
    final zoom = watchPropertyValue((TimelineViewModel vm) => vm.zoom);
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Colors.grey[120])),
      ),
      child: Column(
        children: [
          // Timeline controls
          _buildTimelineControls(context, isPlaying, currentFrame),
          
          // Timeline content
          Expanded(
            child: Row(
              children: [
                // Track labels
                Container(
                  width: 120,
                  color: const Color(0xFF2D2D2D),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    children: [
                      _TrackLabel(label: 'Video 1'),
                      _TrackLabel(label: 'Audio 1'),
                    ],
                  ),
                ),
                
                // Tracks with clips
                Expanded(
                  child: Stack(
                    children: [
                      // Time ruler
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _TimeRuler(
                          zoom: zoom,
                          totalFrames: timelineViewModel.totalFrames,
                        ),
                      ),
                      
                      // Playhead
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: currentFrame * zoom * 5, // 5 pixels per frame at zoom 1.0
                        child: Container(
                          width: 1,
                          color: Colors.red,
                        ),
                      ),
                      
                      // Tracks and clips
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          children: [
                            TimelineTrack(
                              trackIndex: 0,
                              clips: clips.where((clip) => clip.type.toString().contains('video')).toList(),
                            ),
                            TimelineTrack(
                              trackIndex: 1,
                              clips: clips.where((clip) => clip.type.toString().contains('audio')).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineControls(BuildContext context, bool isPlaying, int currentFrame) {
    final timelineViewModel = di<TimelineViewModel>();
    
    return Container(
      height: 40,
      color: const Color(0xFF2D2D2D),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Zoom controls
          IconButton(
            icon: const Icon(FluentIcons.remove, size: 16),
            onPressed: () {
              timelineViewModel.setZoom(timelineViewModel.zoom / 1.2);
            },
          ),
          IconButton(
            icon: const Icon(FluentIcons.add, size: 16),
            onPressed: () {
              timelineViewModel.setZoom(timelineViewModel.zoom * 1.2);
            },
          ),
          
          const SizedBox(width: 16),
          
          // Playback controls
          IconButton(
            icon: const Icon(FluentIcons.previous, size: 16),
            onPressed: () {
              timelineViewModel.seekTo(0);
            },
          ),
          IconButton(
            icon: Icon(
              isPlaying ? FluentIcons.pause : FluentIcons.play,
              size: 16,
            ),
            onPressed: () {
              timelineViewModel.togglePlayback();
            },
          ),
          IconButton(
            icon: const Icon(FluentIcons.next, size: 16),
            onPressed: () {
              timelineViewModel.seekTo(timelineViewModel.totalFrames);
            },
          ),
          
          const SizedBox(width: 16),
          
          // Frame counter
          Text(
            'Frame: $currentFrame / ${timelineViewModel.totalFrames}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          
          const Spacer(),
          
          // Add clip button
          FilledButton(
            onPressed: () {
              _showAddClipDialog(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.add, size: 12),
                SizedBox(width: 4),
                Text('Add Clip'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddClipDialog(BuildContext context) {
    // This would show a dialog to add a new clip in a real application
    // For now, just add a dummy clip
    final timelineViewModel = di<TimelineViewModel>();
    
    final newClip = Clip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Clip',
      type: ClipType.video,
      filePath: '/path/to/dummy/file.mp4',
      startFrame: timelineViewModel.currentFrame,
      durationFrames: 120,
    );
    
    timelineViewModel.addClip(newClip);
  }
}

class _TrackLabel extends StatelessWidget {
  final String label;
  
  const _TrackLabel({required this.label});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            label.contains('Video') ? FluentIcons.video : FluentIcons.music_in_collection,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TimeRuler extends StatelessWidget {
  final double zoom;
  final int totalFrames;
  
  const _TimeRuler({required this.zoom, required this.totalFrames});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      color: const Color(0xFF2D2D2D),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: (totalFrames / 10).ceil() + 1,
        itemBuilder: (context, index) {
          final frameNumber = index * 10;
          return Container(
            width: 10 * zoom * 5, // 5 pixels per frame at zoom 1.0
            decoration: const BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey),
              ),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                frameNumber.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
