import 'package:fluent_ui/fluent_ui.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:watch_it/watch_it.dart';

/// Acts as a coordinator for editor-related view models and state.
/// Manages global editor state like selected clips and extensions.
class EditorViewModel {
  String get _logTag => runtimeType.toString();

  final TimelineViewModel _timelineViewModel = di<TimelineViewModel>();
  final TimelineNavigationViewModel _timelineNavigationViewModel =
      di<TimelineNavigationViewModel>();

  final ValueNotifier<String> selectedExtensionNotifier = ValueNotifier<String>(
    'media',
  );
  final ValueNotifier<String?> selectedClipIdNotifier = ValueNotifier<String?>(
    null,
  );
  
  // Notifier for the video URL currently under the playhead
  final ValueNotifier<String?> currentPreviewVideoUrlNotifier =
      ValueNotifier<String?>(null);

  final ValueNotifier<bool> snappingEnabledNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> aspectRatioLockedNotifier = ValueNotifier<bool>(
    true,
  );

  VoidCallback? _timelineFrameListener;
  VoidCallback? _timelineClipsListener;
  VoidCallback? _timelinePlayStateListener;

  // --- Getters ---
  String get selectedExtension => selectedExtensionNotifier.value;
  String? get selectedClipId => selectedClipIdNotifier.value;

  // --- Setters ---
  set selectedExtension(String value) {
    if (selectedExtensionNotifier.value == value) return;
    selectedExtensionNotifier.value = value;
  }

  set selectedClipId(String? value) {
    if (selectedClipIdNotifier.value == value) return;
    selectedClipIdNotifier.value = value;
  }

  EditorViewModel() {
    logInfo(
      _logTag,
      "EditorViewModel initialized.",
    );

    selectedClipIdNotifier.addListener(_syncTimelineClipSelection);
    _timelineViewModel.selectedClipIdNotifier.addListener(
      _syncFromTimelineClipSelection,
    );
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
    currentPreviewVideoUrlNotifier.dispose();
    snappingEnabledNotifier.dispose();
    aspectRatioLockedNotifier.dispose();

    // Remove clip selection sync listeners
    selectedClipIdNotifier.removeListener(_syncTimelineClipSelection);
    _timelineViewModel.selectedClipIdNotifier.removeListener(
      _syncFromTimelineClipSelection,
    );

    if (_timelineFrameListener != null) {
      _timelineNavigationViewModel.currentFrameNotifier.removeListener(
        _timelineFrameListener!,
      );
    }
    if (_timelineClipsListener != null) {
      _timelineViewModel.clipsNotifier.removeListener(
        _timelineClipsListener!,
      );
    }
    if (_timelinePlayStateListener != null) {
      _timelineNavigationViewModel.isPlayingNotifier.removeListener(
        _timelinePlayStateListener!,
      );
    }

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
    logInfo(
      _logTag,
      "Aspect Ratio Lock Toggled: ${aspectRatioLockedNotifier.value}",
    );
  }
}
