import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:watch_it/watch_it.dart';
import '../../../services/video_texture_service.dart';
import '../../../models/video_texture_model.dart';
import '../../utils/video_player_benchmark.dart';
import 'dart:async';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  late final VideoTextureService _textureService;
  late final VideoTextureModel _textureModel;
  
  String? _videoPath;
  bool _isRunning = false;
  BenchmarkResult? _result;
  double _progress = 0.0;
  
  @override
  void initState() {
    super.initState();
    _textureService = di.get<VideoTextureService>();
    _textureModel = _textureService.createTextureModel('benchmark');
    _initializeTexture();
  }
  
  Future<void> _initializeTexture() async {
    await _textureModel.createSession('benchmark', numDisplays: 1);
    setState(() {});
  }
  
  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _videoPath = result.files.single.path;
      });
    }
  }
  
  Future<void> _runBenchmark() async {
    if (_videoPath == null) return;
    
    setState(() {
      _isRunning = true;
      _progress = 0.0;
      _result = null;
    });
    
    // Update progress during benchmark
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRunning) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress = (_progress + 0.01).clamp(0.0, 0.95);
      });
    });
    
    try {
      final result = await VideoPlayerBenchmark.runBenchmark(
        videoPath: _videoPath!,
        textureModel: _textureModel,
        display: 0,
        durationSeconds: 10, // 10 second benchmark
      );
      
      setState(() {
        _result = result;
        _progress = 1.0;
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _result = BenchmarkResult()..error = e.toString();
        _isRunning = false;
      });
    }
  }
  
  @override
  void dispose() {
    _textureService.disposeTextureModel('benchmark');
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Player Benchmark'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Video',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickVideo,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Choose Video'),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _videoPath ?? 'No video selected',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Benchmark controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Benchmark Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Duration: 10 seconds'),
                    const Text('Target FPS: 30'),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _videoPath != null && !_isRunning
                            ? _runBenchmark
                            : null,
                        icon: Icon(_isRunning ? Icons.hourglass_empty : Icons.speed),
                        label: Text(_isRunning ? 'Running...' : 'Run Benchmark'),
                      ),
                    ),
                    if (_isRunning) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _progress),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Results
            if (_result != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Results',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_result!.error != null)
                          Text(
                            'Error: ${_result!.error}',
                            style: const TextStyle(color: Colors.red),
                          )
                        else
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildResultRow(
                                    'Load Time',
                                    '${_result!.loadTimeMs}ms',
                                    _result!.loadTimeMs < 1000 ? Colors.green : Colors.orange,
                                  ),
                                  _buildResultRow(
                                    'Average FPS',
                                    _result!.averageFps.toStringAsFixed(2),
                                    _result!.averageFps >= 29 ? Colors.green : Colors.red,
                                  ),
                                  _buildResultRow(
                                    'FPS Accuracy',
                                    '${_result!.fpsAccuracy.toStringAsFixed(1)}%',
                                    _result!.fpsAccuracy >= 95 ? Colors.green : Colors.orange,
                                  ),
                                  _buildResultRow(
                                    'Frame Drops',
                                    '${_result!.frameDropPercentage.toStringAsFixed(1)}%',
                                    _result!.frameDropPercentage <= 5 ? Colors.green : Colors.red,
                                  ),
                                  _buildResultRow(
                                    'Render Time',
                                    '${(_result!.averageRenderTimeUs / 1000).toStringAsFixed(2)}ms',
                                    _result!.averageRenderTimeUs < 10000 ? Colors.green : Colors.orange,
                                  ),
                                  const Divider(),
                                  const Text(
                                    'Frame Timing Analysis',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  _buildResultRow(
                                    'Min Frame Time',
                                    '${(_result!.minFrameTimeUs / 1000).toStringAsFixed(2)}ms',
                                  ),
                                  _buildResultRow(
                                    'Max Frame Time',
                                    '${(_result!.maxFrameTimeUs / 1000).toStringAsFixed(2)}ms',
                                  ),
                                  _buildResultRow(
                                    'Median Frame Time',
                                    '${(_result!.medianFrameTimeUs / 1000).toStringAsFixed(2)}ms',
                                  ),
                                  _buildResultRow(
                                    'Timing Consistency',
                                    '±${(_result!.frameTimeStdDev / 1000).toStringAsFixed(2)}ms',
                                    _result!.frameTimeStdDev < 5000 ? Colors.green : Colors.orange,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildResultRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
