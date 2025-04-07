import 'dart:developer' as developer;

/// Log levels for different severity of messages
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
}

/// Logger utility for FlipEdit
class Logger {
  /// Current minimum log level to display
  static LogLevel _currentLevel = LogLevel.info;
  
  /// Set the minimum log level to display
  static void setLevel(LogLevel level) {
    _currentLevel = level;
  }
  
  /// Log a verbose message
  static void v(String tag, String message) {
    if (_currentLevel.index <= LogLevel.verbose.index) {
      _log('V', tag, message);
    }
  }
  
  /// Log a debug message
  static void d(String tag, String message) {
    if (_currentLevel.index <= LogLevel.debug.index) {
      _log('D', tag, message);
    }
  }
  
  /// Log an info message
  static void i(String tag, String message) {
    if (_currentLevel.index <= LogLevel.info.index) {
      _log('I', tag, message);
    }
  }
  
  /// Log a warning message
  static void w(String tag, String message) {
    if (_currentLevel.index <= LogLevel.warning.index) {
      _log('W', tag, message);
    }
  }
  
  /// Log an error message
  static void e(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    if (_currentLevel.index <= LogLevel.error.index) {
      _log('E', tag, message);
      if (error != null) {
        _log('E', tag, 'Error: $error');
      }
      if (stackTrace != null) {
        _log('E', tag, 'Stack trace: $stackTrace');
      }
    }
  }
  
  /// Internal logging method
  static void _log(String level, String tag, String message) {
    final timestamp = DateTime.now().toIso8601String();
    developer.log('$timestamp [$level] $tag: $message');
  }
}

/// Extension method for easier logging from classes
extension LoggerExtension on Object {
  /// Get a tag for logging based on the class name
  String get _logTag => runtimeType.toString();
  
  /// Log a verbose message from this class
  void logVerbose(String message) {
    Logger.v(_logTag, message);
  }
  
  /// Log a debug message from this class
  void logDebug(String message) {
    Logger.d(_logTag, message);
  }
  
  /// Log an info message from this class
  void logInfo(String message) {
    Logger.i(_logTag, message);
  }
  
  /// Log a warning message from this class
  void logWarning(String message) {
    Logger.w(_logTag, message);
  }
  
  /// Log an error message from this class
  void logError(String message, [Object? error, StackTrace? stackTrace]) {
    Logger.e(_logTag, message, error, stackTrace);
  }
}
