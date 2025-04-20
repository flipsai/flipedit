import 'package:flipedit/comfyui/comfyui_service.dart';
import 'package:flipedit/persistence/dao/project_metadata_dao.dart';
import 'package:flipedit/persistence/database/project_metadata_database.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/services/layout_service.dart';
import 'package:flipedit/services/project_database_service.dart';
import 'package:flipedit/services/project_metadata_service.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';

// Use the global di instance provided by watch_it package
// No need to create our own GetIt instance

/// Setup all service locator registrations
/// This function is now async because SharedPreferences requires it.
Future<void> setupServiceLocator() async {
  // Register SharedPreferences asynchronously
  di.registerSingletonAsync<SharedPreferences>(() => SharedPreferences.getInstance());
  // Ensure SharedPreferences is ready before proceeding
  await di.isReady<SharedPreferences>();

  // Remove old database registrations and keep only the new architecture
  // Project Metadata Database (for managing separate project databases)
  di.registerLazySingleton<ProjectMetadataDatabase>(() => ProjectMetadataDatabase());
  di.registerFactory<ProjectMetadataDao>(() => ProjectMetadataDao(di<ProjectMetadataDatabase>()));

  // Services - remove ProjectService and keep only new services
  di.registerLazySingleton<ProjectMetadataService>(() => ProjectMetadataService());
  di.registerLazySingleton<ProjectDatabaseService>(() => ProjectDatabaseService());
  di.registerLazySingleton<UvManager>(() => UvManager());
  di.registerLazySingleton<ComfyUIService>(() => ComfyUIService());
  di.registerLazySingleton<VideoPlayerManager>(() => VideoPlayerManager());
  di.registerLazySingleton<LayoutService>(() => LayoutService());

  // ViewModels
  di.registerLazySingleton<AppViewModel>(() => AppViewModel());
  di.registerLazySingleton<ProjectViewModel>(() => ProjectViewModel(prefs: di<SharedPreferences>()));
  di.registerLazySingleton<EditorViewModel>(() => EditorViewModel());
  
  // Update TimelineViewModel to use ProjectDatabaseService
  di.registerSingleton<TimelineViewModel>(TimelineViewModel(di<ProjectDatabaseService>()));
}
