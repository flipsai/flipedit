import 'package:flutter/material.dart';
import 'package:flipedit/app.dart';
import 'package:flipedit/di/service_locator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up dependency injection
  setupServiceLocator();
  
  // Initialize services if needed
  
  runApp(FlipEditApp());
}
