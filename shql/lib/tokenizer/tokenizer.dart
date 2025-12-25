import 'package:shql/tokenizer/state_machine.dart';
import 'package:shql/tokenizer/token.dart';

class Tokenizer {
  static Iterable<Token> tokenize(String text) {
    return tokenizeCodeUnits(text.codeUnits);
  }

  static Iterable<Token> tokenizeCodeUnits(Iterable<Char> text) sync* {
    var stateMachine = StateMachine();

    for (var symbol in text) {
      for (Token token in stateMachine.accept(symbol)) {
        yield token;
      }
    }

    for (Token token in stateMachine.acceptEndOfStream()) {
      yield token;
    }
  }
}
