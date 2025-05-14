import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/views/widgets/player/stream_video_player.dart';
import 'package:flipedit/views/widgets/player/native_video_player.dart';
import 'package:flipedit/views/widgets/player/demo_video_player.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/viewmodels/player/native_player_viewmodel.dart';

enum PlayerMode {
  stream,  // Python server streaming
  native,  // Native Flutter/OpenCV rendering
  demo,    // Demo player implementation
}

class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key});

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  // Default to stream mode
  PlayerMode _playerMode = PlayerMode.stream;
  
  // Native player viewmodel instance
  NativePlayerViewModel? _nativePlayerViewModel;
  
  @override
  void initState() {
    super.initState();
    
    // Only initialize native player when switching to native mode
    if (_playerMode == PlayerMode.native) {
      _initializeNativePlayer();
    }
  }
  
  void _initializeNativePlayer() {
    if (_nativePlayerViewModel == null) {
      _nativePlayerViewModel = NativePlayerViewModel();
    }
  }
  
  void _disposeNativePlayer() {
    _nativePlayerViewModel?.dispose();
    _nativePlayerViewModel = null;
  }
  
  @override
  void dispose() {
    _disposeNativePlayer();
    super.dispose();
  }
  
  void _switchPlayerMode(PlayerMode mode) {
    if (_playerMode == mode) return;
    
    setState(() {
      _playerMode = mode;
      
      if (mode == PlayerMode.native) {
        _initializeNativePlayer();
      } else {
        _disposeNativePlayer();
      }
    });
    
    logInfo('PlayerPanel: Switched to ${mode.name} mode');
  }

  @override
  Widget build(BuildContext context) {
    logDebug("Rebuilding PlayerPanel...", 'PlayerPanel');

    // Watch values manually with ValueListenableBuilders
    return ValueListenableBuilder<int>(
      valueListenable: di.get<TimelineNavigationViewModel>().totalFramesNotifier,
      builder: (context, totalFrames, _) {
        final bool hasActiveProject = totalFrames > 0;
        
        Widget content;

        if (!hasActiveProject && _playerMode != PlayerMode.demo) {
          // Demo mode can work without an active project
          content = const Center(
            child: Text('No media loaded', style: TextStyle(color: Colors.white)),
          );
        } else {
          // Choose player based on mode
          if (_playerMode == PlayerMode.demo) {
            // Use demo player implementation
            content = Container(
              color: const Color(0xFF333333),
              child: Stack(
                children: [
                  const DemoVideoPlayer(),
                  
                  // Mode switcher button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildModeSwitcher(),
                  ),
                ],
              ),
            );
          } else if (_playerMode == PlayerMode.native) {
            // Use native player with direct OpenCV rendering
            content = Container(
              color: const Color(0xFF333333),
              child: Stack(
                children: [
                  if (_nativePlayerViewModel != null)
                    ChangeNotifierProvider<NativePlayerViewModel>.value(
                      value: _nativePlayerViewModel!,
                      child: const NativeVideoPlayer(showControls: true),
                    ),
                  
                  // Mode switcher button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildModeSwitcher(),
                  ),
                ],
              ),
            );
          } else {
            // Use stream player with Python server
            return ValueListenableBuilder<bool>(
              valueListenable: di.get<PreviewViewModel>().isConnectedNotifier,
              builder: (context, isConnected, _) {
                return ValueListenableBuilder<String>(
                  valueListenable: di.get<PreviewViewModel>().statusNotifier,
                  builder: (context, statusMessage, _) {
                    return ValueListenableBuilder<int>(
                      valueListenable: di.get<TimelineNavigationViewModel>().currentFrameNotifier,
                      builder: (context, currentTimelineFrame, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: di.get<TimelineNavigationViewModel>().isPlayingNotifier,
                          builder: (context, isPlaying, _) {
                            if (!isConnected) {
                              content = Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Preview Server Offline: $statusMessage',
                                      style: const TextStyle(color: Colors.white),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildModeSwitcher(),
                                  ],
                                ),
                              );
                            } else {
                              content = Stack(
                                children: [
                                  StreamVideoPlayer(
                                    key: const ValueKey('stream_player'),
                                    serverBaseUrl: 'http://localhost:8085',
                                    initialFrame: currentTimelineFrame,
                                    autoPlay: isPlaying,
                                    showControls: true,
                                  ),
                                  
                                  // Mode switcher button
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: _buildModeSwitcher(),
                                  ),
                                ],
                              );
                            }
                            
                            return material.Material(
                              color: const Color(0xFF333333),
                              child: content,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          }
        }

        return material.Material(
          color: const Color(0xFF333333),
          child: content,
        );
      },
    );
  }
  
  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: material.ToggleButtons(
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
        selectedColor: Colors.white,
        fillColor: Colors.blue.withOpacity(0.3),
        textStyle: const TextStyle(fontSize: 12),
        constraints: const BoxConstraints(minHeight: 32, minWidth: 50),
        children: const [
          Text('Stream'),
          Text('Native'),
          Text('Demo'),
        ],
        isSelected: [
          _playerMode == PlayerMode.stream,
          _playerMode == PlayerMode.native,
          _playerMode == PlayerMode.demo,
        ],
        onPressed: (index) {
          if (index == 0) {
            _switchPlayerMode(PlayerMode.stream);
          } else if (index == 1) {
            _switchPlayerMode(PlayerMode.native);
          } else {
            _switchPlayerMode(PlayerMode.demo);
          }
        },
      ),
    );
  }
}

// Simple ChangeNotifierProvider for the native player viewmodel
class ChangeNotifierProvider<T extends ChangeNotifier> extends InheritedNotifier<T> {
  const ChangeNotifierProvider({
    super.key,
    required T value,
    required super.child,
  }) : super(notifier: value);
  
  const ChangeNotifierProvider.value({
    super.key,
    required T value,
    required super.child,
  }) : super(notifier: value);
  
  static T of<T extends ChangeNotifier>(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<ChangeNotifierProvider<T>>();
    assert(provider != null, 'No ChangeNotifierProvider<$T> found in context');
    return provider!.notifier!;
  }
}
