import 'dart:convert';
import 'dart:io';

import 'dart:async';
import 'package:v04/terminal/colours.dart';

class Terminal {
  /// [stdin] as a broadcast [Stream] of lines.
  static final Stream<String> _stdinLineStreamBroadcaster = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();

  /// Reads a single line from [stdin] asynchronously.
  static Future<String> _readStdinLine() async {
    var lineCompleter = Completer<String>();

    var listener = _stdinLineStreamBroadcaster.listen((line) {
      if (!lineCompleter.isCompleted) {
        lineCompleter.complete(line);
      }
    });

    return lineCompleter.future.then((line) {
      listener.cancel();
      return line;
    });
  }

  static String? _currentPromptText;
  static void initialize() {
    stdout.encoding = utf8;
    stderr.encoding = utf8;
    stdout.write('${Colours.clearScreen}${Colours.home}${Colours.green}');
  }

  static void showPrompt([String? promptText]) {
    _currentPromptText = "${promptText ?? ""}\n> ";
    print(_currentPromptText!);
    stdout.flush();
  }

  static void println(String text) {
    // Keep green color without resetting
    stdout.writeln('${Colours.green}$text');
    //stdout.flush();
  }

  static void print(String text) {
    // Keep green color without resetting
    stdout.write('${Colours.green}$text');
    //stdout.flush();
  }

  static Future<void> printLnAndRedisplayCurrentPrompt(String text) async {
    // allow any pending async operations to complete to save changes
    await Future.delayed(Duration.zero);
    print(text);
    //stdout.flush();
    var message = _currentPromptText ?? '\n> ';
    print(message);
    //stdout.flush();
  }

  static Future<String?> readInput([String? promptText]) async {
    showPrompt(promptText);
    return _readStdinLine();
  }

  // Keep sync version for legacy code during refactoring
  static String? readInputSync([String? promptText]) {
    showPrompt(promptText);
    var input = stdin.readLineSync(encoding: utf8);
    _currentPromptText = null;
    return input;
  }

  static void cleanup() {
    stdout.write('${Colours.reset}${Colours.showCursor}');
    stdout.flush();
  }
}
