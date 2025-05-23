import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flipedit/utils/logger.dart';
import 'package:flutter/services.dart' show rootBundle;

class TextureBridgeChecker {
  static const String _logTag = 'TextureBridgeChecker';
  static bool _initialized = false;

  /// Check if the texture bridge library exists and is accessible
  static Future<bool> checkTextureBridge() async {
    if (_initialized) {
      return true;
    }

    try {
      // Get application support directory
      final appDir = await getApplicationSupportDirectory();
      final binDir = Directory('${appDir.path}/bin');

      // Create bin directory if it doesn't exist
      if (!await binDir.exists()) {
        logInfo(_logTag, 'Creating bin directory: ${binDir.path}');
        await binDir.create(recursive: true);
      }

      // Check if texture bridge library exists
      final libraryPath =
          Platform.isWindows
              ? '${binDir.path}\\texture_bridge.dll'
              : Platform.isMacOS
              ? '${binDir.path}/libtexture_bridge.dylib'
              : '${binDir.path}/libtexture_bridge.so';

      final libraryFile = File(libraryPath);

      if (!await libraryFile.exists()) {
        logInfo(
          _logTag,
          'Texture bridge library not found, extracting from assets...',
        );

        // Extract library from assets
        await _extractLibraryFromAssets(binDir.path);
      } else {
        logInfo(_logTag, 'Texture bridge library found at: $libraryPath');
      }

      // Verify the library exists after extraction
      if (await libraryFile.exists()) {
        // Make binary executable on Unix systems
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', libraryPath]);
        }

        _initialized = true;
        logInfo(_logTag, 'Texture bridge library verified and ready');
        return true;
      } else {
        logError(_logTag, 'Texture bridge library not found after extraction');
        return false;
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error: $e', stackTrace);
      return false;
    }
  }

  /// Extract the library from assets
  static Future<void> _extractLibraryFromAssets(String targetDir) async {
    try {
      if (Platform.isMacOS) {
        // On macOS, we need to build the library
        final scriptData = await rootBundle.load(
          'assets/build_texture_bridge.sh',
        );
        final cppData = await rootBundle.load('assets/texture_bridge.cpp');
        final cmakeData = await rootBundle.load('assets/CMakeLists.txt');

        // Create a temporary directory to build
        final tempDir = await getTemporaryDirectory();
        final buildDir = Directory('${tempDir.path}/texture_bridge_build');

        if (await buildDir.exists()) {
          await buildDir.delete(recursive: true);
        }
        await buildDir.create(recursive: true);

        // Write the files to the build directory
        final scriptFile = File('${buildDir.path}/build_texture_bridge.sh');
        final cppFile = File('${buildDir.path}/texture_bridge.cpp');
        final cmakeFile = File('${buildDir.path}/CMakeLists.txt');

        await scriptFile.writeAsBytes(scriptData.buffer.asUint8List());
        await cppFile.writeAsBytes(cppData.buffer.asUint8List());
        await cmakeFile.writeAsBytes(cmakeData.buffer.asUint8List());

        // Make script executable
        await Process.run('chmod', ['+x', scriptFile.path]);

        // Run the build script
        logInfo(_logTag, 'Building texture bridge library...');
        final result = await Process.run(scriptFile.path, []);

        if (result.exitCode != 0) {
          logError(_logTag, 'Error building texture bridge: ${result.stderr}');
          return;
        }

        logInfo(_logTag, 'Build output: ${result.stdout}');

        // Copy the built library to the target directory
        final builtLibrary = File(
          '${buildDir.path}/../bin/libtexture_bridge.dylib',
        );
        if (await builtLibrary.exists()) {
          await builtLibrary.copy('$targetDir/libtexture_bridge.dylib');
          logInfo(
            _logTag,
            'Texture bridge library copied to: $targetDir/libtexture_bridge.dylib',
          );
        } else {
          // Try alternative path based on build output
          final altPath = '${buildDir.path}/lib/libtexture_bridge.dylib';
          final altLibrary = File(altPath);
          if (await altLibrary.exists()) {
            await altLibrary.copy('$targetDir/libtexture_bridge.dylib');
            logInfo(
              _logTag,
              'Texture bridge library copied from alt path: $targetDir/libtexture_bridge.dylib',
            );
          } else {
            logError(
              _logTag,
              'Built library not found at: ${builtLibrary.path} or $altPath',
            );
          }
        }
      } else if (Platform.isWindows) {
        // Windows build process (similar to macOS)
        // ...
      } else {
        // Linux build process
        // ...
      }
    } catch (e, stackTrace) {
      logError(_logTag, 'Error extracting library from assets: $e', stackTrace);
      rethrow;
    }
  }
}
