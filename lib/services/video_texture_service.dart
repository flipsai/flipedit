import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/video_texture_model.dart';

// Service for managing video texture rendering
class VideoTextureService {
  final Map<String, VideoTextureModel> _textureModels = {};
  
  VideoTextureService();
  
  // Create a new texture model for a specific context/id
  VideoTextureModel createTextureModel(String id) {
    if (_textureModels.containsKey(id)) {
      debugPrint('Texture model already exists for id: $id');
      return _textureModels[id]!;
    }
    
    final model = VideoTextureModel();
    _textureModels[id] = model;
    return model;
  }
  
  // Get an existing texture model
  VideoTextureModel? getTextureModel(String id) {
    return _textureModels[id];
  }
  
  // Remove and dispose a texture model
  void disposeTextureModel(String id) {
    final model = _textureModels.remove(id);
    model?.dispose();
  }
  
  // Dispose all texture models
  void dispose() {
    for (final model in _textureModels.values) {
      model.dispose();
    }
    _textureModels.clear();
  }
}

// Extension to add to your service locator setup
extension VideoTextureServiceLocator on GetIt {
  void registerVideoTextureService() {
    registerLazySingleton<VideoTextureService>(
      () => VideoTextureService(),
      dispose: (service) => service.dispose(),
    );
  }
} 