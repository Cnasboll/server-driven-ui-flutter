/// Global injectable callbacks for platform-specific behavior.
///
/// Console apps (v04) call [configure] at startup to enable interactive
/// prompting and terminal features. Flutter apps leave them unset — methods
/// that require callbacks throw [UnimplementedError] if not configured.
class Callbacks {
  static Future<String> Function(String prompt, [String defaultValue])?
      onPromptFor;
  static Future<bool> Function(String prompt)? onPromptForYesNo;
  static Future<bool> Function(String prompt)? onPromptForYes;
  static void Function(String message)? onPrintln;
  static void Function() Function(String text)? onStartWaiting;
  static Future<void> Function(String message)? onPrintLnAndRedisplay;

  /// Configure platform callbacks. Call at startup in console apps.
  static void configure({
    required Future<String> Function(String prompt, [String defaultValue])
        promptFor,
    required Future<bool> Function(String prompt) promptForYesNo,
    required Future<bool> Function(String prompt) promptForYes,
    required void Function(String message) println,
    void Function() Function(String text)? startWaiting,
    Future<void> Function(String message)? printLnAndRedisplay,
  }) {
    onPromptFor = promptFor;
    onPromptForYesNo = promptForYesNo;
    onPromptForYes = promptForYes;
    onPrintln = println;
    onStartWaiting = startWaiting;
    onPrintLnAndRedisplay = printLnAndRedisplay;
  }
}
