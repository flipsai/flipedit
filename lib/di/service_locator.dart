import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/canvas_dimensions_service.dart';
import 'package:flipedit/services/command_history_service.dart';
import 'package:flipedit/services/clip_update_service.dart';
import 'package:flipedit/services/playback_service.dart';
import 'package:flipedit/services/timeline_logic_service.dart';
import 'package:flipedit/services/layout_service.dart';
import 'package:flipedit/services/area_dimensions_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/services/media_duration_service.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_state_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_navigation_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flipedit/services/undo_redo_service.dart';
import 'package:flipedit/viewmodels/preview_viewmodel.dart';
import 'package:flipedit/services/video_processing_service.dart';
import 'package:flipedit/services/timeline_processing_service.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/video_texture_service.dart';

// Get the instance of GetIt
Future<void> setupServiceLocator() async {
  // Register SharedPreferences asynchronously
  di.registerSingletonAsync<SharedPreferences>(
    () => SharedPreferences.getInstance(),
  );
  // Ensure SharedPreferences is ready before proceeding
  await di.isReady<SharedPreferences>();

  // Project Metadata Database (for managing separate project databases)
  di.registerLazySingleton<ProjectMetadataDatabase>(
    () => ProjectMetadataDatabase(),
    dispose: (db) async => await db.close(),
  );
  di.registerFactory<ProjectMetadataDao>(
    () => ProjectMetadataDao(di<ProjectMetadataDatabase>()),
  );

  di.registerLazySingleton<ProjectMetadataService>(
    () => ProjectMetadataService(),
  );
  di.registerLazySingleton<ProjectDatabaseService>(
    () => ProjectDatabaseService(),
  );
  di.registerLazySingleton<LayoutService>(() => LayoutService());
  di.registerLazySingleton<AreaDimensionsService>(() => AreaDimensionsService());

  // Register canvas dimensions service
  di.registerLazySingleton<CanvasDimensionsService>(
    () => CanvasDimensionsService(),
    dispose: (service) => service.dispose(),
  );

  // Undo/Redo service for project clips
  di.registerLazySingleton<UndoRedoService>(
    () => UndoRedoService(projectDatabaseService: di<ProjectDatabaseService>()),
  );

  // New minimalist Command History and Clip Update services
  di.registerLazySingleton<CommandHistoryService>(
    () => CommandHistoryService(),
  );
  
  // ClipUpdateService depends on Timeline State ViewModel, register after it
  
  // ViewModels
  di.registerLazySingleton<AppViewModel>(() => AppViewModel());
  di.registerLazySingleton<ProjectViewModel>(
    () => ProjectViewModel(prefs: di<SharedPreferences>()),
  );
  di.registerLazySingleton<EditorViewModel>(() => EditorViewModel());

  // Register the new State ViewModel
  di.registerLazySingleton<TimelineStateViewModel>(
    () => TimelineStateViewModel(),
    dispose: (vm) => vm.dispose(),
  );
  
  // Register ClipUpdateService after TimelineStateViewModel
  di.registerLazySingleton<ClipUpdateService>(
    () => ClipUpdateService(
      historyService: di<CommandHistoryService>(),
      databaseService: di<ProjectDatabaseService>(),
      clipsNotifier: di<TimelineStateViewModel>().clipsNotifier,
    ),
  );

  // Register the Interaction ViewModel (formerly just TimelineViewModel)
  di.registerLazySingleton<TimelineViewModel>(() => TimelineViewModel());

  // Update TimelineNavigationViewModel to use TimelineStateViewModel for data
  di.registerLazySingleton<TimelineNavigationViewModel>(
    () => TimelineNavigationViewModel(
      // Provide the function to get clips from the TimelineStateViewModel instance
      getClips: () => di<TimelineStateViewModel>().clips,
      // Pass the clipsNotifier from the TimelineStateViewModel instance
      clipsNotifier: di<TimelineStateViewModel>().clipsNotifier,
    ),
    dispose: (vm) => vm.dispose(),
  );

  // Register TimelineLogicService
  di.registerLazySingleton<TimelineLogicService>(() => TimelineLogicService());
  di.registerLazySingleton<PreviewViewModel>(
    () => PreviewViewModel(),
    dispose: (vm) => vm.dispose(), // Add dispose for consistency
  );

  di.registerLazySingleton<MediaDurationService>(() => MediaDurationService());
  
  // Register video texture service
  di.registerLazySingleton<VideoTextureService>(
    () => VideoTextureService(),
    dispose: (service) => service.dispose(),
  );

  // Register video processing services
  di.registerLazySingleton<VideoProcessingService>(
    () => VideoProcessingService(),
    dispose: (service) => service.dispose(),
  );
  
  di.registerLazySingleton<TimelineProcessingService>(
    () => TimelineProcessingService(),
    dispose: (service) => service.dispose(),
  );

  di.registerLazySingleton<PlaybackService>(
    () => PlaybackService(
      getCurrentFrame: () => 0,
      setCurrentFrame: (int frame) {},
      getTotalFrames: () => 0,
      getDefaultEmptyDurationFrames: () => 0,
    ),
  );
}
