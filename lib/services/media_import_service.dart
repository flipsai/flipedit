import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';

/// A service to handle media import operations
class MediaImportService {
  static const _logTag = 'MediaImportService';
  final ProjectViewModel _projectViewModel;

  MediaImportService(this._projectViewModel);

  /// Displays file picker and imports the selected media file
  /// Returns true if import was successful, false otherwise
  Future<bool> importMediaFromFilePicker(BuildContext context) async {
    logInfo(_logTag, "Opening file picker dialog");
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        String? filePath = result.files.single.path;
        logInfo(_logTag, "File selected: $filePath");
        
        if (filePath != null) {
          try {
            logInfo(_logTag, "Importing file: $filePath");
            final assetId = await _projectViewModel.importMediaAssetCommand(filePath);
            
            if (assetId != null) {
              logInfo(_logTag, "Media imported successfully: $filePath");
              return true;
            } else {
              logError(_logTag, "Failed to import media: Database operation returned null");
              return false;
            }
          } catch (importError) {
            logError(_logTag, "Error importing media: $importError");
            return false;
          }
        } else {
          logWarning(_logTag, "File path is null after picking");
          return false;
        }
      } else {
        logInfo(_logTag, "File picking cancelled or no file selected");
        return false;
      }
    } catch (e) {
      logError(_logTag, "Error picking file: $e");
      return false;
    }
  }
  
  /// Shows a loading indicator overlay
  static OverlayEntry showLoadingOverlay(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).resources.subtleFillColorSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProgressRing(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
    return entry;
  }
  
  /// Shows a notification message
  static void showNotification(
    BuildContext context, 
    String message, 
    {InfoBarSeverity severity = InfoBarSeverity.info}
  ) {
    displayInfoBar(context, builder: (context, close) {
      return InfoBar(
        title: Text(message),
        severity: severity,
        onClose: close,
      );
    });
  }
} 