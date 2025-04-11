import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'uv_downloader.dart';

class UvManager {
  late String _uvPath;
  late String _appDataDir;
  
  // Add getter for _uvPath
  String get uvPath => _uvPath;
  
  Future<void> initialize() async {
    try {
      // Get app support directory first
      final appDir = await getApplicationSupportDirectory();
      _appDataDir = appDir.path;
      print('App data directory: $_appDataDir');
      
      // Create a bin directory for our executables
      final binDir = Directory('$_appDataDir/bin');
      if (!await binDir.exists()) {
        print('Creating bin directory: ${binDir.path}');
        await binDir.create(recursive: true);
      }

      // Download and install UV if needed
      if (!await UvDownloader.isUvInstalled()) {
        print('UV not found, downloading...');
        await UvDownloader.downloadAndInstallUv();
        print('UV download completed');
      } else {
        print('UV already installed');
      }

      // Get the UV path
      _uvPath = await UvDownloader.getUvPath();
      print('Using UV at: $_uvPath');

      // Verify that the UV executable exists
      final uvFile = File(_uvPath);
      if (!await uvFile.exists()) {
        print('ERROR: UV executable not found at: $_uvPath');
        throw Exception('UV executable not found after installation');
      } else {
        print('UV executable found and verified at: $_uvPath');
      }

      // Make binary executable on Unix systems
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', _uvPath]);
      }
    } catch (e, stackTrace) {
      print('Error during initialization:');
      print(e);
      print('Stack trace:');
      print(stackTrace);
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
    
    print('Checking if env exists at: $pythonPath');
    final exists = await File(pythonPath).exists();
    print('Python executable exists: $exists');
    
    // On Windows, let's also check the activation script as an alternative
    if (Platform.isWindows && !exists) {
      final activateScript = '$envPath\\Scripts\\activate.bat';
      print('Checking activation script: $activateScript');
      final activateExists = await File(activateScript).exists();
      print('Activation script exists: $activateExists');
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
    
    print('Creating venv at: $envPath');
    print('Using UV at path: $_uvPath');
    
    // Verify that the UV executable exists
    final uvFile = File(_uvPath);
    if (!await uvFile.exists()) {
      print('UV executable not found at: $_uvPath');
      throw Exception('UV executable not found at: $_uvPath');
    }
    
    try {
      final result = await Process.run(_uvPath, ['venv', envPath]);
      print('Create venv stdout: ${result.stdout}');
      print('Create venv stderr: ${result.stderr}');
      
      // Verify the environment was created
      if (!await doesEnvExist(envName)) {
        print('Failed verification: environment not found after creation');
        throw Exception('Failed to create virtual environment');
      }
      
      print('Successfully created and verified venv: $envName');
      return result;
    } catch (e) {
      print('Error creating environment: $e');
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
    
    print('Installing package using Python at: $pythonPath');
    print('Using UV at path: $_uvPath');
    
    // Verify that the UV executable exists
    final uvFile = File(_uvPath);
    if (!await uvFile.exists()) {
      print('UV executable not found at: $_uvPath');
      throw Exception('UV executable not found at: $_uvPath');
    }
    
    try {
      // Install package using uv with the specific python interpreter
      final result = await Process.run(
        _uvPath, 
        ['pip', 'install', packageName, '--python', pythonPath],
        runInShell: true
      );
      
      print('Install command stdout: ${result.stdout}');
      print('Install command stderr: ${result.stderr}');
      
      if (result.exitCode != 0) {
        throw Exception('Package installation failed: ${result.stderr}');
      }
      
      return result;
    } catch (e) {
      print('Error running UV: $e');
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
    
    print('Running script with Python at: $pythonExe');
    return await Process.run(pythonExe, [scriptPath, ...args]);
  }

  Future<List<String>> listVenvs() async {
    final venvsDir = Platform.isWindows
        ? Directory('$_appDataDir\\venvs')
        : Directory('$_appDataDir/venvs');
    
    print('Looking for venvs in: ${venvsDir.path}');
    
    if (!await venvsDir.exists()) {
      print('Directory does not exist: ${venvsDir.path}');
      return [];
    }
    
    final List<String> venvs = [];
    await for (var entity in venvsDir.list()) {
      if (entity is Directory) {
        print('Found directory: ${entity.path}');
        
        // Extract the venv name from the path using proper path handling
        final pathSegments = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final venvName = pathSegments.isNotEmpty ? pathSegments.last : '';
        
        print('Extracted venv name: $venvName');
        
        if (venvName.isNotEmpty && await doesEnvExist(venvName)) {
          print('Verified venv exists: $venvName');
          venvs.add(venvName);
        } else {
          print('Venv does not exist or name is empty: $venvName');
        }
      }
    }
    
    print('Found venvs: $venvs');
    return venvs;
  }
}