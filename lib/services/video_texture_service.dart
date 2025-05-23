import 'package:flutter/foundation.dart';
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/models/video_texture_model.dart';

// Service for managing video texture rendering
class VideoTextureService {
  final Map<String, VideoTextureModel> _textureModels = {};

  // For monitoring and debugging
  final ValueNotifier<int> activeTextureCountNotifier = ValueNotifier(0);

  VideoTextureService() {
    debugPrint('VideoTextureService initialized');
  }

  // Create a new texture model for a specific context/id
  VideoTextureModel createTextureModel(String id) {
    try {
      if (id.isEmpty) {
        debugPrint(
          'Warning: Empty ID provided for texture model, using fallback ID',
        );
        id = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
      }

      if (_textureModels.containsKey(id)) {
        debugPrint('Texture model already exists for id: $id');
        return _textureModels[id]!;
      }

      final model = VideoTextureModel();
      _textureModels[id] = model;
      activeTextureCountNotifier.value = _textureModels.length;
      debugPrint('Created texture model for id: $id');
      return model;
    } catch (e) {
      debugPrint('Error creating texture model: $e');
      // Create a fallback model in case of error
      final fallbackModel = VideoTextureModel();
      return fallbackModel;
    }
  }

  // Get an existing texture model
  VideoTextureModel? getTextureModel(String id) {
    try {
      if (id.isEmpty) return null;

      final model = _textureModels[id];
      if (model == null) {
        debugPrint('Texture model not found for id: $id');
      }
      return model;
    } catch (e) {
      debugPrint('Error getting texture model: $e');
      return null;
    }
  }

  // Remove and dispose a texture model
  void disposeTextureModel(String id) {
    try {
      if (id.isEmpty) return;

      final model = _textureModels.remove(id);
      if (model != null) {
        try {
          model.dispose();
          debugPrint('Disposed texture model for id: $id');
        } catch (e) {
          debugPrint('Error disposing texture model: $e');
        }
        activeTextureCountNotifier.value = _textureModels.length;
      } else {
        debugPrint('No texture model found to dispose for id: $id');
      }
    } catch (e) {
      debugPrint('Error in disposeTextureModel: $e');
    }
  }

  // Dispose all texture models
  void dispose() {
    try {
      debugPrint(
        'Disposing all texture models (count: ${_textureModels.length})',
      );

      // Create a copy of keys to avoid concurrent modification
      final ids = List<String>.from(_textureModels.keys);

      for (final id in ids) {
        try {
          disposeTextureModel(id);
        } catch (e) {
          debugPrint('Error disposing texture model $id: $e');
        }
      }

      _textureModels.clear();
      activeTextureCountNotifier.value = 0;

      // Dispose notifiers
      activeTextureCountNotifier.dispose();

      debugPrint('VideoTextureService disposed successfully');
    } catch (e) {
      debugPrint('Error disposing VideoTextureService: $e');
    }
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
