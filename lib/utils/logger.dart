import 'dart:developer' as developer;

/// Log levels for different severity of messages
enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
}

/// Current minimum log level to display
LogLevel _currentLevel = LogLevel.info;

/// Set the minimum log level to display
void setLevel(LogLevel level) {
  _currentLevel = level;
}

/// Log a verbose message
void logVerbose(String message, [String tag = '']) {
  if (_currentLevel.index <= LogLevel.verbose.index) {
    _log('V', tag, message);
  }
}

/// Log a debug message
void logDebug(String message, [String tag = '']) {
  if (_currentLevel.index <= LogLevel.debug.index) {
    _log('D', tag, message);
  }
}

/// Log an info message
void logInfo(String message, [String tag = '']) {
  if (_currentLevel.index <= LogLevel.info.index) {
    _log('I', tag, message);
  }
}

/// Log a warning message
void logWarning(String message, [String tag = '']) {
  if (_currentLevel.index <= LogLevel.warning.index) {
    _log('W', tag, message);
  }
}

/// Log an error message
void logError(String message, [Object? error, StackTrace? stackTrace, String tag = '']) {
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
void _log(String level, String tag, String message) {
  final timestamp = DateTime.now().toIso8601String();
  final tagStr = tag.isNotEmpty ? ' $tag:' : '';
  developer.log('$timestamp [$level]$tagStr $message');
}
