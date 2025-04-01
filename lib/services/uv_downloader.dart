import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../models/uv_release.dart';
import 'package:archive/archive.dart';

class UvDownloader {
  static const String uvVersion = "0.6.11";
  
  static final Map<String, UvRelease> _releases = {
    "windows-x64": UvRelease(
      url: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-x86_64-pc-windows-msvc.zip",
      checksumUrl: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-x86_64-pc-windows-msvc.zip.sha256",
      platform: "windows-x64",
      fileName: "uv-x86_64-pc-windows-msvc.zip",
    ),
    "macos-arm64": UvRelease(
      url: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-aarch64-apple-darwin.tar.gz",
      checksumUrl: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-aarch64-apple-darwin.tar.gz.sha256",
      platform: "macos-arm64",
      fileName: "uv-aarch64-apple-darwin.tar.gz",
    ),
    "linux-x64": UvRelease(
      url: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-x86_64-unknown-linux-gnu.tar.gz",
      checksumUrl: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-x86_64-unknown-linux-gnu.tar.gz.sha256",
      platform: "linux-x64",
      fileName: "uv-x86_64-unknown-linux-gnu.tar.gz",
    ),
    "linux-arm64": UvRelease(
      url: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-aarch64-unknown-linux-gnu.tar.gz",
      checksumUrl: "https://github.com/astral-sh/uv/releases/download/$uvVersion/uv-aarch64-unknown-linux-gnu.tar.gz.sha256",
      platform: "linux-arm64",
      fileName: "uv-aarch64-unknown-linux-gnu.tar.gz",
    ),
  };

  static Future<String> getUvPath() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}/uv';
  }

  static String _getCurrentPlatform() {
    if (Platform.isWindows) {
      print('Detected Windows platform');
      return "windows-x64"; // Add more specific detection if needed
    } else if (Platform.isMacOS) {
      final isArm = Platform.version.contains('ARM');
      print('Detected macOS platform (${isArm ? 'ARM' : 'Intel'})');
      return Platform.version.contains('ARM') ? "macos-arm64" : "macos-x64";
    } else if (Platform.isLinux) {
      // Detect Linux architecture
      try {
        final result = Process.runSync('uname', ['-m']);
        final arch = result.stdout.toString().trim();
        print('Detected Linux platform with architecture: $arch');
        
        if (arch == 'x86_64') {
          return "linux-x64";
        } else if (arch == 'aarch64' || arch == 'arm64') {
          return "linux-arm64";
        }
        
        print('Unsupported Linux architecture: $arch');
      } catch (e) {
        print('Error detecting Linux architecture: $e');
      }
      
      // Fallback to x64 if detection fails
      print('Falling back to linux-x64');
      return "linux-x64";
    }
    
    final error = 'Unsupported platform: ${Platform.operatingSystem}';
    print(error);
    throw UnsupportedError(error);
  }

  static Future<bool> isUvInstalled() async {
    final uvPath = await getUvPath();
    return File(uvPath).existsSync();
  }

  static Future<void> downloadAndInstallUv() async {
    final platform = _getCurrentPlatform();
    print('Getting UV release for platform: $platform');
    
    final release = _releases[platform];
    if (release == null) {
      final error = 'No UV release available for platform: $platform';
      print(error);
      print('Available platforms: ${_releases.keys.join(', ')}');
      throw UnsupportedError(error);
    }

    print('Downloading UV from: ${release.url}');
    final directory = await getApplicationSupportDirectory();
    final downloadPath = '${directory.path}/${release.fileName}';
    
    // Download UV
    final response = await http.get(Uri.parse(release.url));
    if (response.statusCode != 200) {
      throw Exception('Failed to download UV');
    }
    
    // Download checksum
    final checksumResponse = await http.get(Uri.parse(release.checksumUrl));
    if (checksumResponse.statusCode != 200) {
      throw Exception('Failed to download checksum');
    }
    
    // Verify checksum
    final expectedChecksum = checksumResponse.body.trim().split(' ').first;
    final actualChecksum = sha256.convert(response.bodyBytes).toString();
    
    if (expectedChecksum != actualChecksum) {
      throw Exception('Checksum verification failed');
    }
    
    print('Checksum verified successfully');
    
    // Save the downloaded file
    await File(downloadPath).writeAsBytes(response.bodyBytes);
    print('Downloaded file saved to: $downloadPath');
    
    // Extract the archive
    final bytes = response.bodyBytes;
    if (platform.startsWith('windows')) {
      // Extract ZIP file
      final archive = ZipDecoder().decodeBytes(bytes);
      _extractArchive(archive, directory.path);
    } else {
      // Extract tar.gz file
      final gzBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzBytes);
      _extractArchive(archive, directory.path);
    }
    
    print('Archive extracted successfully');
    
    // Find the UV executable in the extracted files
    String? extractedUvPath;
    
    if (platform.startsWith('windows')) {
      // For Windows, search for uv.exe
      extractedUvPath = await _findFile(directory.path, 'uv.exe');
    } else {
      // For Unix systems, search for the 'uv' executable
      extractedUvPath = await _findFile(directory.path, 'uv');
    }
    
    if (extractedUvPath == null) {
      throw Exception('Could not find UV executable in extracted files');
    }
    
    print('Found UV executable at: $extractedUvPath');
    
    // Ensure the target directory exists
    final uvPath = await getUvPath();
    final uvFile = File(uvPath);
    if (!await uvFile.parent.exists()) {
      await uvFile.parent.create(recursive: true);
    }
    
    // Move the UV executable to the final location
    await File(extractedUvPath).rename(uvPath);
    print('UV executable moved to: $uvPath');
    
    // Make the file executable on Unix systems
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', uvPath]);
      print('Made UV executable');
    }
    
    // Clean up extracted files
    await _cleanupExtractedFiles(directory.path);
    print('Cleaned up extracted files');
  }
  
  static Future<String?> _findFile(String directory, String filename) async {
    final dir = Directory(directory);
    
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith(filename)) {
          return entity.path;
        }
      }
    } catch (e) {
      print('Error searching for file: $e');
    }
    
    return null;
  }

  static Future<void> _cleanupExtractedFiles(String directory) async {
    try {
      final dir = Directory(directory);
      await for (final entity in dir.list()) {
        if (entity is Directory && entity.path.contains('uv-')) {
          await entity.delete(recursive: true);
        } else if (entity is File && 
                  (entity.path.endsWith('.tar.gz') || 
                   entity.path.endsWith('.zip'))) {
          await entity.delete();
        }
      }
    } catch (e) {
      print('Error cleaning up files: $e');
    }
  }

  static void _extractArchive(Archive archive, String outputPath) {
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final filePath = '$outputPath/$filename';
        print('Extracting: $filePath');
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
  }
} 