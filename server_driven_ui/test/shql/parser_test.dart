import 'package:server_driven_ui/shql/parser/constants_set.dart';
import 'package:server_driven_ui/shql/parser/lookahead_iterator.dart';
import 'package:server_driven_ui/shql/parser/parser.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Parse addition', () {
    var v = Tokenizer.tokenize('10+2').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children[0].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[0].qualifier!), 10);
    expect(p.children[1].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[1].qualifier!), 2);
  });

  test('Parse addition and multiplication', () {
    var v = Tokenizer.tokenize('10+13*37+1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children[0].symbol, Symbols.add);
    expect(p.children[0].children[0].symbol, Symbols.integerLiteral);
    expect(
      constantsSet.getConstantByIndex(p.children[0].children[0].qualifier!),
      10,
    );
    expect(p.children[0].children[1].symbol, Symbols.mul);
    expect(
      p.children[0].children[1].children[0].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[0].children[1].children[0].qualifier!,
      ),
      13,
    );
    expect(
      p.children[0].children[1].children[1].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[0].children[1].children[1].qualifier!,
      ),
      37,
    );
    expect(p.children[1].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[1].qualifier!), 1);
  });

  test('Parse addition and multiplication with parenthesis', () {
    var v = Tokenizer.tokenize('10+13*(37+1)').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children[0].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[0].qualifier!), 10);
    expect(p.children[1].symbol, Symbols.mul);
    expect(p.children[1].children[0].symbol, Symbols.integerLiteral);
    expect(
      constantsSet.getConstantByIndex(p.children[1].children[0].qualifier!),
      13,
    );
    expect(p.children[1].children[1].symbol, Symbols.add);
    expect(
      p.children[1].children[1].children[0].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[1].children[1].children[0].qualifier!,
      ),
      37,
    );
    expect(
      p.children[1].children[1].children[1].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[1].children[1].children[1].qualifier!,
      ),
      1,
    );
  });

  test('Parse addition, multiplication and subtraction', () {
    var v = Tokenizer.tokenize('10+13*37-1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.sub);
    expect(p.children[0].symbol, Symbols.add);
    expect(p.children[0].children[0].symbol, Symbols.integerLiteral);
    expect(
      constantsSet.getConstantByIndex(p.children[0].children[0].qualifier!),
      10,
    );
    expect(p.children[0].children[1].symbol, Symbols.mul);
    expect(
      p.children[0].children[1].children[0].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[0].children[1].children[0].qualifier!,
      ),
      13,
    );
    expect(
      p.children[0].children[1].children[1].symbol,
      Symbols.integerLiteral,
    );
    expect(
      constantsSet.getConstantByIndex(
        p.children[0].children[1].children[1].qualifier!,
      ),
      37,
    );
    expect(p.children[1].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[1].qualifier!), 1);
  });

  test('Parse function call', () {
    var v = Tokenizer.tokenize('f()').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);
    expect(p.children[0].symbol, Symbols.identifier);
    expect(p.children[0].children.isEmpty, true);
    expect(p.children[1].symbol, Symbols.tuple);
    expect(p.children[1].children.isEmpty, true);
  });

  test('Parse function call followed by operator', () {
    var v = Tokenizer.tokenize('f()+1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children.length, 2);
  });

  test('Parse function call with 1 arg', () {
    var v = Tokenizer.tokenize('f(1)').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);
    expect(p.children[0].symbol, Symbols.identifier);
    expect(p.children[1].symbol, Symbols.tuple);
    expect(p.children[1].children.length, 1);
  });

  test('Parse function call with 1 arg followed by operator', () {
    var v = Tokenizer.tokenize('f(1)+1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children.length, 2);
  });

  test(
    'Parse function call with 1 arg and operator with expression followed by operator',
    () {
      var v = Tokenizer.tokenize('f(1*2, 2)+1').toList();
      var constantsSet = ConstantsSet();
      var p = Parser.parseExpression(v.lookahead(), constantsSet);
      expect(p.symbol, Symbols.add);
      expect(p.children.length, 2);
    },
  );

  test('Parse empty list', () {
    var v = Tokenizer.tokenize('[]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.list);
    expect(p.children.isEmpty, true);
  });

  test('Parse empty list followed by operator', () {
    var v = Tokenizer.tokenize('[]+1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children.length, 2);
    var list = p.children[0];
    expect(list.symbol, Symbols.list);
    expect(list.children.isEmpty, true);
  });

  test('Parse list of one element ', () {
    var v = Tokenizer.tokenize('[1]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.list);
    expect(p.children.length, 1);
  });

  test('Parse list of one element followed by operator', () {
    var v = Tokenizer.tokenize('[1]+1').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children.length, 2);
    var list = p.children[0];
    expect(list.symbol, Symbols.list);
    expect(list.children.length, 1);
  });

  test(
    'Parse list of two elements, one with operator, followed by operator',
    () {
      var v = Tokenizer.tokenize('[1*2, 2]+1').toList();
      var constantsSet = ConstantsSet();
      var p = Parser.parseExpression(v.lookahead(), constantsSet);
      expect(p.symbol, Symbols.add);
      expect(p.children.length, 2);
      var list = p.children[0];
      expect(list.symbol, Symbols.list);
      expect(list.children.length, 2);
    },
  );

  test('Parse list membership', () {
    var v = Tokenizer.tokenize('2 IN [1, 2]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.inOp);
    expect(p.children.length, 2);
    var list = p.children[1];
    expect(list.symbol, Symbols.list);
    expect(list.children.length, 2);
  });

  test('Parse list membership lowercase', () {
    var v = Tokenizer.tokenize('2 in [1, 2]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.inOp);
    expect(p.children.length, 2);
    var list = p.children[1];
    expect(list.symbol, Symbols.list);
    expect(list.children.length, 2);
  });

  test('Parse list indexing', () {
    var v = Tokenizer.tokenize('list[0]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);
  });

  test('Parse list and map indexing', () {
    var v = Tokenizer.tokenize('(list[0])["props"]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);

    var callNode = p.children[0];
    expect(callNode.symbol, Symbols.call);
    expect(callNode.children.length, 2);

    var list = p.children[1];
    expect(list.symbol, Symbols.list);
    expect(list.children.length, 1);
  });

  test('Parse nested list indexing without parentheses', () {
    var v = Tokenizer.tokenize('list[0]["prop"]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);

    var innerCall = p.children[0];
    expect(innerCall.symbol, Symbols.call);
    expect(innerCall.children.length, 2);

    var listIdentifier = innerCall.children[0];
    expect(listIdentifier.symbol, Symbols.identifier);

    var firstIndex = innerCall.children[1];
    expect(firstIndex.symbol, Symbols.list);
    expect(firstIndex.children.length, 1);
    expect(firstIndex.children[0].symbol, Symbols.integerLiteral);

    var secondIndex = p.children[1];
    expect(secondIndex.symbol, Symbols.list);
    expect(secondIndex.children.length, 1);
    expect(secondIndex.children[0].symbol, Symbols.stringLiteral);
  });

  test('Parse nested list indexing', () {
    var v = Tokenizer.tokenize('list[0][1]').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.call);
    expect(p.children.length, 2);
    var list = p.children[1];
    expect(list.symbol, Symbols.list);
    expect(list.children.length, 1);
  });

  test('Parse member access', () {
    var v = Tokenizer.tokenize('powerstats.strength').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.memberAccess);
    expect(p.children.length, 2);
    var powerstats = p.children[0];
    expect(powerstats.symbol, Symbols.identifier);
    expect(
      powerstats.qualifier,
      constantsSet.identifiers.include('POWERSTATS'),
    );
    var strength = p.children[1];
    expect(strength.symbol, Symbols.identifier);
    expect(strength.qualifier, constantsSet.identifiers.include('STRENGTH'));
  });

  test('Parse large program with comments', () {
    var program = '''--
-- calculator.shql
--
-- A collection of advanced mathematical functions written in SHQL.
-- This script demonstrates user-defined recursive functions and basic arithmetic.
--

add(a,b):=a+b;
sub(a,b):=a-b;
mul(a,b):=a*b;
div(a,b):=a/b;

-- Greatest Common Divisor (GCD)
-- Calculates the largest positive integer that divides two integers without a remainder.
-- Uses the Euclidean algorithm for efficiency.
--
-- Parameters:
--   a: The first integer.
--   b: The second integer.
--
-- Returns:
--   The greatest common divisor of a and b.
--
gcd(a, b) := IF b = 0 THEN a ELSE gcd(b, a % b);

--
-- Least Common Multiple (LCM)
-- Calculates the smallest positive integer that is a multiple of both a and b.
-- This is often what is meant by "least common denominator".
--
-- Parameters:
--   a: The first integer.
--   b: The second integer.
--
-- Returns:
--   The least common multiple of a and b.
--
lcm(a, b) := (a * b) / gcd(a, b);

funcs:=[add, sub, mul, div, gcd, lcm];


print("Welcome to Calculator 1.0");

while true do begin
    input := prompt("Please select a function:\nEnter:\n1 for 'addition',\n2 for 'subtraction',\n3 for 'muliplication',\n4 for 'division',\n5 for 'greatest common divisor',\n6 for 'least common multiple' or 'Q' to quit\n:");
    if uppercase(input) = "Q" then break;
    index := int(input)-1;
    if index < 0 or index > 5 then begin
        print("please enter a number in the range 1 to 5");
        continue;
    end;
    func := funcs[index];
    input := prompt("Please enter the first number (or q to quit)\n:");
    if uppercase(input) = "Q" then break;
    a := if index >= 4 then int(input) else double(input);

    input := prompt("Please enter the second number (or q to quit)\n:");
    if uppercase(input) = "Q" then break;
    b := if index >= 4 then int(input) else double(input);

    print("The result is " + string(func(a, b)));
end''';

    var constantsSet = ConstantsSet();
    var p = Parser.parse(program, constantsSet);
    expect(p.symbol, Symbols.program);
    expect(p.children.isNotEmpty, true);
  });
}
