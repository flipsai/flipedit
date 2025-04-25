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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/services/undo_redo_service.dart';

Future<void> setupServiceLocator() async {
  // Register SharedPreferences asynchronously
  di.registerSingletonAsync<SharedPreferences>(() => SharedPreferences.getInstance());
  // Ensure SharedPreferences is ready before proceeding
  await di.isReady<SharedPreferences>();

  // Project Metadata Database (for managing separate project databases)
  di.registerLazySingleton<ProjectMetadataDatabase>(
    () => ProjectMetadataDatabase(),
    dispose: (db) async => await db.close(),
  );
  di.registerFactory<ProjectMetadataDao>(() => ProjectMetadataDao(di<ProjectMetadataDatabase>()));

  // Services - remove ProjectService and keep only new services
  di.registerLazySingleton<ProjectMetadataService>(() => ProjectMetadataService());
  di.registerLazySingleton<ProjectDatabaseService>(() => ProjectDatabaseService());
  di.registerLazySingleton<UvManager>(() => UvManager());
  di.registerLazySingleton<ComfyUIService>(() => ComfyUIService());
  di.registerLazySingleton<LayoutService>(() => LayoutService());

  // Undo/Redo service for project clips
  di.registerLazySingleton<UndoRedoService>(
    () => UndoRedoService(
      projectDatabaseService: di<ProjectDatabaseService>(),
    ),
  );

  // ViewModels
  di.registerLazySingleton<AppViewModel>(() => AppViewModel());
  di.registerLazySingleton<ProjectViewModel>(() => ProjectViewModel(prefs: di<SharedPreferences>()));
  di.registerLazySingleton<EditorViewModel>(() => EditorViewModel());

  // Update TimelineViewModel to use ProjectDatabaseService
  di.registerLazySingleton<TimelineViewModel>(() => TimelineViewModel());
}
