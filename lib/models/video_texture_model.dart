import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';

// Native FFI interface for texture rendering
class Native {
  Native._();

  static Native? _internalInstance;
  static Native get instance {
    _internalInstance ??= Native._().._init();
    return _internalInstance!;
  }

  late final void Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int) _onRgbaFP;

  void _init() {
    final lib = DynamicLibrary.process();
    _onRgbaFP = lib.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32, Int32, Int32),
        void Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int)
      >("FlutterRgbaRendererPluginOnRgba");
  }

  void onRgba(Pointer<Void> texture, Pointer<Uint8> data, int len, int width, int height, int strideAlign) {
    _onRgbaFP(texture, data, len, width, height, strideAlign);
  }
}

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

// Pixel buffer texture implementation
class PixelbufferTexture {
  int _textureKey = -1;
  int _display = 0;
  VideoSessionID? _sessionId;
  bool _destroying = false;
  int? _id;
  int _texturePtr = 0;

  final textureRenderer = TextureRgbaRenderer();
  final strideAlign = Platform.isMacOS ? 64 : 1;

  int get display => _display;
  int get textureId => _id ?? -1;
  int get texturePtr => _texturePtr;
  bool get isReady => _id != null && _id != -1 && _texturePtr != 0;

  Future<void> create(int displayIndex, VideoSessionID sessionId, VideoTextureModel parent) async {
    _display = displayIndex;
    _textureKey = DateTime.now().millisecondsSinceEpoch + displayIndex;
    _sessionId = sessionId;

    try {
      final id = await textureRenderer.createTexture(_textureKey);
      _id = id;
      
      if (id != -1) {
        parent.setRgbaTextureId(display: displayIndex, id: id);
        final ptr = await textureRenderer.getTexturePtr(_textureKey);
        _texturePtr = ptr;
        debugPrint("Created pixelbuffer texture: sessionId=$sessionId display=$_display, textureId=$id, texturePtr=${ptr.toRadixString(16)}");
      } else {
        debugPrint("Failed to create texture for sessionId=$sessionId display=$_display");
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
      
      await textureRenderer.closeTexture(_textureKey);
      _textureKey = -1;
      _texturePtr = 0;
      _destroying = false;
      
      debugPrint("Destroyed pixelbuffer texture: sessionId=$_sessionId display=$_display, textureId=$_id");
    }
  }

  void renderFrame(Pointer<Uint8> data, int len, int width, int height) {
    if (!isReady) {
      debugPrint("Texture not ready for rendering");
      return;
    }

    final textureTargetPtr = Pointer.fromAddress(_texturePtr).cast<Void>();
    Native.instance.onRgba(textureTargetPtr, data, len, width, height, strideAlign);
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

// Main texture model class
class VideoTextureModel {
  final Map<int, _Control> _control = {};
  final Map<int, PixelbufferTexture> _pixelbufferRenderTextures = {};
  
  // Current session information
  VideoSessionID? _currentSessionId;
  
  VideoTextureModel();

  void setTextureType({required int display, required bool gpuTexture}) {
    debugPrint("setTextureType: display=$display, isGpuTexture=$gpuTexture");
    ensureControl(display);
    _control[display]?.setTextureType(gpuTexture: gpuTexture);
  }

  void setRgbaTextureId({required int display, required int id}) {
    ensureControl(display);
    _control[display]?.setRgbaTextureId(id);
  }

  void setGpuTextureId({required int display, required int id}) {
    ensureControl(display);
    _control[display]?.setGpuTextureId(id);
  }

  ValueNotifier<int> getTextureId(int display) {
    ensureControl(display);
    return _control[display]!.textureID;
  }

  void ensureControl(int display) {
    var ctl = _control[display];
    if (ctl == null) {
      ctl = _Control();
      _control[display] = ctl;
    }
  }

  Future<void> createSession(String sessionId, {int numDisplays = 1}) async {
    _currentSessionId = VideoSessionID(id: sessionId);
    
    for (int i = 0; i < numDisplays; i++) {
      await createDisplay(i);
    }
  }

  Future<void> createDisplay(int displayIndex) async {
    if (_currentSessionId == null) {
      debugPrint("No session ID set. Call createSession first.");
      return;
    }

    if (!_pixelbufferRenderTextures.containsKey(displayIndex)) {
      final renderTexture = PixelbufferTexture();
      _pixelbufferRenderTextures[displayIndex] = renderTexture;
      await renderTexture.create(displayIndex, _currentSessionId!, this);
    }
  }

  Future<void> destroyDisplay(int displayIndex) async {
    final control = _control[displayIndex];
    if (control != null) {
      control.dispose();
      _control.remove(displayIndex);
    }
    
    if (_pixelbufferRenderTextures.containsKey(displayIndex)) {
      await _pixelbufferRenderTextures[displayIndex]!.destroy(true, this);
      _pixelbufferRenderTextures.remove(displayIndex);
    }
  }

  Future<void> destroySession() async {
    final displays = _pixelbufferRenderTextures.keys.toList();
    for (final display in displays) {
      await destroyDisplay(display);
    }
    _currentSessionId = null;
  }

  void renderFrame(int display, Pointer<Uint8> data, int len, int width, int height) {
    _pixelbufferRenderTextures[display]?.renderFrame(data, len, width, height);
  }

  bool isReady(int display) {
    return _pixelbufferRenderTextures[display]?.isReady ?? false;
  }

  void dispose() {
    for (final control in _control.values) {
      control.dispose();
    }
    destroySession();
  }
} 