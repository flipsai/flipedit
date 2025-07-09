import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flipedit/viewmodels/video_player_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/models/clip_transform.dart';
import 'package:flipedit/widgets/player/clip_transform_overlay.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

class VideoPlayerWidget extends StatefulWidget with WatchItStatefulWidgetMixin {
  const VideoPlayerWidget({
    super.key,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late final VideoPlayerViewModel _viewModel;
  late final TimelineViewModel _timelineViewModel;
  late final CanvasDimensionsService _canvasDimensionsService;
  
  // Zoom and pan state
  final ValueNotifier<double> _zoomLevel = ValueNotifier<double>(1.0);
  final ValueNotifier<Offset> _panOffset = ValueNotifier<Offset>(Offset.zero);
  
  // Preferences key for saving zoom level
  static const String _zoomLevelKey = 'video_player_zoom_level';
  bool _hasLoadedPreferences = false;
  
  // Middle mouse button panning state
  bool _isPanning = false;
  Offset? _panStartPosition;
  Offset? _panStartOffset;

  @override
  void initState() {
    super.initState();
    _viewModel = VideoPlayerViewModel();
    _timelineViewModel = di<TimelineViewModel>();
    _canvasDimensionsService = di<CanvasDimensionsService>();
    _loadZoomPreferences();
    _zoomLevel.addListener(_saveZoomPreferences);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _zoomLevel.removeListener(_saveZoomPreferences);
    _zoomLevel.dispose();
    _panOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: _viewModel.errorMessageNotifier,
      builder: (context, errorMessage, _) {
        if (errorMessage != null) {
          // Log error for debugging
          logError('VideoPlayerWidget', 'Timeline player error: $errorMessage');
          
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text('Error: $errorMessage'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Copy error to clipboard for easy sharing
                    Clipboard.setData(ClipboardData(text: errorMessage));
                  },
                  child: const Text('Copy Error'),
                ),
              ],
            ),
          );
        }

        return ValueListenableBuilder<int?>(
          valueListenable: _viewModel.textureIdNotifier,
          builder: (context, textureId, __) {
            if (textureId == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
                
                return ValueListenableBuilder<double>(
                  valueListenable: _canvasDimensionsService.canvasWidthNotifier,
                  builder: (context, canvasWidth, _) {
                    return ValueListenableBuilder<double>(
                      valueListenable: _canvasDimensionsService.canvasHeightNotifier,
                      builder: (context, canvasHeight, _) {
                        final videoSize = Size(canvasWidth, canvasHeight);
                        
                        // Auto-fit zoom when preferences are loaded and canvas dimensions are available
                        if (_hasLoadedPreferences && videoSize.width > 0 && videoSize.height > 0) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _calculateAutoFitZoom(videoSize, screenSize);
                          });
                        }
                        
                        return ValueListenableBuilder<double>(
                          valueListenable: _zoomLevel,
                          builder: (context, zoomLevel, _) {
                            return ValueListenableBuilder<Offset>(
                              valueListenable: _panOffset,
                              builder: (context, panOffset, _) {
                                return Listener(
                                  onPointerSignal: (event) {
                                    if (event is PointerScrollEvent) {
                                      if (HardwareKeyboard.instance.isControlPressed) {
                                        _handleZoom(event.scrollDelta.dy, event.localPosition, screenSize);
                                      }
                                    }
                                  },
                                  onPointerDown: (event) {
                                    if (event.buttons == 4) { // Middle mouse button
                                      _startPanning(event.localPosition);
                                    }
                                  },
                                  onPointerMove: (event) {
                                    if (_isPanning && event.buttons == 4) { // Middle mouse button
                                      _updatePanning(event.localPosition);
                                    }
                                  },
                                  onPointerUp: (event) {
                                    if (_isPanning) {
                                      _endPanning();
                                    }
                                  },
                                  onPointerCancel: (event) {
                                    if (_isPanning) {
                                      _endPanning();
                                    }
                                  },
                                  child: MouseRegion(
                                    cursor: _isPanning ? SystemMouseCursors.grabbing : SystemMouseCursors.basic,
                                    child: Container(
                                      width: screenSize.width,
                                      height: screenSize.height,
                                      color: Colors.black,
                                    child: Stack(
                                      children: [
                                        // Figma-like canvas - fixed size texture in scrollable area
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.vertical,
                                            child: Container(
                                              width: screenSize.width.clamp(videoSize.width, double.infinity),
                                              height: screenSize.height.clamp(videoSize.height, double.infinity),
                                              child: Stack(
                                                children: [
                                                  // Center the fixed-size canvas with unified transform
                                                  Positioned(
                                                    left: (screenSize.width - videoSize.width) / 2,
                                                    top: (screenSize.height - videoSize.height) / 2,
                                                    child: Transform(
                                                      alignment: Alignment.center,
                                                      transform: Matrix4.identity()
                                                        ..scale(zoomLevel)
                                                        ..translate(panOffset.dx / zoomLevel, panOffset.dy / zoomLevel),
                                                      child: Stack(
                                                        children: [
                                                          // Video texture
                                                          Container(
                                                            width: videoSize.width,
                                                            height: videoSize.height,
                                                            decoration: BoxDecoration(
                                                              border: Border.all(color: Colors.grey.shade600, width: 1),
                                                            ),
                                                            child: ClipRect(
                                                              child: FittedBox(
                                                                fit: BoxFit.fill,
                                                                child: SizedBox(
                                                                  width: videoSize.width,
                                                                  height: videoSize.height,
                                                                  child: Texture(textureId: textureId),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          // Transform overlay for selected clip - now in same transform space
                                                          IgnorePointer(
                                                            ignoring: _isPanning, // Ignore pointer events during panning
                                                            child: ValueListenableBuilder<int?>(
                                                              valueListenable: _timelineViewModel.selectedClipIdNotifier,
                                                              builder: (context, selectedClipId, _) {
                                                                if (selectedClipId == null) return const SizedBox.shrink();
                                                                
                                                                final selectedClip = _timelineViewModel.clips
                                                                    .where((clip) => clip.databaseId == selectedClipId)
                                                                    .firstOrNull;
                                                                
                                                                if (selectedClip == null) return const SizedBox.shrink();
                                                                
                                                                return ClipTransformOverlay(
                                                                  clip: selectedClip,
                                                                  videoSize: videoSize,
                                                                  screenSize: videoSize, // Use video size since we're in canvas space
                                                                  onTransformChanged: (transform) {
                                                                    _updateClipTransform(selectedClipId, transform);
                                                                  },
                                                                  onTransformStart: () {
                                                                    logDebug('Transform started for clip $selectedClipId', 'VideoPlayerWidget');
                                                                  },
                                                                  onTransformEnd: () {
                                                                    logDebug('Transform ended for clip $selectedClipId', 'VideoPlayerWidget');
                                                                  },
                                                                  onDeselect: () {
                                                                    _timelineViewModel.selectedClipId = null;
                                                                    logDebug('Deselected clip $selectedClipId', 'VideoPlayerWidget');
                                                                  },
                                                                );
                                                              }
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                );
                              },
                            );
                          },
                        );
                      },
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

  void _updateClipTransform(int clipId, ClipTransform transform) {
    // Use the existing updateClipPreviewTransform method
    _timelineViewModel.updateClipPreviewTransform(
      clipId,
      transform.x,
      transform.y,
      transform.width,
      transform.height,
    );
  }
  
  void _handleZoom(double scrollDelta, Offset localPosition, Size screenSize) {
    const double zoomSensitivity = 0.001;
    const double minZoom = 0.1;
    const double maxZoom = 5.0;
    
    final double zoomChange = -scrollDelta * zoomSensitivity;
    final double newZoom = (_zoomLevel.value + zoomChange).clamp(minZoom, maxZoom);
    
    if (newZoom != _zoomLevel.value) {
      // Calculate zoom center relative to screen center
      final Offset screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
      final Offset zoomCenter = localPosition - screenCenter;
      
      // Adjust pan offset to zoom towards cursor position
      final double zoomRatio = newZoom / _zoomLevel.value;
      final Offset newPanOffset = _panOffset.value * zoomRatio + zoomCenter * (1 - zoomRatio);
      
      _zoomLevel.value = newZoom;
      _panOffset.value = newPanOffset;
      
      logDebug('Zoom: ${newZoom.toStringAsFixed(2)}x, Pan: ${newPanOffset.dx.toStringAsFixed(1)}, ${newPanOffset.dy.toStringAsFixed(1)}', 'VideoPlayerWidget');
    }
  }
  
  // Load zoom preferences from SharedPreferences
  Future<void> _loadZoomPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedZoom = prefs.getDouble(_zoomLevelKey);
      
      if (savedZoom != null) {
        _zoomLevel.value = savedZoom;
        logDebug('Loaded zoom level from preferences: ${savedZoom.toStringAsFixed(2)}x', 'VideoPlayerWidget');
      }
    } catch (e) {
      logError('VideoPlayerWidget', 'Error loading zoom preferences: $e');
    } finally {
      _hasLoadedPreferences = true;
    }
  }
  
  // Save zoom preferences to SharedPreferences
  Future<void> _saveZoomPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_zoomLevelKey, _zoomLevel.value);
      logDebug('Saved zoom level to preferences: ${_zoomLevel.value.toStringAsFixed(2)}x', 'VideoPlayerWidget');
    } catch (e) {
      logError('VideoPlayerWidget', 'Error saving zoom preferences: $e');
    }
  }
  
  // Calculate auto-fit zoom to show the entire canvas
  void _calculateAutoFitZoom(Size videoSize, Size screenSize) {
    if (_zoomLevel.value != 1.0) {
      // Don't auto-fit if user has already changed zoom from default
      return;
    }
    
    // Calculate zoom to fit the entire canvas within the screen with some padding
    const padding = 40.0; // Padding around the canvas
    final availableWidth = screenSize.width - padding;
    final availableHeight = screenSize.height - padding;
    
    final scaleX = availableWidth / videoSize.width;
    final scaleY = availableHeight / videoSize.height;
    
    // Use the smaller scale to ensure the entire canvas fits
    final autoFitZoom = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 1.0);
    
    if (autoFitZoom < 1.0) {
      _zoomLevel.value = autoFitZoom;
      _panOffset.value = Offset.zero; // Reset pan when auto-fitting
      logDebug('Auto-fit zoom calculated: ${autoFitZoom.toStringAsFixed(2)}x for canvas ${videoSize.width.toInt()}x${videoSize.height.toInt()} in screen ${screenSize.width.toInt()}x${screenSize.height.toInt()}', 'VideoPlayerWidget');
    }
  }
  
  // Start middle mouse button panning
  void _startPanning(Offset position) {
    setState(() {
      _isPanning = true;
    });
    _panStartPosition = position;
    _panStartOffset = _panOffset.value;
    logDebug('Started panning at ${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)}', 'VideoPlayerWidget');
  }
  
  // Update panning based on mouse movement
  void _updatePanning(Offset currentPosition) {
    if (_panStartPosition != null && _panStartOffset != null) {
      final delta = currentPosition - _panStartPosition!;
      _panOffset.value = _panStartOffset! + delta;
      logDebug('Panning to ${_panOffset.value.dx.toStringAsFixed(1)}, ${_panOffset.value.dy.toStringAsFixed(1)}', 'VideoPlayerWidget');
    }
  }
  
  // End panning
  void _endPanning() {
    setState(() {
      _isPanning = false;
    });
    _panStartPosition = null;
    _panStartOffset = null;
    logDebug('Ended panning', 'VideoPlayerWidget');
  }
}
