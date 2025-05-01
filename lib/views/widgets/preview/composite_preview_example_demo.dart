import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:flipedit/utils/logger.dart' as logger;
import 'dart:io';
import 'composite_preview_example.dart';
import 'package:fvp/mdk.dart' as mdk;

/// A demo application that showcases the CompositeVideoPreview widget
class CompositePreviewDemo extends StatefulWidget {
  const CompositePreviewDemo({Key? key}) : super(key: key);

  @override
  State<CompositePreviewDemo> createState() => _CompositePreviewDemoState();
}

class _CompositePreviewDemoState extends State<CompositePreviewDemo> {
  // Example video paths - replace with actual paths to your videos
  late String video1Path;
  late String video2Path;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showCustomPathInput = false;
  final TextEditingController _video1Controller = TextEditingController();
  final TextEditingController _video2Controller = TextEditingController();
  
  // Reference to the compositor for controlling playback
  MdkVideoCompositor? _compositor;
  bool _isPlaying = false;
  
  @override
  void initState() {
    super.initState();
    _findVideoPaths();
  }
  
  @override
  void dispose() {
    _video1Controller.dispose();
    _video2Controller.dispose();
    super.dispose();
  }
  
  Future<void> _findVideoPaths() async {
    try {
      // Default to assets paths
      video1Path = 'assets/sample_video_1.mp4';
      video2Path = 'assets/sample_video_2.mp4';
      
      logger.logInfo('Checking if videos exist at default paths', 'CompositePreviewDemo');
      
      // Check if the asset files exist
      final directory = Directory('assets');
      if (await directory.exists()) {
        final entities = await directory.list().toList();
        final fileNames = entities.map((e) => e.path.split('/').last).toList();
        
        logger.logInfo('Found files in assets directory: $fileNames', 'CompositePreviewDemo');
        
        // If any of the sample files don't exist, try to find alternative videos
        if (!fileNames.contains('sample_video_1.mp4') || !fileNames.contains('sample_video_2.mp4')) {
          // Look for any mp4 files
          final videoFiles = entities.where((e) => e.path.endsWith('.mp4')).toList();
          
          if (videoFiles.length >= 2) {
            video1Path = videoFiles[0].path;
            video2Path = videoFiles[1].path;
            logger.logInfo('Using alternative videos: $video1Path, $video2Path', 'CompositePreviewDemo');
          }
        }
      }
      
      // Set the controllers with the found paths
      _video1Controller.text = video1Path;
      _video2Controller.text = video2Path;
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      logger.logError('Error setting up video paths: $e', 'CompositePreviewDemo');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }
  
  void _applyCustomPaths() {
    setState(() {
      video1Path = _video1Controller.text;
      video2Path = _video2Controller.text;
      _showCustomPathInput = false;
      logger.logInfo('Applied custom video paths: $video1Path, $video2Path', 'CompositePreviewDemo');
      _isPlaying = false; // Reset play state when paths change
    });
  }
  
  void _onCompositorCreated(MdkVideoCompositor compositor) {
    _compositor = compositor;
  }
  
  void _togglePlayback() async {
    if (_compositor == null || _compositor!.playerService == null || _compositor!.playerService.player == null) {
      logger.logError('Cannot toggle playback, compositor or player not available', 'CompositePreviewDemo');
      return;
    }
    
    try {
      final player = _compositor!.playerService.player!;
      
      if (_isPlaying) {
        // Pause
        player.state = mdk.PlaybackState.paused;
      } else {
        // Play
        player.state = mdk.PlaybackState.playing;
      }
      
      setState(() {
        _isPlaying = !_isPlaying;
      });
      
      logger.logInfo('Playback toggled to ${_isPlaying ? "playing" : "paused"}', 'CompositePreviewDemo');
    } catch (e) {
      logger.logError('Error toggling playback: $e', 'CompositePreviewDemo');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: fluent_ui.ProgressRing()),
      );
    }
    
    if (_hasError) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: Center(
          child: Text('Error: $_errorMessage', 
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MDK Video Compositor Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              setState(() {
                _showCustomPathInput = !_showCustomPathInput;
              });
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Composite Video Preview using MDK API',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_showCustomPathInput) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _video1Controller,
                      decoration: const InputDecoration(
                        labelText: 'Video 1 Path',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _video2Controller,
                      decoration: const InputDecoration(
                        labelText: 'Video 2 Path',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _applyCustomPaths,
                      child: const Text('Apply Paths'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Video 1: $video1Path\nVideo 2: $video2Path',
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _togglePlayback,
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(_isPlaying ? 'Pause' : 'Play'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CompositeVideoPreview(
                    video1Path: video1Path,
                    video2Path: video2Path,
                    onCompositorCreated: _onCompositorCreated,
                    key: ValueKey('$video1Path-$video2Path'), // Force rebuild when paths change
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'This example shows two videos composited together using MDK\'s API directly.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Run this as a standalone app for testing
void main() {
  runApp(const CompositePreviewDemoApp());
}

class CompositePreviewDemoApp extends StatelessWidget {
  const CompositePreviewDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CompositePreviewDemo(),
    );
  }
} 