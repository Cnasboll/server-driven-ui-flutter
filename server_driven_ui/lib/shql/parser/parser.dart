import 'package:server_driven_ui/shql/parser/constants_set.dart';
import 'package:server_driven_ui/shql/parser/parse_tree.dart';
import 'package:server_driven_ui/shql/parser/lookahead_iterator.dart';
import 'package:server_driven_ui/shql/tokenizer/string_escaper.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/tokenizer.dart';
import 'package:server_driven_ui/shql/tokenizer/code_span.dart';

class ParseException implements Exception {
  final String message;
  final List<Token> tokens;
  final String? sourceCode;

  ParseException(this.message, this.tokens, [this.sourceCode]);

  CodeSpan get tokenSpan => tokens.isEmpty ? (null, null) : tokens.tokenSpan;
  CodeSpan get statementSpan =>
      tokens.isEmpty ? (null, null) : tokens.statementSpan;

  String get _formattedMessage {
    if (sourceCode == null) {
      return 'ParseException: $message';
    }
    final excerpt = statementSpan.excerpt(sourceCode!);
    if (excerpt.isEmpty) {
      return 'ParseException: $message';
    }
    return 'ParseException: $message\n$excerpt';
  }

  @override
  String toString() => _formattedMessage;
}

class TokenConsumer {
  final LookaheadIterator<Token> tokenEnumerator;
  final TokenConsumer? parent;

  TokenConsumer(this.tokenEnumerator) : parent = null;
  TokenConsumer.fromParent(this.parent)
    : tokenEnumerator = parent!.tokenEnumerator;

  List<Token> consumedTokens = [];

  Token consume() {
    var token = parent != null ? parent!.consume() : tokenEnumerator.next();
    consumedTokens.add(token);
    return token;
  }

  bool get hasNext => tokenEnumerator.hasNext;
  Token peek() => tokenEnumerator.peek();
  Token get current => tokenEnumerator.current;
  List<Token> flushConsumedTokens() {
    var tokens = consumedTokens;
    consumedTokens = [];
    return tokens;
  }

  List<Token> flushConsumedTokensAndPeek() {
    var tokens = flushConsumedTokens();
    if (hasNext) {
      tokens.add(peek());
    }
    return tokens;
  }
}

class Parser {
  static ParseTree parse(
    String code,
    ConstantsSet constantsSet, {
    String? sourceCode,
  }) {
    // Use provided sourceCode or fall back to code itself
    final source = sourceCode ?? code;
    var v = Tokenizer.tokenize(code).toList();
    var tokenEnumerator = v.lookahead();
    var tokenConsumer = TokenConsumer(tokenEnumerator);
    List<ParseTree> statements = [];
    while (tokenConsumer.hasNext) {
      if (statements.isNotEmpty) {
        if (tokenConsumer.peek().tokenType != TokenTypes.semiColon) {
          throw ParseException(
            'Unexpected token "${tokenConsumer.consume().lexeme}" after parsing expression.',
            tokenConsumer.flushConsumedTokens(),
            source,
          );
        }
        // Consume the semicolon
        tokenConsumer.consume();
      }

      if (!tokenConsumer.hasNext) {
        break;
      }
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        source,
      );
      if (parseTree == null) {
        throw ParseException(
          error ?? "Could not parse expression.",
          tokenConsumer.flushConsumedTokensAndPeek(),
          source,
        );
      }
      statements.add(parseTree);
    }
    return statements.length == 1
        ? statements[0]
        : ParseTree(
            Symbols.program,
            tokenConsumer.flushConsumedTokens(),
            statements,
            null,
            source,
          );
  }

  static ParseTree parseExpression(
    LookaheadIterator<Token> tokenEnumerator,
    ConstantsSet constantsSet, [
    String? sourceCode,
  ]) {
    var tokenConsumer = TokenConsumer(tokenEnumerator);
    var (parseTree, error) = tryParseExpression(
      tokenConsumer,
      constantsSet,
      sourceCode,
    );
    if (parseTree == null) {
      throw ParseException(
        error ?? "Could not parse expression.",
        tokenConsumer.flushConsumedTokensAndPeek(),
        sourceCode,
      );
    }
    return parseTree;
  }

  static (ParseTree?, String?) tryParseExpression(
    TokenConsumer tokenConsumer,
    ConstantsSet constantsSet,
    String? sourceCode,
  ) {
    var operandStack = <ParseTree>[];
    var operatorStack = <Token>[];

    do {
      if (!tokenConsumer.hasNext) {
        return (
          null,
          "Unexpected End of token stream while expecting operand.",
        );
      }

      var (
        brackets,
        leftBracket,
        rightBracket,
        bracketsError,
      ) = tryParseBrackets(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (brackets != null) {
        if (brackets.symbol == Symbols.tuple && brackets.children.length == 1) {
          operandStack.add(brackets.children[0]);
          // TODO: If we can parse a second operand here, we should consider this a multiplication
          // and push a multiplication operator to the operator stack
          // So we need a tryParseOperand that doesn't throw on failure and dosen't advance the enumerator
          // if no operand is found
          if (tokenConsumer.hasNext) {
            var token = tokenConsumer.peek();
            var location = token.startLocation;
            var (operand, _) = tryParseOperand(
              TokenConsumer.fromParent(tokenConsumer),
              constantsSet,
              sourceCode,
            );
            if (operand != null) {
              operandStack.add(operand);
              operatorStack.add(Token.parser(TokenTypes.mul, "*", location));
            }
          }
        } else {
          operandStack.add(brackets);
        }
      } else {
        if (bracketsError != null) {
          return (null, bracketsError);
        }
        var (parseTree, error) = tryParseOperand(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );
        if (parseTree == null) {
          return (null, error ?? "Could not parse operand.");
        }
        operandStack.add(parseTree);
      }

      // Handle postfix operators like function calls and indexing in a loop
      // to ensure left-associativity. e.g. func(a)(b) or list[a][b]
      while (tokenConsumer.hasNext) {
        var (
          brackets,
          leftBracket,
          rightBracket,
          bracketsError,
        ) = tryParseBrackets(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );

        if (brackets != null) {
          var lhs = operandStack.removeLast();
          // Use the location from leftBracket instead of parent's peek position
          var location = leftBracket!.startLocation;
          var callToken = Token.parser(
            TokenTypes.call,
            leftBracket.lexeme + rightBracket!.lexeme,
            location,
          );
          var callNode = ParseTree(
            callToken.symbol,
            lhs.tokens + brackets.tokens,
            [lhs, brackets],
            null,
            sourceCode,
          );
          operandStack.add(callNode);
        } else {
          if (bracketsError != null) {
            return (null, bracketsError);
          }
          // No more postfix operators, break the loop
          break;
        }
      }

      if (tryConsumeOperator(tokenConsumer)) {
        while (operatorStack.isNotEmpty &&
            !tokenConsumer.current.takesPrecedence(operatorStack.last)) {
          var (operand, error) = popOperatorStack(
            tokenConsumer,
            operandStack,
            operatorStack,
            sourceCode,
          );
          if (error != null) {
            return (null, error);
          }
        }
        operatorStack.add(tokenConsumer.current);
      } else {
        // No more operators.
        while (operatorStack.isNotEmpty) {
          var (operand, error) = popOperatorStack(
            tokenConsumer,
            operandStack,
            operatorStack,
            sourceCode,
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
    TokenConsumer tokenConsumer,
    List<ParseTree> operandStack,
    List<Token> operatorStack,
    String? sourceCode,
  ) {
    Token operatorToken = operatorStack.removeLast();
    if (operandStack.length < 2) {
      var unexpectedLexeme = tokenConsumer.peek().lexeme;
      var operatorLexeme = operatorStack.last.lexeme;
      return (
        null,
        'Unexpected token "$unexpectedLexeme" when expecting operand for binary operator "$operatorLexeme".',
      );
    }
    var rhs = operandStack.removeLast();
    var lhs = operandStack.removeLast();
    var operand = ParseTree(
      operatorToken.symbol,
      tokenConsumer.flushConsumedTokens() + lhs.tokens + rhs.tokens,
      [lhs, rhs],
      null,
      sourceCode,
    );
    operandStack.add(operand);
    return (operand, null);
  }

  static (ParseTree?, String?) tryParseOperand(
    TokenConsumer tokenConsumer,
    ConstantsSet constantsSet,
    String? sourceCode, [
    bool allowSign = true,
  ]) {
    if (!tokenConsumer.hasNext) {
      return (null, 'End of token stream when expecting operand.');
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.nullLiteral)) {
      return (
        ParseTree(Symbols.nullLiteral, [], const [], null, sourceCode),
        null,
      );
    }

    // Handle OBJECT{...} literal syntax
    if (tryConsumeSymbol(tokenConsumer, Symbols.objectLiteral)) {
      var (
        brackets,
        leftBracket,
        rightBracket,
        bracketsError,
      ) = tryParseBrackets(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );

      if (brackets == null) {
        return (null, bracketsError ?? "Expected {...} after OBJECT keyword");
      }

      if (brackets.symbol != Symbols.map) {
        return (
          null,
          "Expected curly braces {...} after OBJECT keyword, not ${brackets.symbol}",
        );
      }

      // Verify all keys are bare identifiers (not expressions)
      for (var child in brackets.children) {
        // Handle both simple key:value pairs and key:lambda pairs
        // For lambdas, the structure is lambdaExpression -> colon (key:params) + body
        // BUT: if the lambda body contains assignment, the parser creates:
        //   assignment -> lambdaExpression -> colon (key:params) + partial_body, rhs
        ParseTree colonNode;
        if (child.symbol == Symbols.colon) {
          colonNode = child;
        } else if (child.symbol == Symbols.lambdaExpression) {
          // Lambda expression: first child is the colon (identifier: params)
          if (child.children.isEmpty ||
              child.children[0].symbol != Symbols.colon) {
            return (null, "Object literal must contain key:value pairs");
          }
          colonNode = child.children[0];
        } else if (child.symbol == Symbols.assignment) {
          // Assignment where LHS might be a lambda expression
          // e.g., setX: (newX) => x := newX becomes assignment(lambdaExpression(...), newX)
          if (child.children.isEmpty ||
              child.children[0].symbol != Symbols.lambdaExpression) {
            return (null, "Object literal must contain key:value pairs");
          }
          var lambdaNode = child.children[0];
          if (lambdaNode.children.isEmpty ||
              lambdaNode.children[0].symbol != Symbols.colon) {
            return (null, "Object literal must contain key:value pairs");
          }
          colonNode = lambdaNode.children[0];
        } else {
          return (null, "Object literal must contain key:value pairs");
        }

        // Check if left side of colon is a bare identifier
        if (colonNode.children.length < 1 ||
            colonNode.children[0].symbol != Symbols.identifier) {
          return (
            null,
            "Object literal keys must be bare identifiers, not expressions",
          );
        }
      }

      // Convert from map symbol to objectLiteral symbol
      return (
        ParseTree(
          Symbols.objectLiteral,
          tokenConsumer.flushConsumedTokens(),
          brackets.children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    // If we find a plus or minus sign here, consider that a sign for the operand, then we recurse
    if (tryConsumeSymbol(tokenConsumer, Symbols.add)) {
      var (parseTree, error) = tryParseOperand(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (
        ParseTree.withChildren(
          Symbols.unaryPlus,
          [parseTree!],
          tokenConsumer.flushConsumedTokens(),
          sourceCode: sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.sub)) {
      var (parseTree, error) = tryParseOperand(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (
        ParseTree.withChildren(
          Symbols.unaryMinus,
          [parseTree!],
          tokenConsumer.flushConsumedTokens(),
          sourceCode: sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.not)) {
      var (parseTree, error) = tryParseOperand(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
        false,
      );
      if (parseTree == null && error != null) {
        return (null, error);
      }
      return (
        ParseTree.withChildren(
          Symbols.not,
          [parseTree!],
          tokenConsumer.flushConsumedTokens(),
          sourceCode: sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.ifStatement)) {
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after IF.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenConsumer, Symbols.thenKeyword)) {
        return (null, 'Expected THEN after IF condition.');
      }

      (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after THEN.');
      }
      children.add(parseTree);

      if (tryConsumeSymbol(tokenConsumer, Symbols.elseKeyword)) {
        (parseTree, error) = tryParseExpression(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after ELSE.');
        }
        children.add(parseTree);
      }

      return (
        ParseTree(
          Symbols.ifStatement,
          tokenConsumer.flushConsumedTokens(),
          children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.whileLoop)) {
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after WHILE.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenConsumer, Symbols.doKeyword)) {
        return (null, 'Expected DO after WHILE condition.');
      }

      (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after DO.');
      }
      children.add(parseTree);

      return (
        ParseTree(
          Symbols.whileLoop,
          tokenConsumer.flushConsumedTokens(),
          children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.repeatUntilLoop)) {
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after REPEAT.');
      }
      var children = <ParseTree>[parseTree];

      if (!tryConsumeSymbol(tokenConsumer, Symbols.untilKeyword)) {
        return (null, 'Expected UNTIL after REPEAT statement.');
      }

      (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );

      if (parseTree == null) {
        return (null, error ?? 'Expected expression after UNTIL.');
      }

      children.add(parseTree);

      return (
        ParseTree(
          Symbols.repeatUntilLoop,
          tokenConsumer.flushConsumedTokens(),
          children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.forLoop)) {
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after FOR.');
      }

      var initialization = parseTree;

      if (!tryConsumeSymbol(tokenConsumer, Symbols.toKeyword)) {
        return (null, 'Expected TO after FOR statement.');
      }

      (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected expression after TO.');
      }

      var toExpression = parseTree;

      ParseTree? stepExpression;
      if (tryConsumeSymbol(tokenConsumer, Symbols.stepKeyword)) {
        (parseTree, error) = tryParseExpression(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after STEP.');
        }
        stepExpression = parseTree;
      }

      if (!tryConsumeSymbol(tokenConsumer, Symbols.doKeyword)) {
        return (null, 'Expected DO after FOR loop range.');
      }

      var children = <ParseTree>[initialization];

      (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
      );
      if (parseTree == null) {
        return (null, error ?? 'Expected body after DO.');
      }

      var body = parseTree;

      children.add(body);
      children.add(toExpression);

      if (stepExpression != null) {
        children.add(stepExpression);
      }

      return (
        ParseTree(
          Symbols.forLoop,
          tokenConsumer.flushConsumedTokens(),
          children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.breakStatement)) {
      return (
        ParseTree(Symbols.breakStatement, [], const [], null, sourceCode),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.continueStatement)) {
      return (
        ParseTree(Symbols.continueStatement, [], const [], null, sourceCode),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.returnStatement)) {
      var children = <ParseTree>[];
      if (tokenConsumer.hasNext &&
          tokenConsumer.peek().symbol != Symbols.semiColon) {
        var (parseTree, error) = tryParseExpression(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after RETURN.');
        }

        children.add(parseTree);
      }
      return (
        ParseTree(
          Symbols.returnStatement,
          tokenConsumer.flushConsumedTokens(),
          children,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeSymbol(tokenConsumer, Symbols.compoundStatement)) {
      List<ParseTree> statements = [];
      while (!tryConsumeSymbol(tokenConsumer, Symbols.endKeyword)) {
        var (parseTree, error) = tryParseExpression(
          TokenConsumer.fromParent(tokenConsumer),
          constantsSet,
          sourceCode,
        );
        if (parseTree == null) {
          return (null, error ?? 'Expected expression after semicolon.');
        }
        statements.add(parseTree);
        while (tryConsumeSymbol(tokenConsumer, Symbols.semiColon)) {
          // Consume zero or many semicolons
        }
        if (!tokenConsumer.hasNext) {
          return (null, 'Expected END to close BEGIN block.');
        }
      }
      return (
        ParseTree(
          Symbols.compoundStatement,
          tokenConsumer.flushConsumedTokens(),
          statements,
          null,
          sourceCode,
        ),
        null,
      );
    }

    if (tryConsumeTokenType(tokenConsumer, TokenTypes.identifier)) {
      String identifierName = tokenConsumer.current.lexeme;
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
          tokenConsumer.flushConsumedTokens(),
          [],
          constantsSet.identifiers.include(identifierName.toUpperCase()),
          sourceCode,
        ),
        null,
      );
    }

    var literalType = tokenConsumer.peek().literalType;
    if (literalType != LiteralTypes.none) {
      tokenConsumer.consume();
    }
    switch (literalType) {
      case LiteralTypes.integerLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.integerLiteral,
            constantsSet.includeConstant(
              int.parse(tokenConsumer.current.lexeme),
            ),
            tokenConsumer.flushConsumedTokens(),
            sourceCode: sourceCode,
          ),
          null,
        );
      case LiteralTypes.floatLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.floatLiteral,
            constantsSet.includeConstant(
              double.parse(tokenConsumer.current.lexeme),
            ),
            tokenConsumer.flushConsumedTokens(),
            sourceCode: sourceCode,
          ),
          null,
        );
      case LiteralTypes.doubleQuotedStringLiteral:
      case LiteralTypes.singleQuotedStringLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.stringLiteral,
            constantsSet.includeConstant(
              StringEscaper.unescape(tokenConsumer.current.lexeme),
            ),
            tokenConsumer.flushConsumedTokens(),
            sourceCode: sourceCode,
          ),
          null,
        );
      case LiteralTypes.doubleQuotedRawStringLiteral:
      case LiteralTypes.singleQuotedRawStringLiteral:
        return (
          ParseTree.withQualifier(
            Symbols.stringLiteral,
            constantsSet.includeConstant(
              tokenConsumer.current.lexeme.substring(
                2,
                tokenConsumer.current.lexeme.length - 1,
              ),
            ),
            tokenConsumer.flushConsumedTokens(),
            sourceCode: sourceCode,
          ),
          null,
        );
      default:
    }

    String currentLexeme = tokenConsumer.peek().lexeme;

    return (null, 'Unexpected token "$currentLexeme" when expecting operand.');
  }

  static (ParseTree?, Token?, Token?, String?) tryParseBrackets(
    TokenConsumer tokenConsumer,
    ConstantsSet constantsSet,
    String? sourceCode,
  ) {
    if (!tokenConsumer.hasNext || !tokenConsumer.peek().isLeftBracket) {
      return (null, null, null, null);
    }

    // Consume the left bracket
    var leftBracket = tokenConsumer.consume();
    var rightBracketType = leftBracket.correspondingRightBracket!;

    List<ParseTree> arguments = [];
    var result = ParseTree(
      leftBracket.bracketSymbol!,
      tokenConsumer.flushConsumedTokens(),
      arguments,
      null,
      sourceCode,
    );

    // Proceed to next token
    if (tryConsumeTokenType(tokenConsumer, rightBracketType)) {
      // Empty argument list
      return (result, leftBracket, tokenConsumer.current, null);
    }

    for (;;) {
      var (parseTree, error) = tryParseExpression(
        TokenConsumer.fromParent(tokenConsumer),
        constantsSet,
        sourceCode,
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

      if (!tokenConsumer.hasNext) {
        return (
          null,
          leftBracket,
          null,
          "End of stream when expecting ${Token.tokenType2String(TokenTypes.comma)} or ${Token.tokenType2String(rightBracketType)}",
        );
      }

      tokenConsumer.consume();

      if (tokenConsumer.current.tokenType == rightBracketType) {
        break;
      }

      if (tokenConsumer.current.tokenType != TokenTypes.comma) {
        var n = arguments.length;
        return (
          null,
          leftBracket,
          null,
          "Expected ${Token.tokenType2String(TokenTypes.comma)} or ${Token.tokenType2String(rightBracketType)} following $n:th member",
        );
      }
    }
    return (result, leftBracket, tokenConsumer.current, null);
  }

  static bool tryConsumeOperator(TokenConsumer tokenConsumer) {
    if (tokenConsumer.hasNext && tokenConsumer.peek().isOperator()) {
      tokenConsumer.consume();
      return true;
    }
    return false;
  }

  static bool tryConsumeTokenType(
    TokenConsumer tokenConsumer,
    TokenTypes expectedTokenType,
  ) {
    if (!tokenConsumer.hasNext) {
      return false;
    }
    if (tokenConsumer.peek().tokenType == expectedTokenType) {
      tokenConsumer.consume();
      return true;
    }
    return false;
  }

  static bool tryConsumeSymbol(
    TokenConsumer tokenConsumer,
    Symbols expectedSymbol,
  ) {
    if (!tokenConsumer.hasNext) {
      return false;
    }
    if (tokenConsumer.peek().symbol == expectedSymbol) {
      tokenConsumer.consume();
      return true;
    }
    return false;
  }
}
