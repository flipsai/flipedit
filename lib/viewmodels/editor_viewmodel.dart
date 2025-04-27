import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart'; // Added import
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
  
  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  // Inject TimelineNavigationViewModel
  final TimelineNavigationViewModel _timelineNavigationViewModel = di<TimelineNavigationViewModel>();

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

  // State for snapping and aspect ratio lock (moved from PreviewPanel)
  final ValueNotifier<bool> snappingEnabledNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> aspectRatioLockedNotifier = ValueNotifier<bool>(true);

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
    
    // Set up two-way binding between EditorViewModel and TimelineViewModel clip selection
    selectedClipIdNotifier.addListener(_syncTimelineClipSelection);
    _timelineViewModel.selectedClipIdNotifier.addListener(_syncFromTimelineClipSelection);
  }

  // Synchronize TimelineViewModel's selectedClipId when EditorViewModel's selectedClipId changes
  void _syncTimelineClipSelection() {
    final selectedClipIdString = selectedClipIdNotifier.value;
    if (selectedClipIdString == null) {
      _timelineViewModel.selectedClipId = null;
      return;
    }
    
    try {
      final clipId = int.parse(selectedClipIdString);
      if (_timelineViewModel.selectedClipId != clipId) {
        _timelineViewModel.selectedClipId = clipId;
      }
    } catch (e) {
      logWarning(_logTag, "Could not parse clip ID: $selectedClipIdString");
    }
  }

  // Synchronize EditorViewModel's selectedClipId when TimelineViewModel's selectedClipId changes
  void _syncFromTimelineClipSelection() {
    final timelineClipId = _timelineViewModel.selectedClipId;
    if (timelineClipId == null) {
      if (selectedClipIdNotifier.value != null) {
        selectedClipIdNotifier.value = null;
      }
      return;
    }
    
    final clipIdString = timelineClipId.toString();
    if (selectedClipIdNotifier.value != clipIdString) {
      selectedClipIdNotifier.value = clipIdString;
    }
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
    snappingEnabledNotifier.dispose(); // Dispose snapping notifier
    aspectRatioLockedNotifier.dispose(); // Dispose aspect ratio notifier
    
    // Remove clip selection sync listeners
    selectedClipIdNotifier.removeListener(_syncTimelineClipSelection);
    _timelineViewModel.selectedClipIdNotifier.removeListener(_syncFromTimelineClipSelection);
    
    // Remove timeline listeners (update to use TimelineNavigationViewModel where appropriate)
    if (_timelineFrameListener != null) {
      _timelineNavigationViewModel.currentFrameNotifier.removeListener(_timelineFrameListener!); // Use navigation VM
    }
    if (_timelineClipsListener != null) {
       _timelineViewModel.clipsNotifier.removeListener(_timelineClipsListener!); // Clips are still on TimelineViewModel
    }
    if (_timelinePlayStateListener != null) {
       _timelineNavigationViewModel.isPlayingNotifier.removeListener(_timelinePlayStateListener!); // Use navigation VM
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
  
  /// Toggles the snapping feature state.
  void toggleSnapping() {
    snappingEnabledNotifier.value = !snappingEnabledNotifier.value;
    logInfo(_logTag, "Snapping Toggled: ${snappingEnabledNotifier.value}");
  }
  
  /// Toggles the aspect ratio lock feature state.
  void toggleAspectRatioLock() {
    aspectRatioLockedNotifier.value = !aspectRatioLockedNotifier.value;
    logInfo(_logTag, "Aspect Ratio Lock Toggled: ${aspectRatioLockedNotifier.value}");
  }
  
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
