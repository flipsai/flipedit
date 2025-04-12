import 'dart:convert';
import 'dart:io';

import 'package:flipedit/comfyui/models/workflow.dart';
import 'package:flipedit/services/uv_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:watch_it/watch_it.dart';
import 'package:flipedit/utils/logger.dart';

/// Service for interacting with ComfyUI
class ComfyUIService {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  final UvManager _uvManager = di<UvManager>();
  
  final ValueNotifier<String?> comfyUIPathNotifier = ValueNotifier<String?>(null);
  String? get comfyUIPath => comfyUIPathNotifier.value;
  set comfyUIPath(String? value) {
    if (comfyUIPathNotifier.value == value) return;
    comfyUIPathNotifier.value = value;
  }
  
  Process? _comfyProcess;
  
  final ValueNotifier<bool> isRunningNotifier = ValueNotifier<bool>(false);
  bool get isRunning => isRunningNotifier.value;
  set isRunning(bool value) {
    if (isRunningNotifier.value == value) return;
    isRunningNotifier.value = value;
  }
  
  final ValueNotifier<String> selectedPythonEnvNotifier = ValueNotifier<String>('');
  String get selectedPythonEnv => selectedPythonEnvNotifier.value;
  set selectedPythonEnv(String value) {
    if (selectedPythonEnvNotifier.value == value) return;
    selectedPythonEnvNotifier.value = value;
  }
  
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Not initialized');
  String get status => statusNotifier.value;
  set status(String value) {
    if (statusNotifier.value == value) return;
    statusNotifier.value = value;
  }
  
  final ValueNotifier<String> serverUrlNotifier = ValueNotifier<String>('http://127.0.0.1:8188');
  String get serverUrl => serverUrlNotifier.value;
  set serverUrl(String value) {
    if (serverUrlNotifier.value == value) return;
    serverUrlNotifier.value = value;
  }
  
  /// Set the path to the ComfyUI installation
  void setComfyUIPath(String path) {
    comfyUIPath = path;
    status = 'Path set: $path';
  }
  
  /// Set the Python environment to use for ComfyUI
  void setPythonEnvironment(String envName) {
    selectedPythonEnv = envName;
    status = 'Python environment set: $envName';
  }
  
  /// Start the ComfyUI server
  Future<bool> startComfyUI() async {
    if (comfyUIPath == null) {
      status = 'ComfyUI path not set';
      return false;
    }
    
    if (selectedPythonEnv.isEmpty) {
      status = 'Python environment not selected';
      return false;
    }
    
    if (isRunning) {
      status = 'ComfyUI is already running';
      return true;
    }
    
    try {
      status = 'Starting ComfyUI...';
      
      // Determine python path based on the selected environment
      String pythonPath;
      if (Platform.isWindows) {
        pythonPath = await _getPythonPathForEnv(selectedPythonEnv);
      } else {
        pythonPath = await _getPythonPathForEnv(selectedPythonEnv);
      }
      
      // Command to start ComfyUI
      final mainPyPath = '$comfyUIPath/main.py';
      
      // Start ComfyUI process
      _comfyProcess = await Process.start(
        pythonPath,
        [mainPyPath, '--listen', '0.0.0.0', '--port', '8188'],
        workingDirectory: comfyUIPath,
      );
      
      // Listen for stdout and stderr
      _comfyProcess!.stdout.transform(utf8.decoder).listen((data) {
        logInfo(_logTag, 'ComfyUI stdout: $data');
        if (data.contains('Starting server')) {
          isRunning = true;
          status = 'ComfyUI running on $serverUrl';
        }
      });
      
      _comfyProcess!.stderr.transform(utf8.decoder).listen((data) {
        logError(_logTag, 'ComfyUI stderr: $data');
        if (data.contains('Error')) {
          status = 'ComfyUI error: $data';
        }
      });
      
      // Handle process exit
      _comfyProcess!.exitCode.then((exitCode) {
        isRunning = false;
        _comfyProcess = null;
        status = 'ComfyUI stopped with exit code: $exitCode';
      });
      
      // Wait a bit to see if the process starts successfully
      await Future.delayed(const Duration(seconds: 5));
      
      if (isRunning) {
        return true;
      } else {
        status = 'Failed to start ComfyUI within timeout';
        return false;
      }
    } catch (e) {
      status = 'Error starting ComfyUI: $e';
      return false;
    }
  }
  
  /// Stop the ComfyUI server
  Future<void> stopComfyUI() async {
    if (!isRunning || _comfyProcess == null) {
      status = 'ComfyUI is not running';
      return;
    }
    
    try {
      status = 'Stopping ComfyUI...';
      
      // Try to gracefully terminate the process
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${_comfyProcess!.pid}', '/F']);
      } else {
        _comfyProcess!.kill();
      }
      
      // Wait for process to exit
      await _comfyProcess!.exitCode;
      
      isRunning = false;
      _comfyProcess = null;
      status = 'ComfyUI stopped';
    } catch (e) {
      status = 'Error stopping ComfyUI: $e';
    }
  }
  
  /// Execute a workflow in ComfyUI
  Future<Map<String, dynamic>?> executeWorkflow(Workflow workflow) async {
    if (!isRunning) {
      status = 'ComfyUI is not running';
      return null;
    }
    
    try {
      status = 'Executing workflow...';
      
      // Convert workflow to JSON
      final workflowJson = workflow.toJson();
      
      // Send workflow to ComfyUI API
      final response = await http.post(
        Uri.parse('$serverUrl/api/queue'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'prompt': workflowJson}),
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        status = 'Workflow queued: ${responseData['prompt_id']}';
        
        // Wait for workflow execution to complete
        final result = await _waitForWorkflowCompletion(responseData['prompt_id']);
        status = 'Workflow completed';
        
        return result;
      } else {
        status = 'Error queuing workflow: ${response.statusCode} - ${response.body}';
        return null;
      }
    } catch (e) {
      status = 'Error executing workflow: $e';
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
        final response = await http.get(Uri.parse('$serverUrl/api/queue'));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          // Check if our prompt is in the running or pending queues
          final isRunning = data['running'].any((item) => item['prompt_id'] == promptId);
          final isPending = data['pending'].any((item) => item['prompt_id'] == promptId);
          
          if (!isRunning && !isPending) {
            // Check for execution result
            final historyResponse = await http.get(Uri.parse('$serverUrl/api/history'));
            
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
        status = 'Workflow execution timed out';
        return null;
      }
      
      return null;
    } catch (e) {
      status = 'Error waiting for workflow completion: $e';
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
    if (selectedPythonEnv.isEmpty) {
      status = 'Python environment not selected';
      return false;
    }
    
    try {
      status = 'Installing ComfyUI...';
      
      // Create destination directory if it doesn't exist
      final directory = Directory(destinationPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // Clone ComfyUI repository
      final cloneResult = await _uvManager.runPythonScript(
        selectedPythonEnv,
        '-c',
        [
          'import os, subprocess; '
          'subprocess.run(["git", "clone", "https://github.com/comfyanonymous/ComfyUI", "${destinationPath.replaceAll("\\", "\\\\")}"]);'
        ],
      );
      
      if (cloneResult.exitCode != 0) {
        status = 'Error cloning ComfyUI repository: ${cloneResult.stderr}';
        return false;
      }
      
      // Install dependencies
      final installResult = await _uvManager.installPackage('torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121', selectedPythonEnv);
      
      if (installResult.exitCode != 0) {
        status = 'Error installing PyTorch: ${installResult.stderr}';
        return false;
      }
      
      // Install ComfyUI requirements
      final requirementsPath = '$destinationPath/requirements.txt';
      final requirementsResult = await _uvManager.runPythonScript(
        selectedPythonEnv,
        '-c',
        [
          'import subprocess; '
          'subprocess.run(["$selectedPythonEnv", "-m", "pip", "install", "-r", "$requirementsPath"]);'
        ],
      );
      
      if (requirementsResult.exitCode != 0) {
        status = 'Error installing ComfyUI requirements: ${requirementsResult.stderr}';
        return false;
      }
      
      comfyUIPath = destinationPath;
      status = 'ComfyUI installed successfully';
      return true;
    } catch (e) {
      status = 'Error installing ComfyUI: $e';
      return false;
    }
  }
}
