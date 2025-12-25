import 'package:server_driven_ui/shql/parser/constants_set.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';
import 'package:server_driven_ui/shql/parser/lookahead_iterator.dart';
import 'package:server_driven_ui/shql/tokenizer/string_escaper.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/tokenizer.dart';

class ParseException implements Exception {
  final String message;

  ParseException(this.message);

  @override
  String toString() => 'ParseException: $message';
}

class Parser {
  static ParseTree parse(String code, ConstantsSet constantsSet) {
    var v = Tokenizer.tokenize(code).toList();
    var tokenEnumerator = v.lookahead();
    List<ParseTree> statements = [];
    while (tokenEnumerator.hasNext) {
      if (statements.isNotEmpty) {
        if (tokenEnumerator.peek().tokenType != TokenTypes.semiColon) {
          throw ParseException(
            'Unexpected token "${tokenEnumerator.next().lexeme}" after parsing expression.',
          );
        }
        // Consume the semicolon
        tokenEnumerator.next();
      }

      if (!tokenEnumerator.hasNext) {
        break;
      }
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        throw ParseException(error ?? "Could not parse expression.");
      }
      statements.add(parseTree);
    }
    return statements.length == 1
        ? statements[0]
        : ParseTree(Symbols.program, statements);
  }

  static ParseTree parseExpression(
    LookaheadIterator<Token> tokenEnumerator,
    ConstantsSet constantsSet,
  ) {
    var (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
    if (parseTree == null) {
      throw ParseException(error ?? "Could not parse expression.");
    }
    return parseTree;
  }

  static (ParseTree?, String?) tryParseExpression(
    LookaheadIterator<Token> tokenEnumerator,
    ConstantsSet constantsSet,
  ) {
    var operandStack = <ParseTree>[];
    var operatorStack = <Token>[];

    do {
      if (!tokenEnumerator.hasNext) {
        return (
          null,
          "Unexpected End of token stream while expecting operand.",
        );
      }

      var (brackets, leftBracket, rightBracket, bracketsError) =
          tryParseBrackets(tokenEnumerator, constantsSet);
      if (brackets != null) {
        if (brackets.symbol == Symbols.tuple && brackets.children.length == 1) {
          operandStack.add(brackets.children[0]);
          // TODO: If we can parse a second operand here, we should consider this a multiplication
          // and push a multiplication operator to the operator stack
          // So we need a tryParseOperand that doesn't throw on failure and dosen't advance the enumerator
          // if no operand is found
          if (tokenEnumerator.hasNext) {
            var token = tokenEnumerator.peek();
            var lineNumber = token.lineNumber;
            var columnNumber = token.columnNumber;
            var (operand, _) = tryParseOperand(tokenEnumerator, constantsSet);
            if (operand != null) {
              operandStack.add(operand);
              operatorStack.add(
                Token.parser(TokenTypes.mul, "*", lineNumber, columnNumber),
              );
            }
          }
        } else {
          operandStack.add(brackets);
        }
      } else {
        if (bracketsError != null) {
          return (null, bracketsError);
        }
        var (parseTree, error) = tryParseOperand(tokenEnumerator, constantsSet);
        if (parseTree == null) {
          return (null, error ?? "Could not parse operand.");
        }
        operandStack.add(parseTree);
      }
      // If we find a left parenthesis after the operand, consider this a call!
      if (tokenEnumerator.hasNext) {
        var token = tokenEnumerator.peek();
        var lineNumber = token.lineNumber;
        var columnNumber = token.columnNumber;
        var (brackets, leftBracket, rightBracket, bracketsError) =
            tryParseBrackets(tokenEnumerator, constantsSet);
        if (brackets != null) {
          operandStack.add(brackets);
          operatorStack.add(
            Token.parser(
              TokenTypes.call,
              leftBracket!.lexeme + rightBracket!.lexeme,
              lineNumber,
              columnNumber,
            ),
          );
          var (operand, error) = popOperatorStack(
            tokenEnumerator,
            operandStack,
            operatorStack,
          );
          if (error != null) {
            return (null, error);
          }
        } else if (bracketsError != null) {
          return (null, bracketsError);
        }
      }

      if (tryConsumeOperator(tokenEnumerator)) {
        while (operatorStack.isNotEmpty &&
            !tokenEnumerator.current.takesPrecedence(operatorStack.last)) {
          var (operand, error) = popOperatorStack(
            tokenEnumerator,
            operandStack,
            operatorStack,
          );
          if (error != null) {
            return (null, error);
          }
        }
        operatorStack.add(tokenEnumerator.current);
      } else {
        // No more operators.
        while (operatorStack.isNotEmpty) {
          var (operand, error) = popOperatorStack(
            tokenEnumerator,
            operandStack,
            operatorStack,
          );
          if (error != null) {
            return (null, error);
          }
        }
      }
    } while (operatorStack.isNotEmpty || operandStack.length > 1);

    return (operandStack.isNotEmpty ? operandStack.removeLast() : null, null);
  }

  static (ParseTree?, String?) popOperatorStack(
    LookaheadIterator<Token> tokenEnumerator,
    List<ParseTree> operandStack,
    List<Token> operatorStack,
  ) {
    Token operatorToken = operatorStack.removeLast();
    if (operandStack.length < 2) {
      var unexpectedLexeme = tokenEnumerator.peek().lexeme;
      var operatorLexeme = operatorStack.last.lexeme;
      return (
        null,
        'Unexpected token "$unexpectedLexeme" when expecting operand for binary operator "$operatorLexeme".',
      );
    }
    var rhs = operandStack.removeLast();
    var lhs = operandStack.removeLast();
    var operand = ParseTree(operatorToken.symbol, [lhs, rhs]);
    operandStack.add(operand);
    return (operand, null);
  }

  static (ParseTree?, String?) tryParseOperand(
    LookaheadIterator<Token> tokenEnumerator,
    ConstantsSet constantsSet, [
    bool allowSign = true,
  ]) {
    if (!tokenEnumerator.hasNext) {
      return (null, 'End of token stream when expecting operand.');
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.nullLiteral)) {
      return (ParseTree(Symbols.nullLiteral, []), null);
    }

    // If we find a plus or minus sign here, consider that a sign for the operand, then we recurse
    if (tryConsumeSymbol(tokenEnumerator, Symbols.add)) {
      var (parseTree, error) = tryParseOperand(
        tokenEnumerator,
        constantsSet,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (ParseTree.withChildren(Symbols.unaryPlus, [parseTree!]), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.sub)) {
      var (parseTree, error) = tryParseOperand(
        tokenEnumerator,
        constantsSet,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (ParseTree.withChildren(Symbols.unaryMinus, [parseTree!]), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.not)) {
      var (parseTree, error) = tryParseOperand(
        tokenEnumerator,
        constantsSet,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (ParseTree.withChildren(Symbols.not, [parseTree!]), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.ifStatement)) {
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after IF.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenEnumerator, Symbols.thenKeyword)) {
        return (null, 'Expected THEN after IF condition.');
      }

      (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after THEN.');
      }
      children.add(parseTree);

      if (tryConsumeSymbol(tokenEnumerator, Symbols.elseKeyword)) {
        (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after ELSE.');
        }
        children.add(parseTree);
      }

      return (ParseTree(Symbols.ifStatement, children), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.whileLoop)) {
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after WHILE.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenEnumerator, Symbols.doKeyword)) {
        return (null, 'Expected DO after WHILE condition.');
      }

      (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after DO.');
      }
      children.add(parseTree);

      return (ParseTree(Symbols.whileLoop, children), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.repeatUntilLoop)) {
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after REPEAT.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenEnumerator, Symbols.untilKeyword)) {
        return (null, 'Expected UNTIL after REPEAT statement.');
      }

      (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);

      if (parseTree == null) {
        return (null, error ?? 'Expected expression after UNTIL.');
      }

      children.add(parseTree);

      return (ParseTree(Symbols.repeatUntilLoop, children), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.forLoop)) {
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after FOR.');
      }

      var initialization = parseTree;

      if (!tryConsumeSymbol(tokenEnumerator, Symbols.toKeyword)) {
        return (null, 'Expected TO after FOR statement.');
      }

      (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after TO.');
      }

      var toExpression = parseTree;

      ParseTree? stepExpression;
      if (tryConsumeSymbol(tokenEnumerator, Symbols.stepKeyword)) {
        (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after STEP.');
        }
        stepExpression = parseTree;
      }

      if (!tryConsumeSymbol(tokenEnumerator, Symbols.doKeyword)) {
        return (null, 'Expected DO after FOR loop range.');
      }

      var children = <ParseTree>[initialization];

      (parseTree, error) = tryParseExpression(tokenEnumerator, constantsSet);
      if (parseTree == null) {
        return (null, error ?? 'Expected body after DO.');
      }

      var body = parseTree;

      children.add(body);
      children.add(toExpression);

      if (stepExpression != null) {
        children.add(stepExpression);
      }

      return (ParseTree(Symbols.forLoop, children), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.breakStatement)) {
      return (ParseTree(Symbols.breakStatement, []), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.continueStatement)) {
      return (ParseTree(Symbols.continueStatement, []), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.returnStatement)) {
      var children = <ParseTree>[];
      if (tokenEnumerator.hasNext &&
          tokenEnumerator.peek().symbol != Symbols.semiColon) {
        var (parseTree, error) = tryParseExpression(
          tokenEnumerator,
          constantsSet,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after RETURN.');
        }

        children.add(parseTree);
      }
      return (ParseTree(Symbols.returnStatement, children), null);
    }

    if (tryConsumeSymbol(tokenEnumerator, Symbols.compoundStatement)) {
      List<ParseTree> statements = [];
      while (!tryConsumeSymbol(tokenEnumerator, Symbols.endKeyword)) {
        var (parseTree, error) = tryParseExpression(
          tokenEnumerator,
          constantsSet,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after semicolon.');
        }
        statements.add(parseTree);
        if (tokenEnumerator.hasNext &&
            tokenEnumerator.peek().symbol == Symbols.semiColon) {
          // Consume the semicolon
          tokenEnumerator.next();
        }
        if (!tokenEnumerator.hasNext) {
          return (null, 'Expected END to close BEGIN block.');
        }
      }
      return (ParseTree(Symbols.compoundStatement, statements), null);
    }

    if (tryConsumeTokenType(tokenEnumerator, TokenTypes.identifier)) {
      String identifierName = tokenEnumerator.current.lexeme;
      /*var (brackets, leftBracket, rightBracket, bracketsError) =
          tryParseBrackets(tokenEnumerator, constantsSet);
      List<ParseTree> children = [];
      if (brackets != null) {
        children.add(brackets);
      } else if (bracketsError != null) {
        return (null, bracketsError);
      }*/

      return (
        ParseTree(
          Symbols.identifier,
          [],
          constantsSet.identifiers.include(identifierName.toUpperCase()),
        ),
        null,
      );
    }

    var literalType = tokenEnumerator.peek().literalType;
    if (literalType != LiteralTypes.none) {
      tokenEnumerator.next();
    }
    switch (literalType) {
      case LiteralTypes.integerLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.integerLiteral,
            constantsSet.includeConstant(
              int.parse(tokenEnumerator.current.lexeme),
            ),
          ),
          null,
        );
      case LiteralTypes.floatLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.floatLiteral,
            constantsSet.includeConstant(
              double.parse(tokenEnumerator.current.lexeme),
            ),
          ),
          null,
        );
      case LiteralTypes.doubleQuotedStringLiteral:
      case LiteralTypes.singleQuotedStringLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.stringLiteral,
            constantsSet.includeConstant(
              StringEscaper.unescape(tokenEnumerator.current.lexeme),
            ),
          ),
          null,
        );
      case LiteralTypes.doubleQuotedRawStringLiteral:
      case LiteralTypes.singleQuotedRawStringLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.stringLiteral,
            constantsSet.includeConstant(
              tokenEnumerator.current.lexeme.substring(
                2,
                tokenEnumerator.current.lexeme.length - 1,
              ),
            ),
          ),
          null,
        );
      default:
    }

    String currentLexeme = tokenEnumerator.peek().lexeme;

    return (null, 'Unexpected token "$currentLexeme" when expecting operand.');
  }

  static (ParseTree?, Token?, Token?, String?) tryParseBrackets(
    LookaheadIterator<Token> tokenEnumerator,
    ConstantsSet constantsSet,
  ) {
    if (!tokenEnumerator.hasNext || !tokenEnumerator.peek().isLeftBracket) {
      return (null, null, null, null);
    }

    // Consume the left bracket
    var leftBracket = tokenEnumerator.next();
    var rightBracketType = leftBracket.correspondingRightBracket!;

    List<ParseTree> arguments = [];
    var result = ParseTree(leftBracket.bracketSymbol!, arguments);

    // Proceed to next token
    if (tryConsumeTokenType(tokenEnumerator, rightBracketType)) {
      // Empty argument list
      return (result, leftBracket, tokenEnumerator.current, null);
    }

    for (;;) {
      var (parseTree, error) = tryParseExpression(
        tokenEnumerator,
        constantsSet,
      );
      if (parseTree == null) {
        return (
          null,
          leftBracket,
          null,
          error ?? "Expected expression as bracket member.",
        );
      }
      arguments.add(parseTree);

      if (!tokenEnumerator.hasNext) {
        return (
          null,
          leftBracket,
          null,
          "End of stream when expecting ${Token.tokenType2String(TokenTypes.comma)} or ${Token.tokenType2String(rightBracketType)}",
        );
      }

      tokenEnumerator.next();

      if (tokenEnumerator.current.tokenType == rightBracketType) {
        break;
      }

      if (tokenEnumerator.current.tokenType != TokenTypes.comma) {
        var n = arguments.length;
        return (
          null,
          leftBracket,
          null,
          "Expected ${Token.tokenType2String(TokenTypes.comma)} or ${Token.tokenType2String(rightBracketType)} following $n:th member",
        );
      }
    }
    return (result, leftBracket, tokenEnumerator.current, null);
  }

  static bool tryConsumeOperator(LookaheadIterator<Token> tokenEnumerator) {
    if (tokenEnumerator.hasNext && tokenEnumerator.peek().isOperator()) {
      tokenEnumerator.next();
      return true;
    }
    return false;
  }

  static bool tryConsumeTokenType(
    LookaheadIterator<Token> tokenEnumerator,
    TokenTypes expectedTokenType,
  ) {
    if (!tokenEnumerator.hasNext) {
      return false;
    }
    if (tokenEnumerator.peek().tokenType == expectedTokenType) {
      tokenEnumerator.next();
      return true;
    }
    return false;
  }

  static bool tryConsumeSymbol(
    LookaheadIterator<Token> tokenEnumerator,
    Symbols expectedSymbol,
  ) {
    if (!tokenEnumerator.hasNext) {
      return false;
    }
    if (tokenEnumerator.peek().symbol == expectedSymbol) {
      tokenEnumerator.next();
      return true;
    }
    return false;
  }
}
