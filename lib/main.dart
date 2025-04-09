import 'package:flutter/material.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:watch_it/watch_it.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up dependency injection
  setupServiceLocator();
  
  // Ensure TimelineViewModel is accessible to watch_it
  // This line is important to make sure the type is registered
  di.get<TimelineViewModel>();
  
  runApp(FlipEditApp());
}
