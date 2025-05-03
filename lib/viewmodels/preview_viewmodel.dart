import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/services/preview_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

class PreviewViewModel extends ChangeNotifier implements Disposable {
  // --- Injected Dependencies ---
  late final PreviewService _previewService;
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineViewModel _timelineViewModel;

  // --- Internal State ---
  Timer? _seekDebounceTimer;
  int _lastSentFrame = -1;
  VoidCallback? _isPlayingListener;
  VoidCallback? _currentFrameListener;
  VoidCallback? _clipsListener;
  final Duration _seekDebounceDuration = const Duration(milliseconds: 50); // Debounce delay

  // --- Exposed State (from PreviewService) ---
  ValueListenable<ui.Image?> get currentFrameNotifier => _previewService.currentFrameNotifier;
  ValueListenable<bool> get isConnectedNotifier => _previewService.isConnectedNotifier;
  ValueListenable<String> get statusNotifier => _previewService.statusNotifier;
  ValueListenable<int> get fpsNotifier => _previewService.fpsNotifier;

  PreviewViewModel() {
    logDebug('PreviewViewModel initializing...');
    // Get dependencies from DI
    _previewService = di<PreviewService>();
    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineViewModel = di<TimelineViewModel>();

    // --- Setup Listeners ---

    // Listen to TimelineNavigationViewModel for playback and frame changes
    _isPlayingListener = _onIsPlayingChanged;
    _timelineNavViewModel.isPlayingNotifier.addListener(_isPlayingListener!);

    _currentFrameListener = _onCurrentFrameChanged;
    _timelineNavViewModel.currentFrameNotifier.addListener(_currentFrameListener!);

    // Listen to TimelineViewModel for clip changes
    _clipsListener = _onClipsChanged;
    _timelineViewModel.clipsNotifier.addListener(_clipsListener!);

    // --- Initial Actions ---
    // Connect the preview service automatically
    _previewService.connect().then((_) {
       // After connection attempt, send initial state
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
    logVerbose('PreviewViewModel: Playback state changed: $isPlaying. Sending command.');
    _previewService.sendPlaybackCommand(isPlaying);
    // If starting playback, cancel any pending seek command
    if (isPlaying) {
      _seekDebounceTimer?.cancel();
      _lastSentFrame = -1; // Reset last sent frame when playing starts
    }
  }

  void _onCurrentFrameChanged() {
    // Only send seek commands when not playing
    if (!_timelineNavViewModel.isPlayingNotifier.value) {
      final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;
      // Debounce seek commands
      if (currentFrame != _lastSentFrame) {
         _seekDebounceTimer?.cancel();
         _seekDebounceTimer = Timer(_seekDebounceDuration, () {
           if (!_timelineNavViewModel.isPlayingNotifier.value) { // Double check playing state
             logVerbose('PreviewViewModel: Debounced seek to frame: $currentFrame');
             _previewService.sendSeekCommand(currentFrame);
             _lastSentFrame = currentFrame;
           }
         });
      }
    } else {
       // If playing, ensure any lingering debounce timer is cancelled.
       _seekDebounceTimer?.cancel();
    }
  }

  void _onClipsChanged() {
    final clips = _timelineViewModel.clipsNotifier.value;
    logVerbose('PreviewViewModel: Clips changed. Sending ${clips.length} clips.');
    // Pass the List<ClipModel?> directly
    _previewService.sendClipsData(clips);
  }

  @override
  void dispose() {
    logDebug('PreviewViewModel disposing...');
    // Remove listeners
    if (_isPlayingListener != null) {
      _timelineNavViewModel.isPlayingNotifier.removeListener(_isPlayingListener!);
    }
    if (_currentFrameListener != null) {
      _timelineNavViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    }
    if (_clipsListener != null) {
      _timelineViewModel.clipsNotifier.removeListener(_clipsListener!);
    }

    // Cancel timers
    _seekDebounceTimer?.cancel();

    // Dispose service (important!) - Let DI handle singleton disposal if needed,
    // but if this VM specifically manages the service lifecycle, dispose here.
    // Assuming PreviewService is intended to live with the Preview feature:
    // _previewService.dispose(); // Let DI manage singleton lifecycle

    super.dispose();
    logDebug('PreviewViewModel disposed.');
  }

  // --- Explicitly implement Disposable ---
  @override
  FutureOr onDispose() {
     dispose();
  }
}
