import 'package:v04/terminal/terminal.dart';

Future<String> promptFor(String promptText, [String defaultValue = '']) async {
  var input = (await Terminal.readInput(promptText)) ?? defaultValue;
  return input.isEmpty ? defaultValue : input;
}

Future<bool> promptForYesNo(String prompt) async {
  for (;;) {
    var input = await promptFor('''

$prompt (y/n)''');
    if (input.startsWith("y")) {
      return true;
    }
    if (input.startsWith("n")) {
      return false;
    }
    Terminal.println("Invalid answer, please enter y or n");
  }
}

enum YesNoAllQuit { yes, no, all, quit }

Future<YesNoAllQuit> promptForYesNoAllQuit(String prompt) async {
  for (;;) {
    // Add a small delay to ensure any spinner output is complete
    await Future.delayed(Duration(milliseconds: 100));
    
    var input = (await promptFor('''

$prompt (y = yes, n = no, a = all, q = quit)''')).toLowerCase();
    if (input.startsWith("y")) {
      return YesNoAllQuit.yes;
    }
    if (input.startsWith("n")) {
      return YesNoAllQuit.no;
    }
    if (input.startsWith("a")) {
      return YesNoAllQuit.all;
    }
    if (input.startsWith("q")) {
      return YesNoAllQuit.quit;
    }
    Terminal.println("Invalid answer, please enter y = yes, n = no, a = all, or q = quit");
  }
}

Future<bool> promptForYes(String prompt) async {
  return (await promptFor('''

$prompt (y/N)''', 'N')).toLowerCase().startsWith('y');
}

Future<bool> promptForNo(String prompt) async {
  return !((await promptFor('''

$prompt (Y/n)''', 'Y')).toLowerCase()).startsWith('n');
}

enum YesNextCancel { yes, next, cancel }

Future<YesNextCancel> promptForYesNextCancel(String prompt) async {
  for (;;) {
    var input = await promptFor("$prompt (y = yes, n = next, c = cancel)");
    if (input.startsWith("y")) {
      return YesNextCancel.yes;
    }
    if (input.startsWith("n")) {
      return YesNextCancel.next;
    }
    if (input.startsWith("c")) {
      return YesNextCancel.cancel;
    }
    Terminal.println("Invalid answer, please enter y, n or c");
  }
}
