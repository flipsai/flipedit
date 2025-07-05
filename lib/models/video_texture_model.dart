import 'dart:ffi';
import 'package:flutter/material.dart';

// Video session ID for managing multiple video streams
class VideoSessionID {
  final String id;
  final int displayIndex;

  VideoSessionID({required this.id, this.displayIndex = 0});

  @override
  String toString() => '${id}_$displayIndex';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoSessionID &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayIndex == other.displayIndex;

  @override
  int get hashCode => id.hashCode ^ displayIndex.hashCode;
}

// Simplified pixel buffer texture implementation
class PixelbufferTexture {
  int _textureKey = -1;
  int _display = 0;
  VideoSessionID? _sessionId;
  bool _destroying = false;
  int? _id;

  int get display => _display;
  int get textureId => _id ?? -1;
  bool get isReady => _id != null && _id != -1;

  Future<void> create(
    int displayIndex,
    VideoSessionID sessionId,
    VideoTextureModel parent,
  ) async {
    _display = displayIndex;
    _textureKey = DateTime.now().millisecondsSinceEpoch + displayIndex;
    _sessionId = sessionId;

    try {
      // Create a simple texture ID
      final id = _textureKey % 1000000;
      _id = id;

      if (id != -1) {
        parent.setRgbaTextureId(display: displayIndex, id: id);
        debugPrint(
          "Created pixelbuffer texture: sessionId=$sessionId display=$_display, textureId=$id",
        );
      } else {
        debugPrint(
          "Failed to create texture for sessionId=$sessionId display=$_display",
        );
      }
    } catch (e) {
      debugPrint("Error creating texture: $e");
    }
  }

  Future<void> destroy(bool unregisterTexture, VideoTextureModel parent) async {
    if (!_destroying && _textureKey != -1 && _sessionId != null) {
      _destroying = true;

      if (unregisterTexture) {
        // Sleep briefly to avoid texture being used after it's unregistered
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _textureKey = -1;
      _destroying = false;

      debugPrint(
        "Destroyed pixelbuffer texture: sessionId=$_sessionId display=$_display, textureId=$_id",
      );
    }
  }

  void renderFrame(Pointer<Uint8> data, int len, int width, int height) {
    try {
      if (!isReady) {
        debugPrint("Texture not ready for rendering");
        return;
      }

      if (data == nullptr) {
        debugPrint("Null data pointer provided for rendering");
        return;
      }

      if (len <= 0 || width <= 0 || height <= 0) {
        debugPrint(
          "Invalid dimensions for rendering: len=$len, width=$width, height=$height",
        );
        return;
      }

      // Placeholder for actual rendering - in a real implementation,
      // this would render the frame data to the texture
      debugPrint("Would render frame: ${width}x$height, $len bytes to texture $_id");
    } catch (e) {
      debugPrint("Error in renderFrame: $e");
    }
  }
}

// Control class to manage texture IDs and types
class _Control {
  final ValueNotifier<int> textureID = ValueNotifier<int>(-1);

  int _rgbaTextureId = -1;
  int get rgbaTextureId => _rgbaTextureId;
  int _gpuTextureId = -1;
  int get gpuTextureId => _gpuTextureId;
  bool _isGpuTexture = false;
  bool get isGpuTexture => _isGpuTexture;

  void setTextureType({bool gpuTexture = false}) {
    _isGpuTexture = gpuTexture;
    textureID.value = _isGpuTexture ? gpuTextureId : rgbaTextureId;
  }

  void setRgbaTextureId(int id) {
    _rgbaTextureId = id;
    if (!_isGpuTexture) {
      textureID.value = id;
    }
  }

  void setGpuTextureId(int id) {
    _gpuTextureId = id;
    if (_isGpuTexture) {
      textureID.value = id;
    }
  }

  void dispose() {
    textureID.dispose();
  }
}

// Simplified video texture model
class VideoTextureModel {
  VideoSessionID? _sessionId;
  final Map<int, PixelbufferTexture> _pixelbufferTextures = {};
  final Map<int, _Control> _control = {};
  int _currentDisplay = 0;

  int get currentDisplay => _currentDisplay;
  List<int> get displays => _control.keys.toList();
  
  ValueNotifier<int>? textureId({required int display}) {
    return _control[display]?.textureID;
  }

  Future<void> setSessionId(VideoSessionID sessionId) async {
    if (_sessionId == sessionId) {
      return; // No change needed
    }

    // Clean up existing session
    if (_sessionId != null) {
      await closeSession();
    }

    _sessionId = sessionId;
    debugPrint("Set video session ID: $sessionId");
  }

  void setTextureType({int? display, required bool gpuTexture}) {
    final targetDisplay = display ?? _currentDisplay;
    debugPrint("setTextureType: display=$targetDisplay, isGpuTexture=$gpuTexture");
    _ensureControlExists(targetDisplay);
    _control[targetDisplay]?.setTextureType(gpuTexture: gpuTexture);
  }

  void _ensureControlExists(int display) {
    if (!_control.containsKey(display)) {
      _control[display] = _Control();
    }
  }

  void setRgbaTextureId({required int display, required int id}) {
    _ensureControlExists(display);
    _control[display]?.setRgbaTextureId(id);
    debugPrint("Set RGBA texture ID for display $display: $id");
  }

  void setGpuTextureId({required int display, required int id}) {
    _ensureControlExists(display);
    _control[display]?.setGpuTextureId(id);
    debugPrint("Set GPU texture ID for display $display: $id");
  }

  Future<void> updatePixelbufferTexture({
    required int display,
    required Pointer<Uint8> data,
    required int len,
    required int width,
    required int height,
  }) async {
    final texture = _pixelbufferTextures[display];
    if (texture == null) {
      debugPrint("No pixelbuffer texture found for display $display");
      return;
    }

    debugPrint(
      "Updating pixelbuffer texture for display $display: ${width}x$height, $len bytes",
    );

    texture.renderFrame(data, len, width, height);
  }

  Future<PixelbufferTexture?> createPixelbufferTexture({
    required int display,
  }) async {
    if (_sessionId == null) {
      debugPrint("Cannot create texture: no session ID set");
      return null;
    }

    if (_pixelbufferTextures.containsKey(display)) {
      debugPrint("Pixelbuffer texture already exists for display $display");
      return _pixelbufferTextures[display];
    }

    final texture = PixelbufferTexture();
    await texture.create(display, _sessionId!, this);
    
    if (texture.textureId != -1) {
      _pixelbufferTextures[display] = texture;
      debugPrint("Created pixelbuffer texture for display $display");
      return texture;
    } else {
      debugPrint("Failed to create pixelbuffer texture for display $display");
      return null;
    }
  }

  Future<void> closeSession() async {
    if (_sessionId == null) return;

    debugPrint("Closing video texture session: $_sessionId");

    // Destroy all pixelbuffer textures
    for (final texture in _pixelbufferTextures.values) {
      await texture.destroy(true, this);
    }
    _pixelbufferTextures.clear();

    // Dispose all controls
    for (final control in _control.values) {
      control.dispose();
    }
    _control.clear();

    _sessionId = null;
    _currentDisplay = 0;
    
    debugPrint("Video texture session closed");
  }

  void dispose() {
    closeSession();
  }
}
