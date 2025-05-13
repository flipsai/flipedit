import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';

import 'package:flipedit/services/preview_http_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';

class PreviewViewModel extends ChangeNotifier implements Disposable {
  late final PreviewHttpService _previewHttpService;
  late final TimelineNavigationViewModel _timelineNavViewModel;
  late final TimelineStateViewModel _timelineStateViewModel;
  late final CanvasDimensionsService _canvasDimensionsService;

  Timer? _seekDebounceTimer;
  int _lastNotifiedFrameForStream = -1;
  VoidCallback? _isPlayingListener;
  VoidCallback? _currentFrameListener;
  VoidCallback? _clipsListener;
  VoidCallback? _canvasDimensionsListener; // Added
  final Duration _seekDebounceDuration = const Duration(milliseconds: 150);

  final ValueNotifier<bool> _isConnectedNotifier = ValueNotifier(false);
  ValueListenable<bool> get isConnectedNotifier => _isConnectedNotifier;

  final ValueNotifier<String> _statusNotifier = ValueNotifier('Initializing...');
  ValueListenable<String> get statusNotifier => _statusNotifier;

  final ValueNotifier<String?> _streamUrlNotifier = ValueNotifier(null);
  ValueListenable<String?> get streamUrlNotifier => _streamUrlNotifier;

  bool _isDisposed = false;

  PreviewViewModel() {
    logDebug('PreviewViewModel initializing...');
    _previewHttpService = di<PreviewHttpService>();
    _timelineNavViewModel = di<TimelineNavigationViewModel>();
    _timelineStateViewModel = di<TimelineStateViewModel>();
    _canvasDimensionsService = di<CanvasDimensionsService>(); // Added

    _isPlayingListener = _handlePlaybackOrSeekChange;
    _timelineNavViewModel.isPlayingNotifier.addListener(_isPlayingListener!);

    _currentFrameListener = _handlePlaybackOrSeekChange;
    _timelineNavViewModel.currentFrameNotifier.addListener(_currentFrameListener!);

    _clipsListener = _onClipsChanged;
    _timelineStateViewModel.clipsNotifier.addListener(_clipsListener!);

    _canvasDimensionsListener = _onCanvasDimensionsChanged; // Added
    _canvasDimensionsService.canvasWidthNotifier.addListener(_canvasDimensionsListener!); // Added
    _canvasDimensionsService.canvasHeightNotifier.addListener(_canvasDimensionsListener!); // Added

    _checkInitialServerHealth();

    logDebug('PreviewViewModel initialized.');
  }

  Future<void> _checkInitialServerHealth() async {
    if (_isDisposed) return;
    _statusNotifier.value = 'Checking server...';
    final healthy = await _previewHttpService.checkHealth();
    if (_isDisposed) return;

    _isConnectedNotifier.value = healthy;
    _statusNotifier.value = healthy ? 'Server Connected' : 'Server Offline';

    if (healthy) {
      // Initial sync
      await _onClipsChanged(); // Send initial clips data
      await _onCanvasDimensionsChanged(); // Send initial canvas dimensions
      _updateStreamUrl(); // Set initial stream URL
    } else {
      _streamUrlNotifier.value = null;
    }
  }

  void _handlePlaybackOrSeekChange() {
    if (_isDisposed || !_isConnectedNotifier.value) return;

    final isPlaying = _timelineNavViewModel.isPlayingNotifier.value;
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    _seekDebounceTimer?.cancel();

    if (isPlaying) {
      // If playing, and the stream isn't already set to play from the current frame (or start)
      if (_lastNotifiedFrameForStream != currentFrame || _streamUrlNotifier.value == null) {
         logVerbose('PreviewViewModel: Playback started or resumed. Updating stream for frame $currentFrame.');
        _updateStreamUrl(startFrame: currentFrame);
      }
    } else {
      // If paused, debounce the seek operation
      _seekDebounceTimer = Timer(_seekDebounceDuration, () {
        if (_isDisposed || _timelineNavViewModel.isPlayingNotifier.value) return; // Check again in case state changed
        logVerbose('PreviewViewModel: Debounced seek. Updating stream for frame $currentFrame.');
        _updateStreamUrl(startFrame: currentFrame);
      });
    }
  }

  void _updateStreamUrl({int? startFrame}) {
    if (_isDisposed || !_isConnectedNotifier.value) {
       _streamUrlNotifier.value = null;
       return;
    }

    final targetFrame = startFrame ?? _timelineNavViewModel.currentFrameNotifier.value;

    // Only update if the target frame for the stream has changed.
    // This prevents unnecessary URL changes if currentFrameNotifier updates rapidly during seeking
    // but the debounced/actual stream start point shouldn't change yet.
    if (targetFrame == _lastNotifiedFrameForStream && _streamUrlNotifier.value != null && startFrame == null && !_timelineNavViewModel.isPlayingNotifier.value) {
       // If not playing, and we are not forcing a startFrame, and the target is same as last, do nothing.
       // This helps keep the player stable during rapid scrubbing when paused.
       return;
    }

    _streamUrlNotifier.value = _previewHttpService.getStreamUrl(startFrame: targetFrame);
    _lastNotifiedFrameForStream = targetFrame;
    logInfo('PreviewViewModel: Stream URL updated to: ${_streamUrlNotifier.value}');
  }

  Future<void> _onClipsChanged() async {
    if (_isDisposed || !_isConnectedNotifier.value) return;

    final clips = _timelineStateViewModel.clipsNotifier.value;
    final List<Map<String, dynamic>> serializableClips = clips.map((clip) => clip.toJson()).toList();

    logVerbose('PreviewViewModel: Clips changed. Sending ${serializableClips.length} clips to server.');
    final success = await _previewHttpService.updateTimeline(serializableClips);
    if (!success && !_isDisposed) {
      _isConnectedNotifier.value = false;
      _statusNotifier.value = 'Server Error: Timeline Update Failed';
      _streamUrlNotifier.value = null;
    }
  }

  Future<void> _onCanvasDimensionsChanged() async {
    if (_isDisposed || !_isConnectedNotifier.value) return;

    final width = _canvasDimensionsService.canvasWidthNotifier.value;
    final height = _canvasDimensionsService.canvasHeightNotifier.value;

    if (width == 0 || height == 0) {
      logWarning('PreviewViewModel: Canvas dimensions are zero, skipping update.', 'PreviewViewModel');
      return;
    }

    logVerbose('PreviewViewModel: Canvas dimensions changed to $width x $height. Sending to server.');
    final success = await _previewHttpService.updateCanvasDimensions(width.toInt(), height.toInt());
    if (!success && !_isDisposed) {
      _isConnectedNotifier.value = false;
      _statusNotifier.value = 'Server Error: Canvas Update Failed';
      _streamUrlNotifier.value = null;
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    logDebug('PreviewViewModel disposing...');

    _timelineNavViewModel.isPlayingNotifier.removeListener(_isPlayingListener!);
    _timelineNavViewModel.currentFrameNotifier.removeListener(_currentFrameListener!);
    _timelineStateViewModel.clipsNotifier.removeListener(_clipsListener!);
    _canvasDimensionsService.canvasWidthNotifier.removeListener(_canvasDimensionsListener!);
    _canvasDimensionsService.canvasHeightNotifier.removeListener(_canvasDimensionsListener!);

    _seekDebounceTimer?.cancel();
    _streamUrlNotifier.dispose();
    _isConnectedNotifier.dispose();
    _statusNotifier.dispose();

    super.dispose();
    logDebug('PreviewViewModel disposed.');
  }

  @override
  FutureOr onDispose() {
    // dispose() is already called by the ChangeNotifier mechanism
    // For watch_it, this ensures dispose() is called if registered as disposable.
    // No need to call it twice.
  }
}
