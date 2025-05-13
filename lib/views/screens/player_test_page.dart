import 'package:fluent_ui/fluent_ui.dart' as fluent; // Using fluent_ui for page structure
import 'package:flutter/material.dart'; // For Scaffold fallback or specific Material widgets if needed
import 'package:flipedit/views/widgets/player/stream_video_player.dart';

class PlayerTestPage extends StatelessWidget {
  const PlayerTestPage({super.key});

  static const String serverBaseUrl = 'http://localhost:8085';
  static const int initialFrame = 0;
  static const int targetFps = 15; // Let's try a lower FPS for testing

  @override
  Widget build(BuildContext context) {
    // Using fluent.FluentApp elements for consistency if this is part of a Fluent app
    // If not, Scaffold is fine. For a standalone test, Scaffold is simpler.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Player Test Page'),
        backgroundColor: Colors.blueGrey, // A distinct app bar color
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Isolated StreamVideoPlayer Test',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Container(
              width: 640, // Specify a width
              height: 360, // Specify a height
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
              ),
              child: StreamVideoPlayer(
                serverBaseUrl: serverBaseUrl,
                initialFrame: initialFrame,
                autoPlay: false, // Start paused
                showControls: true,
                targetDisplayFps: targetFps, 
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Use player controls to play, pause, and seek.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
} 