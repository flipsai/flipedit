import 'dart:convert';
import 'dart:io';

import 'package:flipedit/comfyui/models/workflow.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flipedit/di/service_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Service for interacting with ComfyUI
class ComfyUIService extends ChangeNotifier {
  final UvManager _uvManager = di<UvManager>();
  
  String? _comfyUIPath;
  String? get comfyUIPath => _comfyUIPath;
  
  Process? _comfyProcess;
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  
  String _selectedPythonEnv = '';
  String get selectedPythonEnv => _selectedPythonEnv;
  
  String _status = 'Not initialized';
  String get status => _status;
  
  String _serverUrl = 'http://127.0.0.1:8188';
  String get serverUrl => _serverUrl;
  
  /// Set the path to the ComfyUI installation
  void setComfyUIPath(String path) {
    _comfyUIPath = path;
    _status = 'Path set: $path';
    notifyListeners();
  }
  
  /// Set the Python environment to use for ComfyUI
  void setPythonEnvironment(String envName) {
    _selectedPythonEnv = envName;
    _status = 'Python environment set: $envName';
    notifyListeners();
  }
  
  /// Start the ComfyUI server
  Future<bool> startComfyUI() async {
    if (_comfyUIPath == null) {
      _status = 'ComfyUI path not set';
      notifyListeners();
      return false;
    }
    
    if (_selectedPythonEnv.isEmpty) {
      _status = 'Python environment not selected';
      notifyListeners();
      return false;
    }
    
    if (_isRunning) {
      _status = 'ComfyUI is already running';
      notifyListeners();
      return true;
    }
    
    try {
      _status = 'Starting ComfyUI...';
      notifyListeners();
      
      // Determine python path based on the selected environment
      String pythonPath;
      if (Platform.isWindows) {
        pythonPath = await _getPythonPathForEnv(_selectedPythonEnv);
      } else {
        pythonPath = await _getPythonPathForEnv(_selectedPythonEnv);
      }
      
      // Command to start ComfyUI
      final mainPyPath = '$_comfyUIPath/main.py';
      
      // Start ComfyUI process
      _comfyProcess = await Process.start(
        pythonPath,
        [mainPyPath, '--listen', '0.0.0.0', '--port', '8188'],
        workingDirectory: _comfyUIPath,
      );
      
      // Listen for stdout and stderr
      _comfyProcess!.stdout.transform(utf8.decoder).listen((data) {
        print('ComfyUI stdout: $data');
        if (data.contains('Starting server')) {
          _isRunning = true;
          _status = 'ComfyUI running on $_serverUrl';
          notifyListeners();
        }
      });
      
      _comfyProcess!.stderr.transform(utf8.decoder).listen((data) {
        print('ComfyUI stderr: $data');
        if (data.contains('Error')) {
          _status = 'ComfyUI error: $data';
          notifyListeners();
        }
      });
      
      // Handle process exit
      _comfyProcess!.exitCode.then((exitCode) {
        _isRunning = false;
        _comfyProcess = null;
        _status = 'ComfyUI stopped with exit code: $exitCode';
        notifyListeners();
      });
      
      // Wait a bit to see if the process starts successfully
      await Future.delayed(const Duration(seconds: 5));
      
      if (_isRunning) {
        return true;
      } else {
        _status = 'Failed to start ComfyUI within timeout';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = 'Error starting ComfyUI: $e';
      notifyListeners();
      return false;
    }
  }
  
  /// Stop the ComfyUI server
  Future<void> stopComfyUI() async {
    if (!_isRunning || _comfyProcess == null) {
      _status = 'ComfyUI is not running';
      notifyListeners();
      return;
    }
    
    try {
      _status = 'Stopping ComfyUI...';
      notifyListeners();
      
      // Try to gracefully terminate the process
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${_comfyProcess!.pid}', '/F']);
      } else {
        _comfyProcess!.kill();
      }
      
      // Wait for process to exit
      await _comfyProcess!.exitCode;
      
      _isRunning = false;
      _comfyProcess = null;
      _status = 'ComfyUI stopped';
      notifyListeners();
    } catch (e) {
      _status = 'Error stopping ComfyUI: $e';
      notifyListeners();
    }
  }
  
  /// Execute a workflow in ComfyUI
  Future<Map<String, dynamic>?> executeWorkflow(Workflow workflow) async {
    if (!_isRunning) {
      _status = 'ComfyUI is not running';
      notifyListeners();
      return null;
    }
    
    try {
      _status = 'Executing workflow...';
      notifyListeners();
      
      // Convert workflow to JSON
      final workflowJson = workflow.toJson();
      
      // Send workflow to ComfyUI API
      final response = await http.post(
        Uri.parse('$_serverUrl/api/queue'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'prompt': workflowJson}),
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _status = 'Workflow queued: ${responseData['prompt_id']}';
        notifyListeners();
        
        // Wait for workflow execution to complete
        final result = await _waitForWorkflowCompletion(responseData['prompt_id']);
        _status = 'Workflow completed';
        notifyListeners();
        
        return result;
      } else {
        _status = 'Error queuing workflow: ${response.statusCode} - ${response.body}';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _status = 'Error executing workflow: $e';
      notifyListeners();
      return null;
    }
  }
  
  /// Wait for a workflow to complete
  Future<Map<String, dynamic>?> _waitForWorkflowCompletion(String promptId) async {
    try {
      bool isComplete = false;
      int attempts = 0;
      const maxAttempts = 120; // 2 minutes (polling every second)
      
      while (!isComplete && attempts < maxAttempts) {
        final response = await http.get(Uri.parse('$_serverUrl/api/queue'));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          // Check if our prompt is in the running or pending queues
          final isRunning = data['running'].any((item) => item['prompt_id'] == promptId);
          final isPending = data['pending'].any((item) => item['prompt_id'] == promptId);
          
          if (!isRunning && !isPending) {
            // Check for execution result
            final historyResponse = await http.get(Uri.parse('$_serverUrl/api/history'));
            
            if (historyResponse.statusCode == 200) {
              final historyData = json.decode(historyResponse.body);
              
              if (historyData.containsKey(promptId)) {
                return historyData[promptId]['outputs'];
              }
            }
            
            isComplete = true;
          }
        }
        
        attempts++;
        await Future.delayed(const Duration(seconds: 1));
      }
      
      if (attempts >= maxAttempts) {
        _status = 'Workflow execution timed out';
        notifyListeners();
        return null;
      }
      
      return null;
    } catch (e) {
      _status = 'Error waiting for workflow completion: $e';
      notifyListeners();
      return null;
    }
  }
  
  /// Get Python path for the specified environment
  Future<String> _getPythonPathForEnv(String envName) async {
    final appDir = await getApplicationSupportDirectory();
    if (Platform.isWindows) {
      return '${appDir.path}\\venvs\\$envName\\Scripts\\python.exe';
    } else {
      return '${appDir.path}/venvs/$envName/bin/python';
    }
  }
  
  /// Install ComfyUI and its dependencies
  Future<bool> installComfyUI(String destinationPath) async {
    if (_selectedPythonEnv.isEmpty) {
      _status = 'Python environment not selected';
      notifyListeners();
      return false;
    }
    
    try {
      _status = 'Installing ComfyUI...';
      notifyListeners();
      
      // Create destination directory if it doesn't exist
      final directory = Directory(destinationPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Clone ComfyUI repository
      final cloneResult = await _uvManager.runPythonScript(
        _selectedPythonEnv,
        '-c',
        [
          'import os, subprocess; '
          'subprocess.run(["git", "clone", "https://github.com/comfyanonymous/ComfyUI", "${destinationPath.replaceAll("\\", "\\\\")}"]);'
        ],
      );
      
      if (cloneResult.exitCode != 0) {
        _status = 'Error cloning ComfyUI repository: ${cloneResult.stderr}';
        notifyListeners();
        return false;
      }
      
      // Install dependencies
      final installResult = await _uvManager.installPackage('torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121', _selectedPythonEnv);
      
      if (installResult.exitCode != 0) {
        _status = 'Error installing PyTorch: ${installResult.stderr}';
        notifyListeners();
        return false;
      }
      
      // Install ComfyUI requirements
      final requirementsPath = '$destinationPath/requirements.txt';
      final requirementsResult = await _uvManager.runPythonScript(
        _selectedPythonEnv,
        '-c',
        [
          'import subprocess; '
          'subprocess.run(["$_selectedPythonEnv", "-m", "pip", "install", "-r", "$requirementsPath"]);'
        ],
      );
      
      if (requirementsResult.exitCode != 0) {
        _status = 'Error installing ComfyUI requirements: ${requirementsResult.stderr}';
        notifyListeners();
        return false;
      }
      
      _comfyUIPath = destinationPath;
      _status = 'ComfyUI installed successfully';
      notifyListeners();
      return true;
    } catch (e) {
      _status = 'Error installing ComfyUI: $e';
      notifyListeners();
      return false;
    }
  }
}
