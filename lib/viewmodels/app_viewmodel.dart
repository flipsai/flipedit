import 'package:flutter/foundation.dart';

class AppViewModel {
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier<bool>(false);
  bool get isInitialized => isInitializedNotifier.value;
  set isInitialized(bool value) {
    if (isInitializedNotifier.value == value) return;
    isInitializedNotifier.value = value;
  }

  final ValueNotifier<String> statusMessageNotifier = ValueNotifier<String>(
    "Initializing...",
  );
  String get statusMessage => statusMessageNotifier.value;
  set statusMessage(String value) {
    if (statusMessageNotifier.value == value) return;
    statusMessageNotifier.value = value;
  }

  final ValueNotifier<bool> isDownloadingNotifier = ValueNotifier<bool>(false);
  bool get isDownloading => isDownloadingNotifier.value;
  set isDownloading(bool value) {
    if (isDownloadingNotifier.value == value) return;
    isDownloadingNotifier.value = value;
  }

  final ValueNotifier<double> downloadProgressNotifier = ValueNotifier<double>(
    0.0,
  );
  double get downloadProgress => downloadProgressNotifier.value;
  set downloadProgress(double value) {
    if (downloadProgressNotifier.value == value || value < 0.0 || value > 1.0) {
      return;
    }
    downloadProgressNotifier.value = value;
  }

  AppViewModel() {
    isInitialized = true;
    statusMessage = "Environment ready";

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      isDownloading = true;
      statusMessage = "Setting up environment...";

      isDownloading = false;
      isInitialized = true;
      statusMessage = "Environment setup complete";
    } catch (e) {
      isDownloading = false;
      statusMessage = "Failed to initialize: $e";
    }
  }

  void updateStatusMessage(String message) {
    statusMessage = message;
  }

  void updateDownloadProgress(double progress) {
    downloadProgress = progress;
  }
}
