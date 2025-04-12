import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'uv_downloader.dart';
import 'package:flipedit/utils/logger.dart';

class UvManager {
  // Add a tag for logging within this class
  String get _logTag => runtimeType.toString();

  late String _uvPath;
  late String _appDataDir;
  
  // Add getter for _uvPath
  String get uvPath => _uvPath;
  
  Future<void> initialize() async {
    try {
      // Get app support directory first
      final appDir = await getApplicationSupportDirectory();
      _appDataDir = appDir.path;
      logInfo(_logTag, 'App data directory: $_appDataDir');
      
      // Create a bin directory for our executables
      final binDir = Directory('$_appDataDir/bin');
      if (!await binDir.exists()) {
        logInfo(_logTag, 'Creating bin directory: ${binDir.path}');
        await binDir.create(recursive: true);
      }

      // Download and install UV if needed
      if (!await UvDownloader.isUvInstalled()) {
        logInfo(_logTag, 'UV not found, downloading...');
        await UvDownloader.downloadAndInstallUv();
        logInfo(_logTag, 'UV download completed');
      } else {
        logInfo(_logTag, 'UV already installed');
      }

      // Get the UV path
      _uvPath = await UvDownloader.getUvPath();
      logInfo(_logTag, 'Using UV at: $_uvPath');

      // Verify that the UV executable exists
      final uvFile = File(_uvPath);
      if (!await uvFile.exists()) {
        logError(_logTag, 'ERROR: UV executable not found at: $_uvPath');
        throw Exception('UV executable not found after installation');
      } else {
        logInfo(_logTag, 'UV executable found and verified at: $_uvPath');
      }

      // Make binary executable on Unix systems
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', _uvPath]);
      }
    } catch (e, stackTrace) {
      logError(_logTag, e, stackTrace);
      rethrow;
    }
  }
  
  Future<bool> doesEnvExist(String envName) async {
    final envPath = Platform.isWindows
        ? '$_appDataDir\\venvs\\$envName'
        : '$_appDataDir/venvs/$envName';
    
    final pythonPath = Platform.isWindows 
        ? '$envPath\\Scripts\\python.exe'
        : '$envPath/bin/python';
    
    logDebug(_logTag, 'Checking if env exists at: $pythonPath');
    final exists = await File(pythonPath).exists();
    logDebug(_logTag, 'Python executable exists: $exists');
    
    // On Windows, let's also check the activation script as an alternative
    if (Platform.isWindows && !exists) {
      final activateScript = '$envPath\\Scripts\\activate.bat';
      logDebug(_logTag, 'Checking activation script: $activateScript');
      final activateExists = await File(activateScript).exists();
      logDebug(_logTag, 'Activation script exists: $activateExists');
      return activateExists;
    }
    
    return exists;
  }
  
  Future<ProcessResult> createVenv(String envName) async {
    // Create virtual environments within app directory
    final venvsDir = Platform.isWindows
        ? Directory('$_appDataDir\\venvs')
        : Directory('$_appDataDir/venvs');
    
    if (!await venvsDir.exists()) {
      await venvsDir.create(recursive: true);
    }
    
    final envPath = Platform.isWindows
        ? '${venvsDir.path}\\$envName'
        : '${venvsDir.path}/$envName';
    
    logInfo(_logTag, 'Creating venv at: $envPath');
    logInfo(_logTag, 'Using UV at path: $_uvPath');
    
    // Verify that the UV executable exists
    final uvFile = File(_uvPath);
    if (!await uvFile.exists()) {
      logError(_logTag, 'UV executable not found at: $_uvPath');
      throw Exception('UV executable not found at: $_uvPath');
    }
    
    try {
      final result = await Process.run(_uvPath, ['venv', envPath]);
      logDebug(_logTag, 'Create venv stdout: ${result.stdout}');
      logDebug(_logTag, 'Create venv stderr: ${result.stderr}');
      
      // Verify the environment was created
      if (!await doesEnvExist(envName)) {
        logError(_logTag, 'Failed verification: environment not found after creation');
        throw Exception('Failed to create virtual environment');
      }
      
      logInfo(_logTag, 'Successfully created and verified venv: $envName');
      return result;
    } catch (e) {
      logError(_logTag, 'Error creating environment: $e');
      rethrow;
    }
  }
  
  Future<ProcessResult> installPackage(String packageName, String envName) async {
    final envPath = Platform.isWindows
        ? '$_appDataDir\\venvs\\$envName'
        : '$_appDataDir/venvs/$envName';
    
    // Get path to python within the virtual environment
    String pythonPath;
    if (Platform.isWindows) {
      pythonPath = '$envPath\\Scripts\\python.exe';
    } else {
      pythonPath = '$envPath/bin/python';
    }
    
    logInfo(_logTag, 'Installing package using Python at: $pythonPath');
    logInfo(_logTag, 'Using UV at path: $_uvPath');
    
    // Verify that the UV executable exists
    final uvFile = File(_uvPath);
    if (!await uvFile.exists()) {
      logError(_logTag, 'UV executable not found at: $_uvPath');
      throw Exception('UV executable not found at: $_uvPath');
    }
    
    try {
      // Install package using uv with the specific python interpreter
      final result = await Process.run(
        _uvPath, 
        ['pip', 'install', packageName, '--python', pythonPath],
        runInShell: true
      );
      
      logDebug(_logTag, 'Install command stdout: ${result.stdout}');
      logDebug(_logTag, 'Install command stderr: ${result.stderr}');
      
      if (result.exitCode != 0) {
        throw Exception('Package installation failed: ${result.stderr}');
      }
      
      return result;
    } catch (e) {
      logError(_logTag, 'Error running UV: $e');
      rethrow;
    }
  }
  
  String getActivationScript(String envName) {
    if (Platform.isWindows) {
      return '$_appDataDir\\venvs\\$envName\\Scripts\\activate.bat';
    } else {
      return '$_appDataDir/venvs/$envName/bin/activate';
    }
  }
  
  // Run Python script within a virtual environment
  Future<ProcessResult> runPythonScript(String envName, String scriptPath, List<String> args) async {
    String pythonExe;
    if (Platform.isWindows) {
      pythonExe = '$_appDataDir\\venvs\\$envName\\Scripts\\python.exe';
    } else {
      pythonExe = '$_appDataDir/venvs/$envName/bin/python';
    }
    
    logInfo(_logTag, 'Running script with Python at: $pythonExe');
    return await Process.run(pythonExe, [scriptPath, ...args]);
  }

  Future<List<String>> listVenvs() async {
    final venvsDir = Platform.isWindows
        ? Directory('$_appDataDir\\venvs')
        : Directory('$_appDataDir/venvs');
    
    logDebug(_logTag, 'Looking for venvs in: ${venvsDir.path}');
    
    if (!await venvsDir.exists()) {
      logWarning(_logTag, 'Directory does not exist: ${venvsDir.path}');
      return [];
    }
    
    final List<String> venvs = [];
    await for (var entity in venvsDir.list()) {
      if (entity is Directory) {
        logDebug(_logTag, 'Found directory: ${entity.path}');
        
        // Extract the venv name from the path using proper path handling
        final pathSegments = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final venvName = pathSegments.isNotEmpty ? pathSegments.last : '';
        
        logDebug(_logTag, 'Extracted venv name: $venvName');
        
        if (venvName.isNotEmpty && await doesEnvExist(venvName)) {
          logDebug(_logTag, 'Verified venv exists: $venvName');
          venvs.add(venvName);
        } else {
          logDebug(_logTag, 'Venv does not exist or name is empty: $venvName');
        }
      }
    }
    
    logInfo(_logTag, 'Found venvs: $venvs');
    return venvs;
  }
}