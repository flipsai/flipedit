import 'package:flutter/material.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';
import 'package:fvp/fvp.dart';
// import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FVP/MDK with registerWith
  try {
    print("Initializing FVP/MDK...");
    // Register FVP to be used as the backend for video_player
    registerWith(); // Use default options when integrating with video_player
    print("FVP/MDK Initialized Successfully!");
  } catch (e) {
    print("Error initializing FVP/MDK: $e");
    // Show error dialog to the user
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Initialization Error'),
          content: Text('Failed to initialize video playback: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  // Set up dependency injection
  setupServiceLocator();

  // Ensure TimelineViewModel is accessible to watch_it
  // This line is important to make sure the type is registered
  di.get<TimelineViewModel>();

  // debugRepaintRainbowEnabled = true;

  runApp(FlipEditApp());
}
