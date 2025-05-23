import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/viewmodels/player/opencv_python_player_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  late final OpenCvPythonPlayerViewModel _playerViewModel;
  late final TimelineNavigationViewModel _timelineNavViewModel;

  @override
  void initState() {
    super.initState();
    logDebug("Initializing PlayerPanel...", 'PlayerPanel');

    _playerViewModel = OpenCvPythonPlayerViewModel();
    _timelineNavViewModel = di<TimelineNavigationViewModel>();

    // Add listeners to rebuild on state changes
    _playerViewModel.textureIdNotifier.addListener(_rebuild);
    _playerViewModel.isReadyNotifier.addListener(_rebuild);
    _playerViewModel.statusNotifier.addListener(_rebuild);
    _playerViewModel.fpsNotifier.addListener(_rebuild);
    _timelineNavViewModel.isPlayingNotifier.addListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Remove listeners
    _playerViewModel.textureIdNotifier.removeListener(_rebuild);
    _playerViewModel.isReadyNotifier.removeListener(_rebuild);
    _playerViewModel.statusNotifier.removeListener(_rebuild);
    _playerViewModel.fpsNotifier.removeListener(_rebuild);
    _timelineNavViewModel.isPlayingNotifier.removeListener(_rebuild);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_rebuild);

    // Dispose view model
    _playerViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    // Get current values from notifiers
    final textureId = _playerViewModel.textureIdNotifier.value;
    final isReady = _playerViewModel.isReadyNotifier.value;
    final status = _playerViewModel.statusNotifier.value;
    final fps = _playerViewModel.fpsNotifier.value;
    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    return Container(
      color: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video display area
          Expanded(
            child: Center(
              child:
                  textureId != -1
                      ? Container(
                        color: Colors.blue.withOpacity(
                          0.2,
                        ), // Add a slight blue tint to see container boundaries
                        width: double.infinity,
                        height: double.infinity,
                        child: Stack(
                          children: [
                            // Texture widget with explicit size
                            Positioned.fill(
                              child: material.Texture(
                                textureId: textureId,
                                filterQuality: material.FilterQuality.high,
                              ),
                            ),

                            // Debug overlay to show texture ID
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                color: Colors.black.withOpacity(0.5),
                                child: Text(
                                  'Texture ID: $textureId',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),

                            // If Python connection is in progress or failed, show an overlay
                            if (!isReady)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withOpacity(0.7),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const ProgressRing(),
                                        const SizedBox(height: 16),
                                        Text(
                                          status,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                      : const Center(child: ProgressRing()),
            ),
          ),

          // Player controls and info bar
          Container(
            height: 40,
            color: Colors.grey[160],
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Play/Pause button
                Button(
                  onPressed: () {
                    if (isPlaying) {
                      _timelineNavViewModel.stopPlayback();
                    } else {
                      _timelineNavViewModel.startPlayback();
                    }
                  },
                  child: Icon(
                    isPlaying ? FluentIcons.pause : FluentIcons.play,
                    size: 16,
                  ),
                ),

                const SizedBox(width: 8),

                // Frame info
                Text('Frame: $currentFrame'),

                const Spacer(),

                // Mode label
                Text(
                  'Python OpenCV Renderer',
                  style: FluentTheme.of(context).typography.caption,
                ),

                const SizedBox(width: 8),

                // FPS counter
                Text('$fps FPS'),

                const SizedBox(width: 8),

                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.green : Colors.yellow,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isReady ? 'Ready' : status,
                    style: FluentTheme.of(context).typography.caption,
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

// Simple ChangeNotifierProvider for the native player viewmodel
class ChangeNotifierProvider<T extends ChangeNotifier>
    extends InheritedNotifier<T> {
  const ChangeNotifierProvider({
    super.key,
    required T notifier,
    required super.child,
  }) : super(notifier: notifier);

  static T of<T extends ChangeNotifier>(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ChangeNotifierProvider<T>>();
    return provider!.notifier!;
  }
}
