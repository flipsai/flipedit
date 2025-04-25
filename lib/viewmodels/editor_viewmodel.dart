import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/editor/editor_layout_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:docking/docking.dart';
import 'package:watch_it/watch_it.dart';

// Define typedefs for the function types expected by DockingLayout
typedef DockingAreaParser = dynamic Function(DockingArea area);
typedef DockingAreaBuilder = DockingArea? Function(dynamic data);

/// Acts as a coordinator for editor-related view models and state.
/// Delegates layout management to [EditorLayoutManager] and preview control to [EditorPreviewController].
class EditorViewModel {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  // Temporarily commented out LayoutService injection
  // final LayoutService _layoutService = di<LayoutService>();
  
  // Inject TimelineViewModel
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();

  // --- Child Controllers/Managers ---
  final EditorLayoutViewModel layoutManager = EditorLayoutViewModel();

  // --- State Notifiers (Kept in EditorViewModel) ---
  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>('media');
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(null);
  // Keep visibility notifiers for backwards compatibility
  final ValueNotifier<bool> isTimelineVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isInspectorVisibleNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isPreviewVisibleNotifier = ValueNotifier<bool>(true);
  // Notifier for the video URL currently under the playhead
  final ValueNotifier<String?> currentPreviewVideoUrlNotifier = ValueNotifier<String?>(null);

  // Listener for layout changes
  VoidCallback? _layoutListener;
  
  // Subscription to timeline changes
  VoidCallback? _timelineFrameListener;
  VoidCallback? _timelineClipsListener;
  VoidCallback? _timelinePlayStateListener; // Listener for play state

  // --- Getters ---
  String get selectedExtension => selectedExtensionNotifier.value;
  String? get selectedClipId => selectedClipIdNotifier.value;
  DockingLayout? get layout => layoutManager.layout;
  ValueNotifier<DockingLayout?> get layoutNotifier => layoutManager.layoutNotifier;
  bool get isTimelineVisible => layoutManager.isTimelineVisible;
  bool get isInspectorVisible => layoutManager.isInspectorVisible;
  bool get isPreviewVisible => layoutManager.isPreviewVisible;

  // --- Setters ---
  set selectedExtension(String value) {
    if (selectedExtensionNotifier.value == value) return;
    selectedExtensionNotifier.value = value;
  }
  
  set selectedClipId(String? value) {
    if (selectedClipIdNotifier.value == value) return;
    selectedClipIdNotifier.value = value;
  }
  
  // Layout setter is now handled within EditorLayoutManager
  // If external setting is needed, expose a method or setter that calls layoutManager.layout = value

  EditorViewModel() {
    // Initialization of layout and preview is handled within their respective classes' constructors
    logInfo(_logTag, "EditorViewModel initialized. Layout and Preview controllers created.");
  }

  void onDispose() {
    logInfo(_logTag, "Disposing EditorViewModel...");
    // Dispose local notifiers
    selectedExtensionNotifier.dispose();
    selectedClipIdNotifier.dispose();
    isTimelineVisibleNotifier.dispose();
    isInspectorVisibleNotifier.dispose();
    isPreviewVisibleNotifier.dispose();
    currentPreviewVideoUrlNotifier.dispose(); // Dispose new notifier
    
    // Remove timeline listeners
    if (_timelineFrameListener != null) {
      _timelineViewModel.currentFrameNotifier.removeListener(_timelineFrameListener!);
    }
    if (_timelineClipsListener != null) {
       _timelineViewModel.clipsNotifier.removeListener(_timelineClipsListener!); // Assuming clipsNotifier is Listenable
    }
    if (_timelinePlayStateListener != null) { // Remove play state listener
       _timelineViewModel.isPlayingNotifier.removeListener(_timelinePlayStateListener!);
    }
    
    // Remove layout listener
    if (layoutManager.layoutNotifier.value != null && _layoutListener != null) {
      layoutManager.layoutNotifier.value!.removeListener(_layoutListener!);
    }

    // Dispose child controllers/managers
    layoutManager.dispose();
    logInfo(_logTag, "EditorViewModel disposed.");
  }

  // --- Actions ---
  // Toggle timeline visibility using generic method
  void toggleTimeline() => layoutManager.toggleTimeline();
  
  // Toggle inspector visibility using generic method
  void toggleInspector() => layoutManager.toggleInspector();

  void togglePreview() => layoutManager.togglePreview();

  // These are called by Docking widget when the close button on an item is clicked
  void markInspectorClosed() => layoutManager.markInspectorClosed();
  
  void markTimelineClosed() => layoutManager.markTimelineClosed();

  void markPreviewClosed() => layoutManager.markPreviewClosed();
}
