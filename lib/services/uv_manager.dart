import 'dart:io';
import 'dart:convert'; // Import dart:convert for utf8
import 'package:path_provider/path_provider.dart';
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
      
      // Run the main.py script
      await runMainPythonScript();
    } catch (e, stackTrace) {
      logError(_logTag, e, stackTrace);
      rethrow;
    }
  }
  
  /// Runs the main Python script that's included in the app assets
  /// Runs the main Python script that's included in the app assets
  Future<ProcessResult?> runMainPythonScript() async {
    try {
      const defaultEnvName = 'flipedit_default';
      
      // Ensure default environment exists, create if not
      if (!await doesEnvExist(defaultEnvName)) {
        logInfo(_logTag, 'Creating default Python environment: $defaultEnvName');
        await createVenv(defaultEnvName);
      }
      
      // Ensure dependencies are installed (uv is idempotent, safe to run always)
      logInfo(_logTag, 'Ensuring Python dependencies are installed...');
      try {
        await installPackage('websockets', defaultEnvName);
        await installPackage('opencv-python', defaultEnvName);
        await installPackage('numpy', defaultEnvName);
        logInfo(_logTag, 'Python dependencies check/install complete.');
      } catch (e) {
         logError(_logTag, 'Failed to install Python dependencies: $e');
         // Optionally rethrow or handle the error appropriately
         throw Exception('Failed to install required Python packages.');
      }

      // Get the path to the video_stream_server.py script in assets directory
      final scriptPath = 'assets/video_stream_server.py';
      final scriptFile = File(scriptPath);
      
      if (!await scriptFile.exists()) {
        logError(_logTag, 'Python script not found at: $scriptPath');
        return null;
      }
      
      // Get paths to video assets
      final videoPath1 = 'assets/sample_video_1.mp4';
      final videoPath2 = 'assets/sample_video_2.mp4';
      
      logInfo(_logTag, 'Running Python video stream server script: $scriptPath');
      // Run the script in a separate process without waiting for it to finish
      // since it's a long-running server
      final process = await startPythonScript(defaultEnvName, scriptPath, [
        '--video1', videoPath1,
        '--video2', videoPath2,
        '--host', 'localhost',
        '--port', '8080',
      ]);
      
      logInfo(_logTag, 'Python server process started (PID: ${process.pid})');
      
      // Log stdout and stderr asynchronously
      process.stdout.transform(utf8.decoder).listen((data) {
        logInfo('PythonServer', data.trim());
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        logError('PythonServer', data.trim());
      });
      
      // Return null immediately as the process runs in the background
      return null;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error running Python video server script: $e', stackTrace);
      return null;
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
  
  /// Runs a Python script within a virtual environment and returns the ProcessResult
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
  
  /// Starts a Python script within a virtual environment and returns the Process object
  Future<Process> startPythonScript(String envName, String scriptPath, List<String> args) async {
    String pythonExe;
    if (Platform.isWindows) {
      pythonExe = '$_appDataDir\\venvs\\$envName\\Scripts\\python.exe';
    } else {
      pythonExe = '$_appDataDir/venvs/$envName/bin/python';
    }
    
    logInfo(_logTag, 'Starting script with Python at: $pythonExe');
    return await Process.start(pythonExe, [scriptPath, ...args]);
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