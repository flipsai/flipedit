import 'package:flutter/foundation.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/di/service_locator.dart';

class AppViewModel extends ChangeNotifier {
  final UvManager _uvManager = di<UvManager>();
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  String _statusMessage = "Initializing...";
  String get statusMessage => _statusMessage;
  
  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;
  
  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;
  
  AppViewModel() {
    // Initially set as true to skip environment setup and go directly to the editor
    // In a production app, you'd want to check if all requirements are met
    _isInitialized = true;
    _statusMessage = "Environment ready";
    notifyListeners();
    
    // If you want to enable the Python environment setup again, use this:
    // _initialize();
  }
  
  Future<void> _initialize() async {
    try {
      _isDownloading = true;
      _statusMessage = "Setting up environment...";
      notifyListeners();
      
      await _uvManager.initialize();
      
      _isDownloading = false;
      _isInitialized = true;
      _statusMessage = "Environment setup complete";
      notifyListeners();
    } catch (e) {
      _isDownloading = false;
      _statusMessage = "Failed to initialize: $e";
      notifyListeners();
    }
  }
  
  void updateStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }
  
  void updateDownloadProgress(double progress) {
    _downloadProgress = progress;
    notifyListeners();
  }
}
