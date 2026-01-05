import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Tokenize addition', () {
    var v = Tokenizer.tokenize('10+2').toList();

    expect(v.length, 3);
    expect(v[0].tokenType, TokenTypes.integerLiteral);
    expect(v[0].symbol, Symbols.none);
    expect(v[1].tokenType, TokenTypes.add);
    expect(v[1].symbol, Symbols.add);
    expect(v[2].tokenType, TokenTypes.integerLiteral);
    expect(v[2].symbol, Symbols.none);
  });

  test('Tokenize modulus', () {
    var v = Tokenizer.tokenize('9%2').toList();

    expect(v.length, 3);
    expect(v[0].tokenType, TokenTypes.integerLiteral);
    expect(v[0].symbol, Symbols.none);
    expect(v[1].tokenType, TokenTypes.mod);
    expect(v[1].symbol, Symbols.mod);
    expect(v[2].tokenType, TokenTypes.integerLiteral);
    expect(v[2].symbol, Symbols.none);
  });

  test('Tokenize minimal double quoted string', () {
    var v = Tokenizer.tokenize('"h"').toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.doubleQuotedStringLiteral);
    expect(v[0].lexeme, '"h"');
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize minimal single quoted string', () {
    var v = Tokenizer.tokenize("'h'").toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.singleQuotedStringLiteral);
    expect(v[0].lexeme, "'h'");
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize double quoted strings', () {
    var v = Tokenizer.tokenize('"hello world" "good bye"').toList();

    expect(v.length, 2);
    expect(v[0].tokenType, TokenTypes.doubleQuotedStringLiteral);
    expect(v[0].lexeme, '"hello world"');
    expect(v[0].symbol, Symbols.none);
    expect(v[1].tokenType, TokenTypes.doubleQuotedStringLiteral);
    expect(v[1].lexeme, '"good bye"');
    expect(v[1].symbol, Symbols.none);
  });

  test('Tokenize single quoted strings', () {
    var v = Tokenizer.tokenize("'hello world' 'good bye'").toList();

    expect(v.length, 2);
    expect(v[0].tokenType, TokenTypes.singleQuotedStringLiteral);
    expect(v[0].lexeme, "'hello world'");
    expect(v[0].symbol, Symbols.none);
    expect(v[1].tokenType, TokenTypes.singleQuotedStringLiteral);
    expect(v[1].lexeme, "'good bye'");
    expect(v[1].symbol, Symbols.none);
  });

  test('Tokenize escaped double quoted string', () {
    var v = Tokenizer.tokenize('''"5'11\\""''').toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.doubleQuotedStringLiteral);
    expect(v[0].lexeme, '''"5'11\\""''');
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize raw double quoted string', () {
    var v = Tokenizer.tokenize('r"hello\\s+world"').toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.doubleQuotedRawStringLiteral);
    expect(v[0].lexeme, 'r"hello\\s+world"');
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize escaped single quoted string', () {
    var v = Tokenizer.tokenize("""'5\\'11"'""").toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.singleQuotedStringLiteral);
    expect(v[0].lexeme, """'5\\'11"'""");
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize raw single quoted string', () {
    var v = Tokenizer.tokenize("r'hello\\s+world'").toList();

    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.singleQuotedRawStringLiteral);
    expect(v[0].lexeme, "r'hello\\s+world'");
    expect(v[0].symbol, Symbols.none);
  });

  test('Tokenize spaced identifiers', () {
    var v = Tokenizer.tokenize('hello world').toList();

    expect(v.length, 2);
    expect(v[0].tokenType, TokenTypes.identifier);
    expect(v[0].symbol, Symbols.none);
    expect(v[1].tokenType, TokenTypes.identifier);
    expect(v[1].symbol, Symbols.none);
  });

  test('Tokenize keywords', () {
    var v = Tokenizer.tokenize(
      'NOT INTE XOR ANTINGEN_ELLER AND OCH OR ELLER IN FINNS_I',
    ).toList();

    expect(v.length, 10);

    expect(v[0].tokenType, TokenTypes.identifier);
    expect(v[0].keyword, Keywords.notKeyword);
    expect(v[0].symbol, Symbols.not);

    expect(v[1].tokenType, TokenTypes.identifier);
    expect(v[1].keyword, Keywords.notKeyword);
    expect(v[1].symbol, Symbols.not);

    expect(v[2].tokenType, TokenTypes.identifier);
    expect(v[2].keyword, Keywords.xorKeyword);
    expect(v[2].symbol, Symbols.xor);

    expect(v[3].tokenType, TokenTypes.identifier);
    expect(v[3].keyword, Keywords.xorKeyword);
    expect(v[3].symbol, Symbols.xor);

    expect(v[4].tokenType, TokenTypes.identifier);
    expect(v[4].keyword, Keywords.andKeyword);
    expect(v[4].symbol, Symbols.and);

    expect(v[5].tokenType, TokenTypes.identifier);
    expect(v[5].keyword, Keywords.andKeyword);
    expect(v[5].symbol, Symbols.and);

    expect(v[6].tokenType, TokenTypes.identifier);
    expect(v[6].keyword, Keywords.orKeyword);
    expect(v[6].symbol, Symbols.or);

    expect(v[7].tokenType, TokenTypes.identifier);
    expect(v[7].keyword, Keywords.orKeyword);
    expect(v[7].symbol, Symbols.or);

    expect(v[8].tokenType, TokenTypes.identifier);
    expect(v[8].keyword, Keywords.inKeyword);
    expect(v[8].symbol, Symbols.inOp);

    expect(v[9].tokenType, TokenTypes.identifier);
    expect(v[9].keyword, Keywords.inKeyword);
    expect(v[9].symbol, Symbols.inOp);
  });

  test('Tokenize lowercase keywords', () {
    var v = Tokenizer.tokenize('not xor and or in').toList();

    expect(v.length, 5);
    expect(v[0].tokenType, TokenTypes.identifier);
    expect(v[0].keyword, Keywords.notKeyword);
    expect(v[0].symbol, Symbols.not);
    expect(v[1].tokenType, TokenTypes.identifier);
    expect(v[1].keyword, Keywords.xorKeyword);
    expect(v[1].symbol, Symbols.xor);
    expect(v[2].tokenType, TokenTypes.identifier);
    expect(v[2].keyword, Keywords.andKeyword);
    expect(v[2].symbol, Symbols.and);
    expect(v[3].tokenType, TokenTypes.identifier);
    expect(v[3].keyword, Keywords.orKeyword);
    expect(v[3].symbol, Symbols.or);
    expect(v[4].tokenType, TokenTypes.identifier);
    expect(v[4].keyword, Keywords.inKeyword);
    expect(v[4].symbol, Symbols.inOp);
  });

  test('Tokenize various characters', () {
    var v = Tokenizer.tokenize(', . [ ] ( ) !').toList();

    expect(v.length, 7);
    expect(v[0].tokenType, TokenTypes.comma);
    expect(v[1].tokenType, TokenTypes.dot);
    expect(v[1].symbol, Symbols.memberAccess);
    expect(v[2].tokenType, TokenTypes.lSquareBrack);
    expect(v[3].tokenType, TokenTypes.rSquareBrack);
    expect(v[4].tokenType, TokenTypes.lPar);
    expect(v[5].tokenType, TokenTypes.rPar);
    expect(v[6].tokenType, TokenTypes.not);
    expect(v[6].symbol, Symbols.not);
  });

  test('Tokenize comment', () {
    var v = Tokenizer.tokenize(' -- what').toList();

    expect(v.length, 0);
  });

  test('Tokenize comment after something', () {
    var v = Tokenizer.tokenize('x:=3 -- what').toList();

    expect(v.length, 3);
  });

  test('Tokenize something after comment after something', () {
    var v = Tokenizer.tokenize('x:=3 -- what\nx:=4').toList();

    expect(v.length, 6);
  });

  test('Tokenize long comment', () {
    var program = '''--
-- calculator.shql
--
-- A collection of advanced mathematical functions written in SHQL.
-- This script demonstrates user-defined recursive functions and basic arithmetic.
--
''';

    var v = Tokenizer.tokenize(program).toList();
    expect(v.length, 0);
  });

  test('Tokenize long comment and symbol', () {
    var program = '''--
-- calculator.shql
--
-- A collection of advanced mathematical functions written in SHQL.
-- This script demonstrates user-defined recursive functions and basic arithmetic.
--
PI
''';

    var v = Tokenizer.tokenize(program).toList();
    expect(v.length, 1);
    expect(v[0].tokenType, TokenTypes.identifier);
    expect(v[0].lexeme, 'PI');
    expect(v[0].startLocation.lineNumber, 7);
    expect(v[0].startLocation.columnNumber, 1);
  });
}
