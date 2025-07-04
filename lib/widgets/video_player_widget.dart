import 'dart:async';
import 'package:flipedit/src/rust/api/simple.dart';
import 'package:flutter/material.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String leftVideoPath;
  final String rightVideoPath;

  const VideoPlayerWidget({
    super.key,
    required this.leftVideoPath,
    required this.rightVideoPath,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  int? _textureId;
  String? _errorMessage;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final handle = await EngineContext.instance.getEngineHandle();
    final id = playDualVideo(
      filePathLeft: widget.leftVideoPath,
      filePathRight: widget.rightVideoPath,
      engineHandle: handle,
    );
    setState(() => _textureId = id);
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      // _videoPlayer.pause(); // This line is removed as per the edit hint
    } else {
      // _videoPlayer.play(); // This line is removed as per the edit hint
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Error: $_errorMessage'),
          ],
        ),
      );
    }

    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: Texture(textureId: _textureId!),
        ),
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlayPause,
        ),
      ],
    );
  }
}
