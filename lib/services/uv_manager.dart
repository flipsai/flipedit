import 'dart:io';
import 'dart:convert'; // Import dart:convert for utf8
import 'dart:ffi';
import 'dart:async'; // Import for Completer
import 'package:path_provider/path_provider.dart';
import 'package:texture_rgba_renderer/texture_rgba_renderer.dart';
import 'uv_downloader.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flipedit/services/texture_helper.dart';

import 'package:web_socket_channel/io.dart'; // Import for IOWebSocketChannel

// FFI bridge for texture sharing
typedef CopyFrameToTextureNative =
    Void Function(
      Pointer<Void> srcFrameData,
      Pointer<Void> destTexturePtr,
      Int32 width,
      Int32 height,
    );
typedef CopyFrameToTexture =
    void Function(
      Pointer<Void> srcFrameData,
      Pointer<Void> destTexturePtr,
      int width,
      int height,
    );

class PythonProcessOutput {
  final Process process;
  final Stream<String> stdoutBroadcast;
  final Stream<String> stderrBroadcast;

  PythonProcessOutput({
    required this.process,
    required this.stdoutBroadcast,
    required this.stderrBroadcast,
  });
}

class UvManager {
  String get _logTag => runtimeType.toString();

  late String _uvPath;
  late String _appDataDir;

  // Texture rendering
  final TextureRgbaRenderer _textureRenderer = TextureRgbaRenderer();
  TextureRgbaRenderer get textureRenderer => _textureRenderer;
  int _textureId = -1;
  int _texturePtr = 0;
  int _width = 1920; // Default width
  int _height = 1080; // Default height

  // FFI library
  DynamicLibrary? _textureBridge;
  CopyFrameToTexture? _copyFrameToTextureFunc;

  String get uvPath => _uvPath;
  int get textureId => _textureId;

  // Communication settings
  static const String _controlSocketPath = 'texture_control';

  Future<int> initializeTextureSharing({
    required int width,
    required int height,
  }) async {
    try {
      _width = width;
      _height = height;

      logInfo(
        _logTag,
        'Initializing texture sharing with width=$width, height=$height',
      );

      // Use the new FixedTextureHelper approach - no need for texture pointers
      _textureId = await FixedTextureHelper.createTexture(
        _textureRenderer,
        width,
        height,
      );

      // For backward compatibility, set texturePtr to 0 (not used anymore)
      _texturePtr = 0;

      if (_textureId == -1) {
        logError(
          _logTag,
          'Failed to initialize texture via FixedTextureHelper. TextureId: $_textureId',
        );
        return -1; // Signal failure
      }

      logInfo(
        _logTag,
        'TextureHelper provided TextureId: $_textureId and TexturePtr: $_texturePtr',
      );
      // The redundant _textureRenderer.createTexture call is now removed.
      // _textureId from TextureHelper is the one associated with _texturePtr.

      // Load the texture bridge library
      logInfo(_logTag, 'Loading texture bridge library');
      await _loadTextureBridge();

      // Note: With the new texture approach, we don't send texture pointers to Python
      // Instead, Python should send frame data TO Flutter via WebSocket
      // This is a breaking change that requires updating the Python integration
      logInfo(
        _logTag,
        'Texture initialized - Python integration needs to be updated',
      );
      logInfo(
        _logTag,
        'Python should now send frame data TO Flutter, not write to texture pointers',
      );

      // For backward compatibility, still try to send the old way but with ptr=0
      await _sendTexturePtrToPython(0, _width, _height);

      return _textureId;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error initializing texture sharing: $e', stackTrace);
      return -1;
    }
  }

  Future<void> _loadTextureBridge() async {
    try {
      final libraryPath =
          Platform.isWindows
              ? '$_appDataDir\\bin\\texture_bridge.dll'
              : Platform.isMacOS
              ? '$_appDataDir/bin/libtexture_bridge.dylib'
              : '$_appDataDir/bin/libtexture_bridge.so';

      logInfo(_logTag, 'Looking for texture bridge library at: $libraryPath');
      final libraryFile = File(libraryPath);

      if (!await libraryFile.exists()) {
        logError(_logTag, 'Texture bridge library not found at: $libraryPath');
        // Try to copy from project's bin directory if it exists there
        final projectBinDir = Directory('bin');
        if (await projectBinDir.exists()) {
          final projectLibraryPath =
              Platform.isWindows
                  ? 'bin\\texture_bridge.dll'
                  : Platform.isMacOS
                  ? 'bin/libtexture_bridge.dylib'
                  : 'bin/libtexture_bridge.so';

          final projectLibraryFile = File(projectLibraryPath);
          if (await projectLibraryFile.exists()) {
            logInfo(
              _logTag,
              'Found texture bridge in project bin directory, copying to app data',
            );
            await projectLibraryFile.copy(libraryPath);
            logInfo(_logTag, 'Copied texture bridge library to app data');
          }
        }

        // Check if library exists now
        if (!await libraryFile.exists()) {
          logError(
            _logTag,
            'Could not find texture bridge library, please run build_texture_bridge.sh manually',
          );
          return;
        }
      }

      logInfo(_logTag, 'Found texture bridge library, attempting to load it');

      try {
        _textureBridge = DynamicLibrary.open(libraryPath);
        logInfo(_logTag, 'Texture bridge library loaded successfully');

        // Look up the copyFrameToTexture function
        logInfo(_logTag, 'Looking up copyFrameToTexture function');
        _copyFrameToTextureFunc = _textureBridge!
            .lookupFunction<CopyFrameToTextureNative, CopyFrameToTexture>(
              'copyFrameToTexture',
            );
        logInfo(_logTag, 'Successfully loaded copyFrameToTexture function');
      } catch (e, stackTrace) {
        logError(
          _logTag,
          'Error loading texture bridge library: $e',
          stackTrace,
        );
        rethrow; // Rethrow to be caught by the outer catch
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error loading texture bridge: $e', stackTrace);
    }
  }

  Future<void> _sendTexturePtrToPython(
    int texturePtr,
    int width,
    int height,
  ) async {
    try {
      // Create a command to pass the texture pointer to Python
      final command = {
        'command': 'set_texture_ptr',
        'texture_ptr': texturePtr,
        'width': width,
        'height': height,
      };

      logInfo(
        _logTag,
        'Preparing to send texture info via WebSocket: $command',
      );

      // Wait for the Python server to start (it might take a moment)
      logInfo(_logTag, 'Waiting for Python WebSocket server to be ready...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Try to connect with retries
      IOWebSocketChannel? channel;
      int retryCount = 0;
      const maxRetries = 5;

      while (channel == null && retryCount < maxRetries) {
        try {
          // Send via WebSocket (using existing WebSocket connection)
          logInfo(
            _logTag,
            'Connecting to WebSocket server at ws://localhost:8080 (attempt ${retryCount + 1})',
          );
          channel = IOWebSocketChannel.connect(
            Uri.parse('ws://localhost:8080'),
            pingInterval: const Duration(seconds: 1),
          );

          // Wait for the connection to establish
          logInfo(_logTag, 'Waiting for WebSocket connection to establish...');
          await channel.ready;
          logInfo(_logTag, 'WebSocket connection established');
        } catch (e) {
          retryCount++;
          logWarning(
            _logTag,
            'Failed to connect to WebSocket server (attempt $retryCount): $e',
          );
          if (retryCount < maxRetries) {
            // Wait before retrying with exponential backoff
            final delayMs = 500 * (1 << retryCount);
            logInfo(_logTag, 'Retrying in $delayMs ms...');
            await Future.delayed(Duration(milliseconds: delayMs));
          } else {
            logError(
              _logTag,
              'Failed to establish WebSocket connection after $maxRetries attempts: $e',
            );
            rethrow;
          }
        }
      }

      if (channel == null) {
        throw Exception('Failed to connect to WebSocket server');
      }

      // Send the texture pointer info
      logInfo(_logTag, 'Sending texture pointer data through WebSocket');
      channel.sink.add(jsonEncode(command));
      logInfo(_logTag, 'Sent texture pointer data: ${jsonEncode(command)}');

      // Close the connection
      logInfo(_logTag, 'Closing WebSocket connection');
      await channel.sink.close();
      logInfo(_logTag, 'WebSocket connection closed');
    } catch (e, stackTrace) {
      logError(
        _logTag,
        'Error sending texture pointer to Python: $e',
        stackTrace,
      );
      rethrow; // Rethrow to ensure the initialization process knows about the failure
    }
  }

  Future<void> disposeTexture() async {
    try {
      if (_textureId != -1) {
        // Tell Python to stop writing to the texture
        final command = {
          'command': 'dispose_texture',
          'texture_ptr': _texturePtr,
        };

        // Send via WebSocket
        final channel = IOWebSocketChannel.connect(
          Uri.parse('ws://localhost:8080'),
        );

        await channel.ready;
        channel.sink.add(jsonEncode(command));
        await channel.sink.close();

        // Close the texture using the fixed helper
        // Note: With the new approach, we track by textureId, not pointer
        if (_textureId != -1) {
          await FixedTextureHelper.closeTexture(_textureId);
        }

        // Also close directly with renderer
        await _textureRenderer.closeTexture(_textureId);

        _textureId = -1;
        _texturePtr = 0;

        logInfo(_logTag, 'Disposed texture');
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error disposing texture: $e', stackTrace);
    }
  }

  Future<void> initialize() async {
    try {
      // Get app support directory first
      final appDir = await getApplicationSupportDirectory();
      _appDataDir = appDir.path;
      logInfo(_logTag, 'App data directory: $_appDataDir');

      // Check if app directory exists and is writable
      final appDirEntity = Directory(_appDataDir);
      if (!await appDirEntity.exists()) {
        logError(_logTag, 'App data directory does not exist: $_appDataDir');
        try {
          await appDirEntity.create(recursive: true);
          logInfo(_logTag, 'Created app data directory: $_appDataDir');
        } catch (e) {
          logError(_logTag, 'Failed to create app data directory: $e');
          throw Exception('Failed to create app data directory');
        }
      }

      // Check if app directory is writable by writing a test file
      try {
        final testFile = File('$_appDataDir/write_test.txt');
        await testFile.writeAsString('Write test');
        await testFile.delete();
        logInfo(_logTag, 'App data directory is writable');
      } catch (e) {
        logError(_logTag, 'App data directory is not writable: $e');
        throw Exception('App data directory is not writable');
      }

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

      // Check Python version
      final pythonVersion = await _checkPythonVersion();
      logInfo(_logTag, 'Python version: $pythonVersion');

      // Run the main.py script and get the process and its broadcast streams
      final processOutput = await runMainPythonScript();
      if (processOutput == null) {
        logError(
          _logTag,
          'Failed to start Python server process or get its output streams',
        );
        throw Exception('Failed to start Python server process');
      }
      final serverProcess =
          processOutput.process; // Keep for reference if needed
      final stdoutBroadcast = processOutput.stdoutBroadcast; // Use this stream

      // Wait for the server to start listening
      final completer = Completer<void>();
      bool isServerReady = false;

      // Listen for the "server listening" message on the provided broadcast stream
      final StreamSubscription<String> stdoutSubscription = stdoutBroadcast
          .listen((data) {
            if (data.contains('server listening on') && !isServerReady) {
              isServerReady = true;
              logInfo(_logTag, 'Python WebSocket server is ready');
              if (!completer.isCompleted) {
                completer.complete();
              }
            }
          });

      // Set a timeout to prevent hanging if the server never starts
      final timer = Timer(const Duration(seconds: 10), () {
        // Increased timeout slightly
        if (!completer.isCompleted) {
          logWarning(
            _logTag,
            'Timed out waiting for Python server to start, continuing anyway',
          );
          stdoutSubscription
              .cancel(); // Cancel the subscription to avoid late events
          completer
              .complete(); // Complete to allow initialization to proceed or fail gracefully
        }
      });

      // Wait for the server to be ready or timeout
      try {
        await completer.future;
      } finally {
        timer.cancel(); // Cancel the timer if completer finishes early
        // Keep the subscription if server started, or cancel if it timed out (already done in timer)
        // If it timed out and didn't become ready, stdoutSubscription was already cancelled.
        // If it completed successfully, we want to keep the subscription for further logs if needed,
        // or it can be cancelled if no longer needed after this point.
        // For now, we'll assume the main stdout logging in runMainPythonScript is sufficient
        // and the one in initialize was only for the readiness check.
        if (isServerReady && !stdoutSubscription.isPaused) {
          // Check if still active
          // If we want to stop listening after readiness:
          // stdoutSubscription.cancel();
        } else if (!isServerReady) {
          // Already cancelled by timer if it timed out.
          // If completer completed with an error before timeout, cancel now.
          if (!stdoutSubscription.isPaused) stdoutSubscription.cancel();
        }
      }
    } catch (e, stackTrace) {
      logError(_logTag, e, stackTrace);
      rethrow;
    }
  }

  Future<String> _checkPythonVersion() async {
    try {
      const defaultEnvName = 'flipedit_default';

      // Ensure default environment exists, create if not
      if (!await doesEnvExist(defaultEnvName)) {
        logInfo(
          _logTag,
          'Creating default Python environment: $defaultEnvName',
        );
        await createVenv(defaultEnvName);
      }

      // Get Python executable path
      String pythonExe;
      if (Platform.isWindows) {
        pythonExe = '$_appDataDir\\venvs\\$defaultEnvName\\Scripts\\python.exe';
      } else {
        pythonExe = '$_appDataDir/venvs/$defaultEnvName/bin/python';
      }

      // Check Python version
      final result = await Process.run(pythonExe, ['-V']);
      final version = result.stdout.toString().trim();

      return version;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error checking Python version: $e', stackTrace);
      return 'Unknown';
    }
  }

  Future<Map<String, String>> _checkPythonDependencies() async {
    try {
      const defaultEnvName = 'flipedit_default';
      final result = <String, String>{};

      // Get Python executable path
      String pythonExe;
      if (Platform.isWindows) {
        pythonExe = '$_appDataDir\\venvs\\$defaultEnvName\\Scripts\\python.exe';
      } else {
        pythonExe = '$_appDataDir/venvs/$defaultEnvName/bin/python';
      }

      // Check each dependency
      for (final package in [
        'websockets',
        'opencv-python',
        'numpy',
        'flask',
        'sqlalchemy',
      ]) {
        try {
          final checkResult = await Process.run(pythonExe, [
            '-c',
            'import $package; print($package.__version__)',
          ]);

          final version = checkResult.stdout.toString().trim();
          if (version.isNotEmpty) {
            result[package] = version;
          } else {
            result[package] = 'Installed (unknown version)';
          }
        } catch (e) {
          result[package] = 'Not installed';
        }
      }

      return result;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error checking Python dependencies: $e', stackTrace);
      return {'error': e.toString()};
    }
  }

  Future<PythonProcessOutput?> runMainPythonScript() async {
    try {
      const defaultEnvName = 'flipedit_default';

      logInfo(
        _logTag,
        'Attempting to run main Python script with environment: $defaultEnvName',
      );

      // Ensure default environment exists, create if not
      logInfo(_logTag, 'Checking if environment exists: $defaultEnvName');
      if (!await doesEnvExist(defaultEnvName)) {
        logInfo(
          _logTag,
          'Environment does not exist, creating: $defaultEnvName',
        );
        await createVenv(defaultEnvName);
      } else {
        logInfo(_logTag, 'Environment already exists: $defaultEnvName');
      }

      // Ensure dependencies are installed (uv is idempotent, safe to run always)
      logInfo(_logTag, 'Ensuring Python dependencies are installed...');
      try {
        await installPackage('websockets', defaultEnvName);
        await installPackage('opencv-python', defaultEnvName);
        await installPackage('numpy', defaultEnvName);
        await installPackage('flask', defaultEnvName);
        await installPackage('sqlalchemy', defaultEnvName);
        logInfo(_logTag, 'Python dependencies check/install complete.');
      } catch (e) {
        logError(_logTag, 'Failed to install Python dependencies: $e');
        // Optionally rethrow or handle the error appropriately
        throw Exception('Failed to install required Python packages.');
      }

      // Get the path to the video_stream_server.py script in assets directory
      final scriptPath = 'assets/main.py';
      logInfo(_logTag, 'Looking for Python script at: $scriptPath');

      final scriptFile = File(scriptPath);

      if (!await scriptFile.exists()) {
        logError(_logTag, 'Python script not found at: $scriptPath');
        return null;
      }

      logInfo(_logTag, 'Found Python script, preparing to run: $scriptPath');

      // Attempt to kill any existing processes on the target ports before starting
      logInfo(_logTag, 'Checking for processes using port 8080');
      await _killProcessOnPort(8080); // WebSocket server port
      logInfo(_logTag, 'Checking for processes using port 8085');
      await _killProcessOnPort(8085); // HTTP streaming server port

      // Run the script in a separate process without waiting for it to finish
      // since it's a long-running server
      logInfo(
        _logTag,
        'Starting Python script with arguments: --host 0.0.0.0 --ws-port 8080',
      );
      final process = await startPythonScript(defaultEnvName, scriptPath, [
        // Use the arguments defined in video_stream_server.py
        '--host',
        '0.0.0.0',
        '--ws-port',
        '8080',
      ]);

      logInfo(_logTag, 'Python server process started (PID: ${process.pid})');

      // Convert stdout and stderr to broadcast streams for multiple listeners
      final stdoutBroadcast =
          process.stdout.transform(utf8.decoder).asBroadcastStream();
      final stderrBroadcast =
          process.stderr.transform(utf8.decoder).asBroadcastStream();

      // Log stdout and stderr asynchronously
      stdoutBroadcast.listen((data) {
        final lines = data.trim().split('\n');
        for (var line in lines) {
          if (line.contains("server listening on")) {
            logInfo('PythonServer', "WebSocket server is now listening: $line");
          } else {
            logInfo('PythonServer', line);
          }
        }
      });

      stderrBroadcast.listen((data) {
        final lines = data.trim().split('\n');
        for (var line in lines) {
          if (line.contains("ERROR")) {
            logError('PythonServer', line);
          } else {
            logInfo('PythonServer', line);
          }
        }
      });

      // Return the process object and its broadcast streams
      return PythonProcessOutput(
        process: process,
        stdoutBroadcast: stdoutBroadcast,
        stderrBroadcast: stderrBroadcast,
      );
    } catch (e, stackTrace) {
      logError(
        _logTag,
        'Error running Python video server script: $e',
        stackTrace,
      );
      return null;
    }
  }

  Future<bool> doesEnvExist(String envName) async {
    final envPath =
        Platform.isWindows
            ? '$_appDataDir\\venvs\\$envName'
            : '$_appDataDir/venvs/$envName';

    final pythonPath =
        Platform.isWindows
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
    final venvsDir =
        Platform.isWindows
            ? Directory('$_appDataDir\\venvs')
            : Directory('$_appDataDir/venvs');

    if (!await venvsDir.exists()) {
      await venvsDir.create(recursive: true);
    }

    final envPath =
        Platform.isWindows
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
        logError(
          _logTag,
          'Failed verification: environment not found after creation',
        );
        throw Exception('Failed to create virtual environment');
      }

      logInfo(_logTag, 'Successfully created and verified venv: $envName');
      return result;
    } catch (e) {
      logError(_logTag, 'Error creating environment: $e');
      rethrow;
    }
  }

  Future<ProcessResult> installPackage(
    String packageName,
    String envName,
  ) async {
    final envPath =
        Platform.isWindows
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
      final result = await Process.run(_uvPath, [
        'pip',
        'install',
        packageName,
        '--python',
        pythonPath,
      ], runInShell: true);

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
  Future<ProcessResult> runPythonScript(
    String envName,
    String scriptPath,
    List<String> args,
  ) async {
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
  Future<Process> startPythonScript(
    String envName,
    String scriptPath,
    List<String> args,
  ) async {
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
    final venvsDir =
        Platform.isWindows
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
        final pathSegments =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
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

  Future<void> shutdownVideoStreamServer() async {
    logInfo(_logTag, 'Attempting to shut down video stream server...');
    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://localhost:8080'),
      );

      // Wait for the connection to establish (optional, but good practice)
      await channel.ready;

      logInfo(_logTag, 'Connected to WebSocket server for shutdown.');

      // Send the shutdown command
      channel.sink.add('shutdown');
      logInfo(_logTag, 'Sent "shutdown" command to server.');

      // Close the WebSocket connection
      await channel.sink.close();
      logInfo(_logTag, 'WebSocket connection closed.');
    } catch (e, stackTrace) {
      logError(
        _logTag,
        'Error shutting down video stream server via WebSocket: $e',
        stackTrace,
      );
    }
  }

  Future<void> _killProcessOnPort(int port) async {
    logInfo(
      _logTag,
      'Checking if port $port is in use and attempting to kill process if necessary...',
    );
    bool killed = false;

    try {
      if (Platform.isWindows) {
        // Windows: Find PID using netstat, then kill using taskkill
        final netstatResult = await Process.run('netstat', [
          '-ano',
          '|',
          'findstr',
          ':$port',
        ]);
        if (netstatResult.exitCode == 0 &&
            netstatResult.stdout.toString().isNotEmpty) {
          final lines = netstatResult.stdout.toString().split('\n');
          for (var line in lines) {
            if (line.contains('LISTENING')) {
              final parts = line.trim().split(RegExp(r'\s+'));
              if (parts.length >= 5) {
                final pid = parts.last;
                logInfo(
                  _logTag,
                  'Found process with PID $pid listening on port $port. Attempting to kill...',
                );
                final killResult = await Process.run('taskkill', [
                  '/PID',
                  pid,
                  '/F',
                ]);
                if (killResult.exitCode == 0) {
                  logInfo(
                    _logTag,
                    'Successfully killed process with PID $pid.',
                  );
                  killed = true;
                } else {
                  logWarning(
                    _logTag,
                    'Failed to kill process with PID $pid. Stderr: ${killResult.stderr}',
                  );
                }
                // Assuming one process per port for simplicity here
                break;
              }
            }
          }
        } else {
          logInfo(_logTag, 'Port $port appears to be free (netstat check).');
        }
      } else {
        // macOS/Linux: Find PID using lsof, then kill
        final lsofResult = await Process.run('lsof', ['-ti', ':$port']);
        if (lsofResult.exitCode == 0 &&
            lsofResult.stdout.toString().trim().isNotEmpty) {
          final pid = lsofResult.stdout.toString().trim();
          logInfo(
            _logTag,
            'Found process with PID $pid using port $port. Attempting to kill...',
          );
          final killResult = await Process.run('kill', ['-9', pid]);
          if (killResult.exitCode == 0) {
            logInfo(_logTag, 'Successfully killed process with PID $pid.');
            killed = true;
          } else {
            logWarning(
              _logTag,
              'Failed to kill process with PID $pid. Stderr: ${killResult.stderr}',
            );
          }
        } else {
          logInfo(_logTag, 'Port $port appears to be free (lsof check).');
        }
      }

      if (killed) {
        await Future.delayed(const Duration(milliseconds: 500));
        logInfo(_logTag, 'Waited briefly after killing process.');
      }
    } catch (e, stackTrace) {
      logError(
        _logTag,
        'Error checking/killing process on port $port: $e',
        stackTrace,
      );
    }
  }

  // Method to test texture creation directly
  Future<int> testCreateTexture() async {
    try {
      final textureKey = DateTime.now().millisecondsSinceEpoch;
      logInfo(_logTag, 'Testing texture creation with key: $textureKey');

      // Use the new FixedTextureHelper approach - simpler and more reliable
      final testTextureId = await FixedTextureHelper.createTexture(
        _textureRenderer,
        320, // Small test size
        240,
      );

      // Check for failure
      if (testTextureId == -1) {
        logError(
          _logTag,
          'Test texture creation failed. TextureId: $testTextureId',
        );
        return -1; // Signal failure
      }

      logInfo(_logTag, 'Test successful - got TextureId: $testTextureId');

      // Close the texture using the fixed helper
      // Note: With the new approach, we don't need texture pointers
      if (testTextureId != -1) {
        await FixedTextureHelper.closeTexture(testTextureId);
      }

      // Return the textureId as the result of the test, consistent with Future<int>
      return testTextureId;
    } catch (e, stackTrace) {
      logError(_logTag, 'Error in test texture creation: $e', stackTrace);
      return -1;
    }
  }

  // Diagnostic method to check server status
  Future<Map<String, dynamic>> checkPythonServerStatus() async {
    final result = <String, dynamic>{
      'server_running': false,
      'python_available': false,
      'texture_bridge_available': false,
      'websocket_responding': false,
      'errors': <String>[],
    };

    try {
      // Check Python availability
      try {
        const defaultEnvName = 'flipedit_default';
        String pythonExe;
        if (Platform.isWindows) {
          pythonExe =
              '$_appDataDir\\venvs\\$defaultEnvName\\Scripts\\python.exe';
        } else {
          pythonExe = '$_appDataDir/venvs/$defaultEnvName/bin/python';
        }

        final pythonFile = File(pythonExe);
        if (await pythonFile.exists()) {
          final pythonCheck = await Process.run(pythonExe, ['-V']);
          if (pythonCheck.exitCode == 0) {
            result['python_available'] = true;
            result['python_version'] = pythonCheck.stdout.toString().trim();
          } else {
            result['errors'].add(
              'Python exists but cannot be executed: ${pythonCheck.stderr}',
            );
          }
        } else {
          result['errors'].add('Python executable not found at $pythonExe');
        }
      } catch (e) {
        result['errors'].add('Error checking Python: $e');
      }

      // Check texture bridge
      try {
        final libraryPath =
            Platform.isWindows
                ? '$_appDataDir\\bin\\texture_bridge.dll'
                : Platform.isMacOS
                ? '$_appDataDir/bin/libtexture_bridge.dylib'
                : '$_appDataDir/bin/libtexture_bridge.so';

        final libraryFile = File(libraryPath);
        if (await libraryFile.exists()) {
          result['texture_bridge_available'] = true;
          result['texture_bridge_path'] = libraryPath;
        } else {
          result['errors'].add(
            'Texture bridge library not found at $libraryPath',
          );
        }
      } catch (e) {
        result['errors'].add('Error checking texture bridge: $e');
      }

      // Check WebSocket
      try {
        final channel = IOWebSocketChannel.connect(
          Uri.parse('ws://localhost:8080'),
          pingInterval: const Duration(seconds: 1),
        );

        try {
          await channel.ready.timeout(const Duration(seconds: 2));
          // Successfully connected
          result['websocket_responding'] = true;

          // Send a ping message
          channel.sink.add(jsonEncode({'command': 'ping'}));

          // Wait for a response
          final completer = Completer<void>();
          final subscription = channel.stream.listen(
            (data) {
              logInfo(_logTag, 'Received WebSocket response: $data');
              if (!completer.isCompleted) {
                completer.complete();
              }
            },
            onError: (e) {
              logError(_logTag, 'WebSocket error during diagnostic: $e');
              if (!completer.isCompleted) {
                completer.completeError(e);
              }
            },
          );

          try {
            await completer.future.timeout(const Duration(seconds: 2));
            result['server_running'] = true;
          } catch (e) {
            result['errors'].add('WebSocket connected but no response: $e');
          } finally {
            subscription.cancel();
          }

          await channel.sink.close();
        } catch (e) {
          result['errors'].add('Failed to establish WebSocket connection: $e');
        }
      } catch (e) {
        result['errors'].add('Error connecting to WebSocket: $e');
      }
    } catch (e) {
      result['errors'].add('Diagnostics error: $e');
    }

    return result;
  }
}
