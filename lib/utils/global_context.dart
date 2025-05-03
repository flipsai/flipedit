import 'package:flutter/widgets.dart';

/// A utility class to access the global application context from anywhere.
/// This is used for showing dialogs or other UI elements that require a BuildContext.
class GlobalContext {
  /// The application's current build context
  static BuildContext? context;

  /// Set the current application context
  static void setContext(BuildContext ctx) {
    context = ctx;
  }
} 