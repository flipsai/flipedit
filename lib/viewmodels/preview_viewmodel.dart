import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/services/preview_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

class PreviewViewModel extends ChangeNotifier implements Disposable {
  late final PreviewService _previewService;
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineViewModel _timelineViewModel;

  Timer? _seekDebounceTimer;
  int _lastSentFrame = -1;
  VoidCallback? _isPlayingListener;
  VoidCallback? _currentFrameListener;
  VoidCallback? _clipsListener;
  final Duration _seekDebounceDuration = const Duration(milliseconds: 50);

  ValueListenable<ui.Image?> get currentFrameNotifier =>
      _previewService.currentFrameNotifier;
  ValueListenable<bool> get isConnectedNotifier =>
      _previewService.isConnectedNotifier;
  ValueListenable<String> get statusNotifier => _previewService.statusNotifier;
  ValueListenable<int> get fpsNotifier => _previewService.fpsNotifier;

  PreviewViewModel() {
    logDebug('PreviewViewModel initializing...');
    _previewService = di<PreviewService>();
    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineViewModel = di<TimelineViewModel>();

    _isPlayingListener = _onIsPlayingChanged;
    _timelineNavViewModel.isPlayingNotifier.addListener(_isPlayingListener!);

    _currentFrameListener = _onCurrentFrameChanged;
    _timelineNavViewModel.currentFrameNotifier.addListener(
      _currentFrameListener!,
    );

    _clipsListener = _onClipsChanged;
    _timelineViewModel.clipsNotifier.addListener(_clipsListener!);

    // --- Initial Actions ---
    _previewService.connect().then((_) {
      if (_previewService.isConnectedNotifier.value) {
        _onIsPlayingChanged(); // Send initial playback state
        _onClipsChanged(); // Send initial clips data
        _onCurrentFrameChanged(); // Send initial frame (debounced)
      }
    });

    logDebug('PreviewViewModel initialized.');
  }

  void _onIsPlayingChanged() {
    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    logVerbose(
      'PreviewViewModel: Playback state changed: $isPlaying. Sending command.',
    );
    _previewService.sendPlaybackCommand(isPlaying);
    if (isPlaying) {
      _seekDebounceTimer?.cancel();
      _lastSentFrame = -1;
    }
  }

  void _onCurrentFrameChanged() {
    if (!_timelineNavViewModel.isPlayingNotifier.value) {
      final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
      // Debounce seek commands
      if (currentFrame != _lastSentFrame) {
        _seekDebounceTimer?.cancel();
        _seekDebounceTimer = Timer(_seekDebounceDuration, () {
          if (!_timelineNavViewModel.isPlayingNotifier.value) {
            logVerbose(
              'PreviewViewModel: Debounced seek to frame: $currentFrame',
            );
            _previewService.sendSeekCommand(currentFrame);
            _lastSentFrame = currentFrame;
          }
        });
      }
    } else {
      _seekDebounceTimer?.cancel();
    }
  }

  void _onClipsChanged() {
    final clips = _timelineViewModel.clipsNotifier.value;
    logVerbose(
      'PreviewViewModel: Clips changed. Sending ${clips.length} clips.',
    );
    _previewService.sendClipsData(clips);
  }

  @override
  void dispose() {
    logDebug('PreviewViewModel disposing...');
    // Remove listeners
    if (_isPlayingListener != null) {
      _timelineNavViewModel.isPlayingNotifier.removeListener(
        _isPlayingListener!,
      );
    }
    if (_currentFrameListener != null) {
      _timelineNavViewModel.currentFrameNotifier.removeListener(
        _currentFrameListener!,
      );
    }
    if (_clipsListener != null) {
      _timelineViewModel.clipsNotifier.removeListener(_clipsListener!);
    }

    // Cancel timers
    _seekDebounceTimer?.cancel();

    // Dispose service (important!) - Let DI handle singleton disposal if needed,
    // but if this VM specifically manages the service lifecycle, dispose here.
    // Assuming PreviewService is intended to live with the Preview feature:
    // _previewService.dispose();

    super.dispose();
    logDebug('PreviewViewModel disposed.');
  }

  @override
  FutureOr onDispose() {
    dispose();
  }
}
