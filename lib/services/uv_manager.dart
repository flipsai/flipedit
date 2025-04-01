import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'uv_downloader.dart';

class UvManager {
  late String _uvPath;
  late String _appDataDir;
  
  Future<void> initialize() async {
    try {
      // Get app support directory first
      final appDir = await getApplicationSupportDirectory();
      _appDataDir = appDir.path;
      print('App data directory: $_appDataDir');
      
      // Create a bin directory for our executables
      final binDir = Directory('${_appDataDir}/bin');
      if (!await binDir.exists()) {
        print('Creating bin directory: ${binDir.path}');
        await binDir.create(recursive: true);
      }

      // Download and install UV if needed
      if (!await UvDownloader.isUvInstalled()) {
        print('UV not found, downloading...');
        await UvDownloader.downloadAndInstallUv();
      } else {
        print('UV already installed');
      }

      // Get the UV path
      _uvPath = await UvDownloader.getUvPath();
      print('Using UV at: $_uvPath');

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
    final envPath = '${_appDataDir}/venvs/$envName';
    final pythonPath = Platform.isWindows 
        ? '$envPath/Scripts/python.exe'
        : '$envPath/bin/python';
    return await File(pythonPath).exists();
  }
  
  Future<ProcessResult> createVenv(String envName) async {
    // Create virtual environments within app directory
    final venvsDir = Directory('${_appDataDir}/venvs');
    if (!await venvsDir.exists()) {
      await venvsDir.create(recursive: true);
    }
    
    final envPath = '${venvsDir.path}/$envName';
    final result = await Process.run(_uvPath, ['venv', envPath]);
    
    // Verify the environment was created
    if (!await doesEnvExist(envName)) {
      throw Exception('Failed to create virtual environment');
    }
    
    return result;
  }
  
  Future<ProcessResult> installPackage(String packageName, String envName) async {
    final envPath = '${_appDataDir}/venvs/$envName';
    
    // Get path to python within the virtual environment
    String pythonPath;
    if (Platform.isWindows) {
      pythonPath = '$envPath/Scripts/python.exe';
    } else {
      pythonPath = '$envPath/bin/python';
    }
    
    // Install package using uv with the specific python interpreter
    final result = await Process.run(
      _uvPath, 
      ['pip', 'install', packageName, '--python', pythonPath],
      runInShell: true
    );
    
    if (result.exitCode != 0) {
      throw Exception('Package installation failed: ${result.stderr}');
    }
    
    return result;
  }
  
  String getActivationScript(String envName) {
    if (Platform.isWindows) {
      return '${_appDataDir}/venvs/$envName/Scripts/activate.bat';
    } else {
      return '${_appDataDir}/venvs/$envName/bin/activate';
    }
  }
  
  // Run Python script within a virtual environment
  Future<ProcessResult> runPythonScript(String envName, String scriptPath, List<String> args) async {
    String pythonExe;
    if (Platform.isWindows) {
      pythonExe = '${_appDataDir}/venvs/$envName/Scripts/python.exe';
    } else {
      pythonExe = '${_appDataDir}/venvs/$envName/bin/python';
    }
    
    return await Process.run(pythonExe, [scriptPath, ...args]);
  }

  Future<List<String>> listVenvs() async {
    final venvsDir = Directory('${_appDataDir}/venvs');
    if (!await venvsDir.exists()) {
      return [];
    }
    
    final List<String> venvs = [];
    await for (var entity in venvsDir.list()) {
      if (entity is Directory) {
        final venvName = entity.path.split('/').last;
        if (await doesEnvExist(venvName)) {
          venvs.add(venvName);
        }
      }
    }
    return venvs;
  }
}