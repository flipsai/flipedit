import 'dart:io';
import 'dart:convert'; // Import dart:convert for utf8
import 'dart:ffi';
import 'dart:async'; // Import for Completer
import 'package:path_provider/path_provider.dart';
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

  // Simplified texture management (no longer uses texture_rgba_renderer)
  int _textureId = -1;
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

      // Use the simplified texture helper approach
      _textureId = await FixedTextureHelper.createTexture(width, height);

      if (_textureId == -1) {
        logError(
          _logTag,
          'Failed to initialize texture via FixedTextureHelper. TextureId: $_textureId',
        );
        return -1; // Signal failure
      }

      logInfo(
        _logTag,
        'TextureHelper provided TextureId: $_textureId',
      );

      // Load the texture bridge library
      logInfo(_logTag, 'Loading texture bridge library');
      await _loadTextureBridge();

      // Note: With the simplified texture approach, we don't send texture pointers to Python
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

      // For backward compatibility, still try to send initialization data
      await _sendTextureInfoToPython(_textureId, _width, _height);

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

  Future<void> _sendTextureInfoToPython(
    int textureId,
    int width,
    int height,
  ) async {
    try {
      logInfo(
        _logTag,
        'Sending texture info to Python: id=$textureId, size=${width}x$height',
      );

      final controlData = {
        'action': 'set_texture',
        'texture_id': textureId,
        'width': width,
        'height': height,
      };

      final jsonString = jsonEncode(controlData);
      logInfo(_logTag, 'Sending control data: $jsonString');

      // Try to send the control data via a simple file
      final controlFile = File('$_appDataDir/texture_control.json');
      await controlFile.writeAsString(jsonString);
      logInfo(_logTag, 'Wrote texture control data to file');

    } catch (e, stackTrace) {
      logError(_logTag, 'Error sending texture info to Python: $e', stackTrace);
    }
  }

  // Python execution methods
  Future<PythonProcessOutput?> runPythonScript(
    String scriptPath,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      logInfo(_logTag, 'Running Python script: $scriptPath with args: $arguments');
      
      // Use uv to run the Python script
      final uvArgs = ['run', 'python', scriptPath, ...arguments];
      
      final process = await Process.start(
        _uvPath,
        uvArgs,
        workingDirectory: workingDirectory ?? _appDataDir,
        environment: environment,
      );

      final stdoutController = StreamController<String>.broadcast();
      final stderrController = StreamController<String>.broadcast();

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        logDebug('Python stdout: $line', _logTag);
        stdoutController.add(line);
      });

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        logDebug('Python stderr: $line', _logTag);
        stderrController.add(line);
      });

      return PythonProcessOutput(
        process: process,
        stdoutBroadcast: stdoutController.stream,
        stderrBroadcast: stderrController.stream,
      );
    } catch (e, stackTrace) {
      logError(_logTag, 'Error running Python script: $e', stackTrace);
      return null;
    }
  }

  // Package management methods
  Future<bool> installPackage(String packageName, {String? version}) async {
    try {
      final packageSpec = version != null ? '$packageName==$version' : packageName;
      logInfo(_logTag, 'Installing package: $packageSpec');

      final result = await Process.run(
        _uvPath,
        ['add', packageSpec],
        workingDirectory: _appDataDir,
      );

      if (result.exitCode == 0) {
        logInfo(_logTag, 'Successfully installed package: $packageSpec');
        return true;
      } else {
        logError(_logTag, 'Failed to install package: ${result.stderr}');
        return false;
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error installing package: $e', stackTrace);
      return false;
    }
  }

  // Virtual environment management
  Future<List<String>> listVenvs() async {
    try {
      logInfo(_logTag, 'Listing virtual environments');

      final result = await Process.run(
        _uvPath,
        ['venv', 'list'],
        workingDirectory: _appDataDir,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final venvs = output
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => line.trim())
            .toList();
        
        logInfo(_logTag, 'Found ${venvs.length} virtual environments');
        return venvs;
    } else {
        logError(_logTag, 'Failed to list venvs: ${result.stderr}');
        return [];
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error listing venvs: $e', stackTrace);
      return [];
    }
  }

  // Video stream server management (placeholder implementation)
  Future<void> shutdownVideoStreamServer() async {
    try {
      logInfo(_logTag, 'Shutting down video stream server');
      
      // Since we simplified the texture approach, this is now a placeholder
      // In a full implementation, this would stop any running video streaming processes
      
      // Close any active textures
      if (_textureId != -1) {
        await FixedTextureHelper.closeTexture(_textureId);
        _textureId = -1;
      }
      
      // Clean up any control files
      try {
        final controlFile = File('$_appDataDir/texture_control.json');
        if (await controlFile.exists()) {
          await controlFile.delete();
        }
      } catch (e) {
        logDebug('Could not delete control file: $e', _logTag);
          }
      
      logInfo(_logTag, 'Video stream server shutdown completed');
    } catch (e, stackTrace) {
      logError(_logTag, 'Error shutting down video stream server: $e', stackTrace);
    }
  }

  // Rest of the UV manager methods would continue here...
  // For brevity, I'm including just the essential texture-related methods
  
  Future<void> initialize() async {
    try {
      // Get the application documents directory
      final appDocumentsDir = await getApplicationDocumentsDirectory();
      _appDataDir = '${appDocumentsDir.path}/flipedit';

      // Ensure the directory exists
      final appDataDirectory = Directory(_appDataDir);
      if (!await appDataDirectory.exists()) {
        await appDataDirectory.create(recursive: true);
        logInfo(_logTag, 'Created app data directory: $_appDataDir');
      }

      // Set UV path
      _uvPath = '$_appDataDir/uv';
      
      logInfo(_logTag, 'UV Manager initialized');
    } catch (e, stackTrace) {
      logError(_logTag, 'Error initializing UV Manager: $e', stackTrace);
    }
  }

  Future<void> cleanup() async {
    try {
      logInfo(_logTag, 'Cleaning up UV Manager');
      
      // Shutdown video stream server first
      await shutdownVideoStreamServer();
      
      logInfo(_logTag, 'UV Manager cleanup completed');
    } catch (e, stackTrace) {
      logError(_logTag, 'Error during UV Manager cleanup: $e', stackTrace);
        }
  }
}
