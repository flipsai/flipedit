import 'dart:async';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/texture_helper.dart';

class DebugTextureTest extends StatefulWidget {
  const DebugTextureTest({Key? key}) : super(key: key);

  @override
  State<DebugTextureTest> createState() => _DebugTextureTestState();
}

class _DebugTextureTestState extends State<DebugTextureTest> {
  final TextureRgbaRenderer _renderer = TextureRgbaRenderer();
  int _textureId = -1;
  bool _initialized = false;
  String _error = '';
  Timer? _animationTimer;
  int _animationFrame = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeTexture();
  }
  
  Future<void> _initializeTexture() async {
    try {
      logInfo('DebugTextureTest', 'Starting texture initialization...');
      
      // Step 1: Create texture using the fixed helper
      const width = 320;
      const height = 240;
      
      final textureId = await FixedTextureHelper.createTexture(_renderer, width, height);
      
      if (textureId == -1) {
        setState(() {
          _error = 'Failed to create texture';
        });
        return;
      }
      
      // Step 2: Success! The texture is already initialized with a gradient
      setState(() {
        _textureId = textureId;
        _initialized = true;
      });
      
      logInfo('DebugTextureTest', 'Texture initialized successfully with ID: $textureId');
      
      // Step 3: Start color animation
      _startAnimation(width, height);
      
    } catch (e) {
      logError('DebugTextureTest', 'Error initializing texture: $e');
      setState(() {
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _updateTextureWithPattern(int width, int height, Color color) async {
    const bytesPerPixel = 4; // RGBA
    final bytes = Uint8List(width * height * bytesPerPixel);
    
    // Create different patterns based on the color
    if (color == Colors.red) {
      // Solid red
      for (int i = 0; i < width * height; i++) {
        final offset = i * bytesPerPixel;
        bytes[offset] = 255; // R
        bytes[offset + 1] = 0; // G
        bytes[offset + 2] = 0; // B
        bytes[offset + 3] = 255; // A
      }
    } else if (color == Colors.green) {
      // Vertical green stripes
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final offset = (y * width + x) * bytesPerPixel;
          final isStripe = (x ~/ 20) % 2 == 0;
          bytes[offset] = 0; // R
          bytes[offset + 1] = isStripe ? 255 : 100; // G
          bytes[offset + 2] = 0; // B
          bytes[offset + 3] = 255; // A
        }
      }
    } else if (color == Colors.blue) {
      // Horizontal blue stripes
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final offset = (y * width + x) * bytesPerPixel;
          final isStripe = (y ~/ 20) % 2 == 0;
          bytes[offset] = 0; // R
          bytes[offset + 1] = 0; // G
          bytes[offset + 2] = isStripe ? 255 : 100; // B
          bytes[offset + 3] = 255; // A
        }
      }
    } else if (color == Colors.yellow) {
      // Checkerboard pattern
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final offset = (y * width + x) * bytesPerPixel;
          final isChecked = ((x ~/ 20) + (y ~/ 20)) % 2 == 0;
          bytes[offset] = isChecked ? 255 : 100; // R
          bytes[offset + 1] = isChecked ? 255 : 100; // G
          bytes[offset + 2] = 0; // B
          bytes[offset + 3] = 255; // A
        }
      }
    } else {
      // Default gradient (purple)
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final offset = (y * width + x) * bytesPerPixel;
          bytes[offset] = (128 + 127 * sin(x * 0.1)).round(); // R
          bytes[offset + 1] = 0; // G
          bytes[offset + 2] = (128 + 127 * sin(y * 0.1)).round(); // B
          bytes[offset + 3] = 255; // A
        }
      }
    }
    
    logInfo('DebugTextureTest', 'Updating texture with ${color.toString()} pattern');
    final result = await FixedTextureHelper.updateTextureData(_textureId, bytes, width, height);
    if (!result) {
      logError('DebugTextureTest', 'Failed to update texture with ${color.toString()}');
    }
  }

  void _startAnimation(int width, int height) {
    _animationTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // Cycle through colors and patterns
      final colors = [Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.purple];
      final color = colors[_animationFrame % colors.length];
      
      await _updateTextureWithPattern(width, height, color);
      _animationFrame++;
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    if (_textureId != -1) {
      FixedTextureHelper.closeTexture(_textureId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fixed Texture Test'),
        backgroundColor: _initialized ? Colors.green : Colors.red,
        actions: [
          if (_initialized)
            IconButton(
              icon: Icon(Icons.info),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Texture Info'),
                    content: Text(
                      'Texture ID: $_textureId\n'
                      'Animation Frame: $_animationFrame\n'
                      'Active Textures: ${FixedTextureHelper.getActiveTextureIds()}'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_initialized) ...[
              Text(
                'SUCCESS! Texture rendering is working!',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              Container(
                width: 320,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.5),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Texture(textureId: _textureId),
              ),
              SizedBox(height: 16),
              Text(
                'Watch the animated patterns above!',
                style: TextStyle(fontSize: 16),
              ),
            ] else if (_error.isNotEmpty) ...[
              Icon(Icons.error, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text(
                'Error: $_error',
                style: TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = '';
                    _initialized = false;
                  });
                  _initializeTexture();
                },
                child: Text('Retry'),
              ),
            ] else ...[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing texture...'),
            ],
            
            SizedBox(height: 32),
            
            // Manual test buttons
            if (_initialized) ...[
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => _updateTextureWithPattern(320, 240, Colors.red),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: Text('Red', style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: () => _updateTextureWithPattern(320, 240, Colors.green),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: Text('Green', style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: () => _updateTextureWithPattern(320, 240, Colors.blue),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: Text('Blue', style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: () => _updateTextureWithPattern(320, 240, Colors.yellow),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
                    child: Text('Yellow', style: TextStyle(color: Colors.black)),
                  ),
                  ElevatedButton(
                    onPressed: () => _updateTextureWithPattern(320, 240, Colors.purple),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                    child: Text('Purple', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
            
            SizedBox(height: 20),
            
            // Status info
            Card(
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _initialized ? Icons.check_circle : Icons.error,
                          color: _initialized ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _initialized 
                            ? 'Texture system working correctly!'
                            : _error.isNotEmpty 
                              ? 'Texture system failed'
                              : 'Initializing...',
                          style: TextStyle(
                            color: _initialized ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_initialized) ...[
                      SizedBox(height: 8),
                      Text('• Texture ID: $_textureId'),
                      Text('• Animation Frame: $_animationFrame'),
                      Text('• Pattern updates: ${_animationFrame} times'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}