import 'package:flipedit/comfyui/comfyui_service.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/viewmodels/app_viewmodel.dart';
import 'package:flipedit/viewmodels/editor_viewmodel.dart';
import 'package:flipedit/viewmodels/project_viewmodel.dart';
import 'package:flipedit/viewmodels/timeline_viewmodel.dart';
import 'package:get_it/get_it.dart' hide di;
import 'package:watch_it/watch_it.dart';

// Global ServiceLocator instance accessible via di<Type>()
final di = GetIt.instance;

/// Setup all service locator registrations
void setupServiceLocator() {
  // Services
  di.registerLazySingleton<UvManager>(() => UvManager());
  di.registerLazySingleton<ComfyUIService>(() => ComfyUIService());

  // ViewModels
  di.registerLazySingleton<AppViewModel>(() => AppViewModel());
  di.registerLazySingleton<ProjectViewModel>(() => ProjectViewModel());
  di.registerLazySingleton<EditorViewModel>(() => EditorViewModel());
  di.registerLazySingleton<TimelineViewModel>(() => TimelineViewModel());
}
