import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:ffi/ffi.dart'; // Import for malloc

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
        debugPrint("Invalid dimensions for rendering: len=$len, width=$width, height=$height");
        return;
      }
      
      if (_texturePtr == 0) {
        debugPrint("Texture pointer is zero");
        return;
      }
      
      final textureTargetPtr = Pointer.fromAddress(_texturePtr).cast<Void>();
      Native.instance.onRgba(textureTargetPtr, data, len, width, height, strideAlign);
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
    try {
      if (data == nullptr || len <= 0 || width <= 0 || height <= 0) {
        debugPrint("Invalid frame data parameters: len=$len, width=$width, height=$height");
        return;
      }
      
      final texture = _pixelbufferRenderTextures[display];
      if (texture == null) {
        debugPrint("No texture found for display $display");
        return;
      }
      
      texture.renderFrame(data, len, width, height);
    } catch (e) {
      debugPrint("Error rendering frame: $e");
    }
  }
  
  // Overload for Uint8List data
  void renderFrameBytes(int display, Uint8List data, int width, int height) {
    try {
      if (data.isEmpty || width <= 0 || height <= 0) {
        debugPrint("Invalid frame data parameters: dataLength=${data.length}, width=$width, height=$height");
        return;
      }
      
      final texture = _pixelbufferRenderTextures[display];
      if (texture == null) {
        debugPrint("No texture found for display $display");
        return;
      }
      
      if (!texture.isReady) {
        debugPrint("Texture not ready for display $display");
        return;
      }
      
      // Log detailed information about the texture and data
      debugPrint("Rendering to texture: id=${texture.textureId}, ptr=${texture.texturePtr.toRadixString(16)}, " +
                "size=${width}x${height}, data length=${data.length}, first bytes: " +
                "${data.length > 16 ? data.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ') : 'empty'}");
      
      // Try both rendering methods for redundancy
      try {
        // Method 1: Use the texture renderer directly
        final result = texture.textureRenderer.onRgba(
          texture.textureId,
          data,
          height,
          width,
          texture.strideAlign
        );
        
        debugPrint("TextureRenderer.onRgba result: $result");
        
        // Method 2: If the first method fails, try using Native FFI directly
        if (texture.texturePtr > 0) {
          final textureTargetPtr = Pointer.fromAddress(texture.texturePtr).cast<Void>();
          
          // Create a temporary pointer to the data
          final dataLength = data.length;
          final dataPtr = malloc.allocate<Uint8>(dataLength);
          final dataList = dataPtr.asTypedList(dataLength);
          dataList.setAll(0, data);
          
          // Render using Native FFI
          Native.instance.onRgba(
            textureTargetPtr,
            dataPtr,
            dataLength,
            width,
            height,
            texture.strideAlign
          );
          
          // Free the temporary pointer
          malloc.free(dataPtr);
          
          debugPrint("Backup Native FFI rendering completed");
        }
      } catch (renderError) {
        debugPrint("Primary rendering method failed: $renderError, trying fallback...");
        
        // Final fallback: Try with a different stride alignment
        final fallbackStride = texture.strideAlign == 64 ? 1 : 64;
        final result = texture.textureRenderer.onRgba(
          texture.textureId,
          data,
          height,
          width,
          fallbackStride
        );
        
        debugPrint("Fallback rendering with stride=$fallbackStride result: $result");
      }
    } catch (e, stack) {
      debugPrint("Error rendering frame bytes: $e");
      debugPrint("Stack trace: $stack");
    }
  }

  bool isReady(int display) {
    try {
      return _pixelbufferRenderTextures[display]?.isReady ?? false;
    } catch (e) {
      debugPrint("Error checking texture readiness: $e");
      return false;
    }
  }

  void dispose() {
    try {
      debugPrint("Disposing VideoTextureModel");
      
      // Dispose all controls
      for (final control in _control.values) {
        try {
          control.dispose();
        } catch (e) {
          debugPrint("Error disposing control: $e");
        }
      }
      
      // Destroy session (will clean up textures)
      try {
        destroySession();
      } catch (e) {
        debugPrint("Error destroying session during disposal: $e");
      }
      
      debugPrint("VideoTextureModel disposed successfully");
    } catch (e) {
      debugPrint("Error disposing VideoTextureModel: $e");
    }
  }
} 