import 'package:http/http.dart' as http;
import '../viewmodels/timeline_navigation_viewmodel.dart';
import '../services/preview_service.dart';
import '../utils/logger.dart';

class PreviewHttpService {
  final TimelineNavigationViewModel _timelineNavViewModel;
  final PreviewService _previewService;
  final String _logTag = 'PreviewHttpService';

  // Assuming the Python server runs on localhost and the port defined in preview_server.py
  // TODO: Make this configurable if necessary
  final String _baseUrl = 'http://localhost:5001';

  PreviewHttpService({
    required TimelineNavigationViewModel timelineNavViewModel,
    required PreviewService previewService,
  })  : _timelineNavViewModel = timelineNavViewModel,
        _previewService = previewService;

  /// Fetches the current frame from the Python HTTP server and updates the PreviewService.
  Future<void> fetchAndUpdateFrame() async {
    // Get the current frame from the correct ViewModel
    final currentFrame = _timelineNavViewModel.currentFrameNotifier.value;

    final url = Uri.parse('$_baseUrl/get_frame/$currentFrame');

    logInfo('Fetching frame $currentFrame from $url', _logTag);

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5)); // Add timeout

      if (response.statusCode == 200) {
        logInfo('Received frame $currentFrame successfully.', _logTag);
        // Update the PreviewService with the new frame data
        _previewService.updatePreviewFrameFromBytes(response.bodyBytes); // Use correct service and method
      } else {
        logWarning(
            'Failed to fetch frame $currentFrame. Status: ${response.statusCode}, Body: ${response.body}', _logTag);
        // Optionally clear the preview or show an error state
         _previewService.clearPreviewFrame(); // Use correct service and method
      }
    } catch (e, stackTrace) { // Capture stack trace for better error logging
      logError('Error fetching frame $currentFrame', e, stackTrace, _logTag);
       _previewService.clearPreviewFrame(); // Use correct service and method
    }
  }
}