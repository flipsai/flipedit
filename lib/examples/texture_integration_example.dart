import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/services/texture_helper.dart';
import 'package:flipedit/utils/logger.dart';

/// Example of how to properly integrate the texture system with video rendering
/// This shows the correct approach for FlipEdit's use case
class VideoTextureRenderer extends StatefulWidget {
  const VideoTextureRenderer({Key? key}) : super(key: key);

  @override
  State<VideoTextureRenderer> createState() => _VideoTextureRendererState();
}

class _VideoTextureRendererState extends State<VideoTextureRenderer> {
  final TextureRgbaRenderer _renderer = TextureRgbaRenderer();
  int _textureId = -1;
  bool _isInitialized = false;
  Timer? _simulationTimer;
  
  static const int _width = 640;
  static const int _height = 480;
  
  @override
  void initState() {
    super.initState();
    _initializeVideoTexture();
  }
  
  Future<void> _initializeVideoTexture() async {
    try {
      logInfo('VideoTextureRenderer', 'Initializing video texture...');
      
      // Create texture for video rendering
      final textureId = await FixedTextureHelper.createTexture(
        _renderer, 
        _width, 
        _height
      );
      
      if (textureId == -1) {
        logError('VideoTextureRenderer', 'Failed to create video texture');
        return;
      }
      
      setState(() {
        _textureId = textureId;
        _isInitialized = true;
      });
      
      logInfo('VideoTextureRenderer', 'Video texture ready with ID: $textureId');
      
      // Start simulating video frames
      _startVideoSimulation();
      
    } catch (e) {
      logError('VideoTextureRenderer', 'Error initializing video texture: $e');
    }
  }
  
  /// Simulate receiving video frames from Python/external source
  void _startVideoSimulation() {
    _simulationTimer = Timer.periodic(Duration(milliseconds: 33), (timer) {
      // Simulate 30 FPS
      _renderSimulatedFrame();
    });
  }
  
  /// This is where you would integrate with your Python video processing
  void _renderSimulatedFrame() {
    if (!_isInitialized) return;
    
    // Generate a simulated video frame
    final frameData = _generateSimulatedVideoFrame(
      _width, 
      _height, 
      DateTime.now().millisecondsSinceEpoch
    );
    
    // Update the texture with the new frame
    // In your real implementation, this frameData would come from Python
    FixedTextureHelper.updateTextureData(_textureId, frameData, _width, _height);
  }
  
  /// Generate a simulated video frame
  /// In your real app, this would be replaced with frames from Python
  Uint8List _generateSimulatedVideoFrame(int width, int height, int timestamp) {
    const bytesPerPixel = 4; // RGBA
    final data = Uint8List(width * height * bytesPerPixel);
    
    // Create animated pattern based on timestamp
    final time = timestamp / 1000.0; // Convert to seconds
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final offset = (y * width + x) * bytesPerPixel;
        
        // Create moving wave pattern
        final wave1 = (128 + 127 * (x / width * 6.28 + time)).round().clamp(0, 255);
        final wave2 = (128 + 127 * (y / height * 6.28 + time * 0.5)).round().clamp(0, 255);
        
        data[offset] = wave1; // R
        data[offset + 1] = wave2; // G
        data[offset + 2] = ((wave1 + wave2) / 2).round(); // B
        data[offset + 3] = 255; // A (fully opaque)
      }
    }
    
    return data;
  }
  
  @override
  void dispose() {
    _simulationTimer?.cancel();
    if (_textureId != -1) {
      FixedTextureHelper.closeTexture(_textureId);
    }
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Video Texture Renderer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: 8),
                Text(
                  'This shows how to properly integrate texture rendering with video data.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          
          if (_isInitialized) ...[
            // Video display area
            Container(
              width: double.infinity,
              height: 300,
              margin: EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: _width / _height,
                  child: Texture(textureId: _textureId),
                ),
              ),
            ),
            
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Texture rendering active',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Resolution: ${_width}x${_height}'),
                  Text('Texture ID: $_textureId'),
                  Text('Frame Rate: ~30 FPS'),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Integration Notes:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Replace _generateSimulatedVideoFrame() with frames from Python\n'
                          '• Call FixedTextureHelper.updateTextureData() when new frames arrive\n'
                          '• The Texture widget will automatically display the updated frames\n'
                          '• No need for native pointers or FFI - just update with RGBA data',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Initializing video texture...'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Example widget showing proper texture cleanup
class TextureCleanupExample extends StatefulWidget {
  @override
  _TextureCleanupExampleState createState() => _TextureCleanupExampleState();
}

class _TextureCleanupExampleState extends State<TextureCleanupExample> {
  final List<int> _activeTextures = [];
  final TextureRgbaRenderer _renderer = TextureRgbaRenderer();
  
  Future<void> _createTestTexture() async {
    final textureId = await FixedTextureHelper.createTexture(_renderer, 100, 100);
    if (textureId != -1) {
      setState(() {
        _activeTextures.add(textureId);
      });
    }
  }
  
  Future<void> _closeTexture(int textureId) async {
    await FixedTextureHelper.closeTexture(textureId);
    setState(() {
      _activeTextures.remove(textureId);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Texture Management Example',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _createTestTexture,
                  child: Text('Create Texture'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _activeTextures.isNotEmpty 
                    ? () => _closeTexture(_activeTextures.last)
                    : null,
                  child: Text('Close Last'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text('Active Textures: ${_activeTextures.length}'),
            if (_activeTextures.isNotEmpty) ...[
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _activeTextures.map((id) => 
                  Chip(
                    label: Text('ID: $id'),
                    onDeleted: () => _closeTexture(id),
                  )
                ).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}