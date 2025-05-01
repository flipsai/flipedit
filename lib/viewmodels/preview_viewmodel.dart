import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';
import 'package:flipedit/models/clip.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/playback_service.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/utils/logger.dart' as logger;
import 'package:watch_it/watch_it.dart';

class PreviewViewModel extends ChangeNotifier {
  final String _logTag = 'PreviewViewModel';

  // --- Injected Dependencies (via DI) ---
  late final TimelineViewModel _timelineViewModel;
  late final TimelineNavigationViewModel _timelineNavigationViewModel;
  late final ProjectMetadataService _projectMetadataService;
  late final PlaybackService _playbackService; // Inject PlaybackService

  // --- State Notifiers (Exposed to View) ---
  final ValueNotifier<String?> compositeFramePathNotifier = ValueNotifier(null); // Path to the generated frame image
  final ValueNotifier<bool> isGeneratingFrameNotifier = ValueNotifier(false); // Loading indicator
  final ValueNotifier<List<String>> videoSegmentsNotifier = ValueNotifier([]); // Paths to video segments for continuous playback

  final ValueNotifier<List<ClipModel>> visibleClipsNotifier = ValueNotifier([]);
  final ValueNotifier<Map<int, Rect>> clipRectsNotifier = ValueNotifier({});
  final ValueNotifier<Map<int, Flip>> clipFlipsNotifier = ValueNotifier({});
  final ValueNotifier<int?> selectedClipIdNotifier = ValueNotifier(null);
  final ValueNotifier<int?> firstActiveVideoClipIdNotifier = ValueNotifier(null);
  final ValueNotifier<double> aspectRatioNotifier = ValueNotifier(16.0 / 9.0); // Default
  final ValueNotifier<Size?> containerSizeNotifier = ValueNotifier(null);

  // Snap Lines
  final ValueNotifier<double?> activeHorizontalSnapYNotifier = ValueNotifier(null);
  final ValueNotifier<double?> activeVerticalSnapXNotifier = ValueNotifier(null);

  // Interaction State
  final ValueNotifier<bool> isTransformingNotifier = ValueNotifier(false);

  // --- Getters for simplified access ---
  Size? get containerSize => containerSizeNotifier.value;
  String? get compositeFramePath => compositeFramePathNotifier.value;
  bool get isGeneratingFrame => isGeneratingFrameNotifier.value;

  PreviewViewModel() {
    logger.logInfo('PreviewViewModel initializing...', _logTag);
    // Get dependencies from DI
    _timelineViewModel = di<TimelineViewModel>();
    _timelineNavigationViewModel = di<TimelineNavigationViewModel>();
    _projectMetadataService = di<ProjectMetadataService>();
    _playbackService = di<PlaybackService>(); // Get PlaybackService from DI

   
    logger.logInfo('PreviewViewModel initialized.', _logTag);
  }


}


