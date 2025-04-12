import 'package:flipedit/comfyui/comfyui_service.dart';
import 'package:flipedit/persistence/dao/clip_dao.dart';
import 'package:flipedit/persistence/dao/project_dao.dart';
import 'package:flipedit/persistence/dao/project_asset_dao.dart';
import 'package:flipedit/persistence/dao/track_dao.dart';
import 'package:flipedit/persistence/database/app_database.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/services/layout_service.dart';
import 'package:flipedit/services/project_service.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:flipedit/services/video_player_manager.dart';
import 'package:watch_it/watch_it.dart';

// Use the global di instance provided by watch_it package
// No need to create our own GetIt instance

/// Setup all service locator registrations
void setupServiceLocator() {
  // Database
  di.registerLazySingleton<AppDatabase>(() => AppDatabase());
  di.registerLazySingleton<ProjectDao>(() => di<AppDatabase>().projectDao);
  di.registerLazySingleton<TrackDao>(() => di<AppDatabase>().trackDao);
  di.registerLazySingleton<ClipDao>(() => di<AppDatabase>().clipDao);
  di.registerLazySingleton<ProjectAssetDao>(() => di<AppDatabase>().projectAssetDao);

  // Services
  di.registerLazySingleton<ProjectService>(() => ProjectService());
  di.registerLazySingleton<UvManager>(() => UvManager());
  di.registerLazySingleton<ComfyUIService>(() => ComfyUIService());
  di.registerLazySingleton<VideoPlayerManager>(() => VideoPlayerManager());
  di.registerLazySingleton<LayoutService>(() => LayoutService());

  // ViewModels
  di.registerLazySingleton<AppViewModel>(() => AppViewModel());
  di.registerLazySingleton<ProjectViewModel>(() => ProjectViewModel());
  di.registerLazySingleton<EditorViewModel>(() => EditorViewModel());
  di.registerSingleton<TimelineViewModel>(TimelineViewModel(di(), di()));
}
