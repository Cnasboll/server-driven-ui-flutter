enum Symbols {
  none,
  program,
  //Operators:
  memberAccess,
  colon,
  semiColon,
  assignment,
  lambdaExpression,
  call,
  inOp,
  not,
  pow,
  mul,
  div,
  mod,
  add,
  sub,
  lt,
  ltEq,
  gt,
  gtEq,
  eq,
  neq,
  match,
  notMatch,
  and,
  or,
  xor,
  ifStatement,
  thenKeyword,
  elseKeyword,
  whileLoop,
  repeatUntilLoop,
  breakStatement,
  returnStatement,
  continueStatement,
  doKeyword,
  untilKeyword,
  compoundStatement,
  endKeyword,
  forLoop,
  toKeyword,
  stepKeyword,
  unaryPlus,
  unaryMinus,
  identifier,
  list,
  tuple,
  map,
  integerLiteral,
  floatLiteral,
  stringLiteral,
  nullLiteral,
}

enum LiteralTypes {
  none,
  integerLiteral,
  floatLiteral,
  doubleQuotedStringLiteral,
  doubleQuotedRawStringLiteral,
  singleQuotedStringLiteral,
  singleQuotedRawStringLiteral,
}

enum TokenTypes {
  pow,
  mul,
  div,
  mod,
  add,
  sub,
  lt,
  ltEq,
  eq,
  neq,
  gt,
  gtEq,
  match,
  not,
  notMatch,
  integerLiteral,
  floatLiteral,
  doubleQuotedStringLiteral,
  doubleQuotedRawStringLiteral,
  singleQuotedStringLiteral,
  singleQuotedRawStringLiteral,
  lPar,
  rPar,
  lSquareBrack,
  rSquareBrack,
  lBrace,
  rBrace,
  identifier,
  comma,
  dot,
  colon,
  semiColon,
  assignment,
  lambda,
  call,
}

enum Keywords {
  none,
  inKeyword,
  notKeyword,
  andKeyword,
  orKeyword,
  xorKeyword,
  ifKeyword,
  thenKeyword,
  elseKeyword,
  whileKeyword,
  doKeyword,
  repeatKeyword,
  untilKeyword,
  beginKeyword,
  endKeyword,
  forKeyword,
  toKeyword,
  stepKeyword,
  breakKeyword,
  continueKeyword,
  returnKeyword,
  nullKeyword,
}

class Token {
  String get lexeme {
    return _lexeme;
  }

  TokenTypes get tokenType {
    return _tokenType;
  }

  Keywords get keyword {
    return _keyword;
  }

  LiteralTypes get literalType {
    return _literalType;
  }

  int get operatorPrecedence {
    return _operatorPrecedence;
  }

  Symbols get symbol {
    return _symbol;
  }

  int get lineNumber {
    return _lineNumber;
  }

  int get columnNumber {
    return _columnNumber;
  }

  Token(
    this._lexeme,
    this._tokenType,
    this._keyword,
    this._literalType,
    this._operatorPrecedence,
    this._symbol,
    this._lineNumber,
    this._columnNumber,
  );

  factory Token.parser(
    TokenTypes tokenType,
    String lexeme,
    int lineNumber,
    int columnNumber,
  ) {
    Keywords keyword = Keywords.none;
    LiteralTypes literalType = LiteralTypes.none;
    Symbols symbol = Symbols.none;

    switch (tokenType) {
      case TokenTypes.identifier:
        {
          keyword = _keywords[lexeme.toUpperCase()] ?? Keywords.none;
        }
        break;
      case TokenTypes.integerLiteral:
        literalType = LiteralTypes.integerLiteral;
        break;
      case TokenTypes.floatLiteral:
        literalType = LiteralTypes.floatLiteral;
        break;
      case TokenTypes.doubleQuotedStringLiteral:
        literalType = LiteralTypes.doubleQuotedStringLiteral;
        break;
      case TokenTypes.singleQuotedStringLiteral:
        literalType = LiteralTypes.singleQuotedStringLiteral;
        break;
      case TokenTypes.singleQuotedRawStringLiteral:
        literalType = LiteralTypes.singleQuotedRawStringLiteral;
        break;
      case TokenTypes.doubleQuotedRawStringLiteral:
        literalType = LiteralTypes.doubleQuotedRawStringLiteral;
        break;
      default:
        break;
    }

    var keywordSymbol = _keywordTable[keyword];
    if (keywordSymbol != null) {
      symbol = keywordSymbol;
    } else {
      var operatorSymbol = _symbolTable[tokenType];
      if (operatorSymbol != null) {
        symbol = operatorSymbol;
      }
    }

    int operatorPrecedence = _operatorPrecendences[symbol] ?? -1;

    return Token(
      lexeme,
      tokenType,
      keyword,
      literalType,
      operatorPrecedence,
      symbol,
      lineNumber,
      columnNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Token &&
          runtimeType == other.runtimeType &&
          _lexeme == other._lexeme &&
          _tokenType == other._tokenType;

  @override
  int get hashCode => Object.hash(_lexeme, _tokenType);

  String categorizeIdentifier() {
    if (isKeyword()) {
      return "Keyword $_lexeme";
    }

    if (isIdentifier()) {
      return "Identifer $_lexeme";
    }

    return "";
  }

  @override
  String toString() {
    var s = _tokenType == TokenTypes.identifier
        ? " ($categorizeIdentifier())"
        : "";
    return '$_tokenType "$_lexeme"$s';
  }

  bool isKeyword() {
    return _keyword != Keywords.none;
  }

  bool isIdentifier() {
    return _tokenType == TokenTypes.identifier && !isKeyword();
  }

  bool takesPrecedence(Token rhs) {
    return operatorPrecedence < rhs.operatorPrecedence;
  }

  bool isOperator() {
    return _operatorPrecedence >= 0;
  }

  static Map<String, Keywords> getKeywords() {
    return {
      "IN": Keywords.inKeyword,
      "FINNS_I": Keywords.inKeyword,
      "NOT": Keywords.notKeyword,
      "INTE": Keywords.notKeyword,
      "AND": Keywords.andKeyword,
      "OCH": Keywords.andKeyword,
      "OR": Keywords.orKeyword,
      "ELLER": Keywords.orKeyword,
      "XOR": Keywords.xorKeyword,
      "ANTINGEN_ELLER": Keywords.xorKeyword,
      "IF": Keywords.ifKeyword,
      "THEN": Keywords.thenKeyword,
      "ELSE": Keywords.elseKeyword,
      "WHILE": Keywords.whileKeyword,
      "DO": Keywords.doKeyword,
      "REPEAT": Keywords.repeatKeyword,
      "UNTIL": Keywords.untilKeyword,
      "BEGIN": Keywords.beginKeyword,
      "END": Keywords.endKeyword,
      "FOR": Keywords.forKeyword,
      "TO": Keywords.toKeyword,
      "STEP": Keywords.stepKeyword,
      "BREAK": Keywords.breakKeyword,
      "CONTINUE": Keywords.continueKeyword,
      "RETURN": Keywords.returnKeyword,
      "NULL": Keywords.nullKeyword,
    };
  }

  static Map<Symbols, int> getOperatorPrecendences() {
    var precedence = 0;
    return {
      // Member access
      Symbols.memberAccess: precedence++,
      // In [array]
      Symbols.inOp: precedence,
      // Not
      Symbols.not: precedence++,

      // Exponentiation (right-associative, higher than mul/div)
      Symbols.pow: precedence++,

      // Function call
      Symbols.call: precedence,

      // Multiplication, division and remainder
      Symbols.mul: precedence,
      Symbols.div: precedence,
      Symbols.mod: precedence++,

      // Addition and subtraction
      Symbols.add: precedence,
      Symbols.sub: precedence++,

      // Relational operators
      Symbols.lt: precedence,
      Symbols.ltEq: precedence,
      Symbols.gt: precedence,
      Symbols.gtEq: precedence++,

      // Equalities
      Symbols.eq: precedence,
      Symbols.neq: precedence,

      // Pattern matching
      Symbols.match: precedence,
      Symbols.notMatch: precedence++,

      // Conjunctions
      Symbols.and: precedence++,

      // Disjunctions
      Symbols.or: precedence,
      Symbols.xor: precedence++,

      // Lambda
      Symbols.lambdaExpression: precedence++,

      // Assignment
      Symbols.assignment: precedence++,

      Symbols.nullLiteral: precedence,
    };
  }

  static Map<TokenTypes, Symbols> getSymbolTable() {
    return {
      TokenTypes.dot: Symbols.memberAccess,
      TokenTypes.colon: Symbols.colon,
      TokenTypes.semiColon: Symbols.semiColon,
      TokenTypes.assignment: Symbols.assignment,
      TokenTypes.lambda: Symbols.lambdaExpression,
      TokenTypes.pow: Symbols.pow,
      TokenTypes.mul: Symbols.mul,
      TokenTypes.div: Symbols.div,
      TokenTypes.mod: Symbols.mod,
      TokenTypes.add: Symbols.add,
      TokenTypes.sub: Symbols.sub,
      TokenTypes.not: Symbols.not,
      TokenTypes.lt: Symbols.lt,
      TokenTypes.ltEq: Symbols.ltEq,
      TokenTypes.eq: Symbols.eq,
      TokenTypes.neq: Symbols.neq,
      TokenTypes.gt: Symbols.gt,
      TokenTypes.gtEq: Symbols.gtEq,
      TokenTypes.match: Symbols.match,
      TokenTypes.notMatch: Symbols.notMatch,
      TokenTypes.call: Symbols.call,
    };
  }

  static Map<Keywords, Symbols> getKeywordTable() {
    return {
      Keywords.inKeyword: Symbols.inOp,
      Keywords.notKeyword: Symbols.not,
      Keywords.andKeyword: Symbols.and,
      Keywords.orKeyword: Symbols.or,
      Keywords.xorKeyword: Symbols.xor,
      Keywords.ifKeyword: Symbols.ifStatement,
      Keywords.thenKeyword: Symbols.thenKeyword,
      Keywords.elseKeyword: Symbols.elseKeyword,
      Keywords.whileKeyword: Symbols.whileLoop,
      Keywords.doKeyword: Symbols.doKeyword,
      Keywords.repeatKeyword: Symbols.repeatUntilLoop,
      Keywords.untilKeyword: Symbols.untilKeyword,
      Keywords.breakKeyword: Symbols.breakStatement,
      Keywords.continueKeyword: Symbols.continueStatement,
      Keywords.returnKeyword: Symbols.returnStatement,
      Keywords.beginKeyword: Symbols.compoundStatement,
      Keywords.endKeyword: Symbols.endKeyword,
      Keywords.forKeyword: Symbols.forLoop,
      Keywords.toKeyword: Symbols.toKeyword,
      Keywords.stepKeyword: Symbols.stepKeyword,
      Keywords.nullKeyword: Symbols.nullLiteral,
    };
  }

  static List<TokenTypes> getLeftBrackets() {
    return [TokenTypes.lPar, TokenTypes.lSquareBrack, TokenTypes.lBrace];
  }

  static Map<TokenTypes, TokenTypes> getMatchingBrackets() {
    return {
      TokenTypes.lPar: TokenTypes.rPar,
      TokenTypes.lSquareBrack: TokenTypes.rSquareBrack,
      TokenTypes.lBrace: TokenTypes.rBrace,
    };
  }

  static Map<TokenTypes, Symbols> getBracketSymbol() {
    return {
      TokenTypes.lPar: Symbols.tuple,
      TokenTypes.rPar: Symbols.tuple,
      TokenTypes.lSquareBrack: Symbols.list,
      TokenTypes.rSquareBrack: Symbols.list,
      TokenTypes.lBrace: Symbols.map,
      TokenTypes.rBrace: Symbols.map,
    };
  }

  static Map<TokenTypes, String> tokenTypesToStrings() {
    return {
      TokenTypes.pow: "^",
      TokenTypes.mul: "*",
      TokenTypes.div: "/",
      TokenTypes.mod: "%",
      TokenTypes.add: "+",
      TokenTypes.sub: "-",
      TokenTypes.lt: "<",
      TokenTypes.ltEq: "<=",
      TokenTypes.eq: "=",
      TokenTypes.neq: "!=",
      TokenTypes.gt: ">",
      TokenTypes.gtEq: ">=",
      TokenTypes.match: "~",
      TokenTypes.not: "!",
      TokenTypes.notMatch: "!~",
      TokenTypes.integerLiteral: "integer",
      TokenTypes.floatLiteral: "float",
      TokenTypes.doubleQuotedStringLiteral: "string",
      TokenTypes.doubleQuotedRawStringLiteral: "string",
      TokenTypes.singleQuotedStringLiteral: "string",
      TokenTypes.singleQuotedRawStringLiteral: "string",
      TokenTypes.lPar: "(",
      TokenTypes.rPar: ")",
      TokenTypes.lSquareBrack: "[",
      TokenTypes.rSquareBrack: "]",
      TokenTypes.lBrace: "{",
      TokenTypes.rBrace: "}",
      TokenTypes.identifier: "identifier",
      TokenTypes.comma: ",",
      TokenTypes.dot: ".",
      TokenTypes.colon: ":",
      TokenTypes.semiColon: ";",
      TokenTypes.assignment: ":=",
      TokenTypes.lambda: "=>",
      TokenTypes.call: "()",
    };
  }

  static String tokenType2String(TokenTypes tokenType) {
    return tokenTypesToStrings()[tokenType]!;
  }

  bool get isLeftBracket => _leftBrackets.contains(_tokenType);
  bool get isRightBracket => _matchingBrackets.containsValue(_tokenType);
  TokenTypes? get correspondingRightBracket {
    return _matchingBrackets[_tokenType];
  }

  Symbols? get bracketSymbol {
    return _bracketSymbols[_tokenType];
  }

  final String _lexeme;
  final TokenTypes _tokenType;
  static final Map<String, Keywords> _keywords = getKeywords();
  static final Map<Symbols, int> _operatorPrecendences =
      getOperatorPrecendences();
  static final Map<TokenTypes, Symbols> _symbolTable = getSymbolTable();
  static final Map<Keywords, Symbols> _keywordTable = getKeywordTable();
  static final List<TokenTypes> _leftBrackets = getLeftBrackets();
  static final Map<TokenTypes, TokenTypes> _matchingBrackets =
      getMatchingBrackets();
  static final Map<TokenTypes, Symbols> _bracketSymbols = getBracketSymbol();
  final Keywords _keyword;
  final LiteralTypes _literalType;
  final int _operatorPrecedence;
  final Symbols _symbol;
  final int _lineNumber;
  final int _columnNumber;
}
