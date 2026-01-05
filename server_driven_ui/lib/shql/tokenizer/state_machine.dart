import 'package:server_driven_ui/shql/tokenizer/token.dart';

enum ECharCodeClasses {
  letter,
  digit,
  whitespace,
  newline,
  lPar,
  rPar,
  lSquareBrack,
  rSquareBrack,
  lBrace,
  rBrace,
  underscore,
  comma,
  dot,
  colon,
  semiColon,
  powOp,
  mulop,
  divOp,
  modOp,
  minusOp,
  plusOp,
  eq,
  exclamation,
  tilde,
  lt,
  gt,
  // Special addition for string literals:
  backslash,
  doubleQuote,
  singleQuote,
  r,
}

enum TokenizerState {
  start,
  identifier,
  number,
  float,
  doubleQuotedString,
  singleQuotedString,
  escapeDoubleQuotedString,
  escapeSingleQuotedString,
  doubleQuotedRawString,
  singleQuotedRawString,
  colon,
  exclamation,
  eq,
  lt,
  gt,
  minus,
  comment,
  acceptEq,
  acceptMatch,
  acceptNotMatch,
  acceptLPar,
  acceptRPar,
  acceptLSquareBrack,
  acceptRSquareBrack,
  acceptLBrace,
  acceptRBrace,
  acceptIdentifier,
  acceptDivOp,
  acceptModOp,
  acceptPowOp,
  acceptMulOp,
  acceptPlusOp,
  acceptMinusOp,
  numberDot,
  acceptNumber,
  acceptFloat,
  acceptDoubleQuotedString,
  acceptDoubleQuotedRawString,
  acceptSingleQuotedString,
  acceptSingleQuotedRawString,
  acceptComma,
  acceptDot,
  acceptColon,
  acceptAssignment,
  acceptSemiColon,
  acceptNot,
  acceptGt,
  acceptLt,
  acceptLtEq,
  acceptNeq,
  acceptGtEq,
  r,
  acceptLambda,
}

// Apparently there is no built in Char type:
typedef Char = int;

bool isDigit(Char c) => c >= 0x30 && c <= 0x39; // '0'..'9'
bool isUpper(Char c) => c >= 0x41 && c <= 0x5A; // 'A'..'Z'
bool isLower(Char c) => c >= 0x61 && c <= 0x7A; // 'a'..'z'
bool isLetter(Char c) => isUpper(c) || isLower(c); // letter (A-Z,a-z)
bool isWhitespace(Char c) => c == 0x20 /* space */ || c == 0x09 /* tab  */;
bool isNewline(Char c) => c == 0x0A /* \n   */ || c == 0x0D /* \r   */;

class TokenizerException implements Exception {
  final String message;

  TokenizerException(this.message);

  @override
  String toString() => 'TokenizerException: $message';
}

class StateMachine {
  Iterable<Token> accept(Char charCode, {bool updatePosition = true}) sync* {
    try {
      bool wasStartOrComment =
          _state == TokenizerState.start || _state == TokenizerState.comment;
      var nextState = _transitionTable[(_state, categorize(charCode))];
      if (nextState != null) {
        _state = nextState;
        if (_state != TokenizerState.start &&
            _state != TokenizerState.comment) {
          if (wasStartOrComment) {
            _bufferStartLocation = CodeLocation(
              lineNumber: _lineNumber,
              columnNumber: _columnNumber,
            );
            _buffer = StringBuffer();
          }
          _buffer.writeCharCode(charCode);
          var token = interpretAcceptState();
          if (token != null) {
            yield token;
          }
        }
      } else {
        var nextState = _defaultTransitionTable[_state];
        if (nextState != null) {
          _state = nextState;
          var token = interpretAcceptState();
          if (token == null) {
            _buffer.writeCharCode(charCode);
          } else {
            yield token;

            //Don't consume the char, run the char again.
            // Don't update position on recursive call since we already did it
            for (var t in accept(charCode, updatePosition: false)) {
              yield t;
            }
          }
        } else {
          throw TokenizerException(
            "Unexpected char '${String.fromCharCode(charCode)}' at line $_lineNumber, column $_columnNumber in state $_state",
          );
        }
      }
    } finally {
      if (updatePosition) {
        if (isNewline(charCode)) {
          _lineNumber++;
          _columnNumber = 1;
        } else {
          _columnNumber++;
        }
      }
    }
  }

  Iterable<Token> acceptEndOfStream() sync* {
    if (_state != TokenizerState.start && _state != TokenizerState.comment) {
      var nextState = _defaultTransitionTable[_state];
      TokenizerState oldState = _state;
      if (nextState != null) {
        _state = nextState;
        var token = interpretAcceptState();
        if (token != null) {
          yield token;
        } else {
          throw TokenizerException(
            "Internal error: _defaultTransitionTable[{$oldState}] gave {$_state} but interpretAcceptState() returns null at line $_lineNumber, column $_columnNumber.",
          );
        }
      } else {
        throw TokenizerException(
          "Unexpected end of stream in state {$_state} at line $_lineNumber, column $_columnNumber.",
        );
      }
    }
  }

  Token? interpretAcceptState() {
    var tokenType = _acceptStateTable[_state];
    if (tokenType != null) {
      var token = Token.parser(
        tokenType,
        _buffer.toString(),
        _bufferStartLocation!,
      );
      _state = TokenizerState.start;
      return token;
    }
    return null;
  }

  static ECharCodeClasses? categorize(Char charCode) {
    var characterString = String.fromCharCode(charCode);
    var charCodeClass = _charCodeClassTable[characterString];

    if (charCodeClass != null) {
      return charCodeClass;
    }

    if (isLetter(charCode)) {
      return ECharCodeClasses.letter;
    }

    if (isDigit(charCode)) {
      return ECharCodeClasses.digit;
    }

    if (isWhitespace(charCode)) {
      return ECharCodeClasses.whitespace;
    }

    if (isNewline(charCode)) {
      return ECharCodeClasses.newline;
    }

    return null;
  }

  static Map<String, ECharCodeClasses> createCharCodeClassTable() {
    return {
      '(': ECharCodeClasses.lPar,
      ')': ECharCodeClasses.rPar,
      '[': ECharCodeClasses.lSquareBrack,
      ']': ECharCodeClasses.rSquareBrack,
      '{': ECharCodeClasses.lBrace,
      '}': ECharCodeClasses.rBrace,
      '_': ECharCodeClasses.underscore,
      ',': ECharCodeClasses.comma,
      '.': ECharCodeClasses.dot,
      ':': ECharCodeClasses.colon,
      ';': ECharCodeClasses.semiColon,
      '^': ECharCodeClasses.powOp,
      '*': ECharCodeClasses.mulop,
      '/': ECharCodeClasses.divOp,
      '%': ECharCodeClasses.modOp,
      '+': ECharCodeClasses.plusOp,
      '-': ECharCodeClasses.minusOp,
      '=': ECharCodeClasses.eq,
      '!': ECharCodeClasses.exclamation,
      "~": ECharCodeClasses.tilde,
      '<': ECharCodeClasses.lt,
      '>': ECharCodeClasses.gt,
      '\\': ECharCodeClasses.backslash,
      '"': ECharCodeClasses.doubleQuote,
      "'": ECharCodeClasses.singleQuote,
      "r": ECharCodeClasses.r,
    };
  }

  static Map<(TokenizerState, ECharCodeClasses), TokenizerState>
  createTransitionTable() {
    return {
      (TokenizerState.start, ECharCodeClasses.r): TokenizerState.r,
      (TokenizerState.start, ECharCodeClasses.letter):
          TokenizerState.identifier,
      (TokenizerState.start, ECharCodeClasses.underscore):
          TokenizerState.identifier,
      (TokenizerState.start, ECharCodeClasses.digit): TokenizerState.number,
      (TokenizerState.start, ECharCodeClasses.doubleQuote):
          TokenizerState.doubleQuotedString,
      (TokenizerState.start, ECharCodeClasses.singleQuote):
          TokenizerState.singleQuotedString,
      (TokenizerState.r, ECharCodeClasses.doubleQuote):
          TokenizerState.doubleQuotedRawString,
      (TokenizerState.r, ECharCodeClasses.singleQuote):
          TokenizerState.singleQuotedRawString,
      (TokenizerState.start, ECharCodeClasses.colon): TokenizerState.colon,
      (TokenizerState.start, ECharCodeClasses.semiColon):
          TokenizerState.acceptSemiColon,
      (TokenizerState.start, ECharCodeClasses.exclamation):
          TokenizerState.exclamation,
      (TokenizerState.start, ECharCodeClasses.eq): TokenizerState.eq,
      (TokenizerState.start, ECharCodeClasses.gt): TokenizerState.gt,
      (TokenizerState.start, ECharCodeClasses.lt): TokenizerState.lt,
      (TokenizerState.start, ECharCodeClasses.tilde):
          TokenizerState.acceptMatch,
      (TokenizerState.start, ECharCodeClasses.lPar): TokenizerState.acceptLPar,
      (TokenizerState.start, ECharCodeClasses.rPar): TokenizerState.acceptRPar,
      (TokenizerState.start, ECharCodeClasses.lSquareBrack):
          TokenizerState.acceptLSquareBrack,
      (TokenizerState.start, ECharCodeClasses.rSquareBrack):
          TokenizerState.acceptRSquareBrack,
      (TokenizerState.start, ECharCodeClasses.lBrace):
          TokenizerState.acceptLBrace,
      (TokenizerState.start, ECharCodeClasses.rBrace):
          TokenizerState.acceptRBrace,
      (TokenizerState.start, ECharCodeClasses.divOp):
          TokenizerState.acceptDivOp,
      (TokenizerState.start, ECharCodeClasses.modOp):
          TokenizerState.acceptModOp,
      (TokenizerState.start, ECharCodeClasses.powOp):
          TokenizerState.acceptPowOp,
      (TokenizerState.start, ECharCodeClasses.mulop):
          TokenizerState.acceptMulOp,
      (TokenizerState.start, ECharCodeClasses.plusOp):
          TokenizerState.acceptPlusOp,
      (TokenizerState.start, ECharCodeClasses.minusOp): TokenizerState.minus,
      (TokenizerState.start, ECharCodeClasses.comma):
          TokenizerState.acceptComma,
      (TokenizerState.start, ECharCodeClasses.dot): TokenizerState.acceptDot,
      (TokenizerState.start, ECharCodeClasses.whitespace): TokenizerState.start,
      (TokenizerState.start, ECharCodeClasses.newline): TokenizerState.start,
      (TokenizerState.identifier, ECharCodeClasses.r):
          TokenizerState.identifier,
      (TokenizerState.identifier, ECharCodeClasses.letter):
          TokenizerState.identifier,
      (TokenizerState.identifier, ECharCodeClasses.underscore):
          TokenizerState.identifier,
      (TokenizerState.identifier, ECharCodeClasses.digit):
          TokenizerState.identifier,
      (TokenizerState.r, ECharCodeClasses.letter): TokenizerState.identifier,
      (TokenizerState.r, ECharCodeClasses.underscore):
          TokenizerState.identifier,
      (TokenizerState.r, ECharCodeClasses.digit): TokenizerState.identifier,
      (TokenizerState.number, ECharCodeClasses.digit): TokenizerState.number,
      (TokenizerState.number, ECharCodeClasses.dot): TokenizerState.numberDot,
      (TokenizerState.numberDot, ECharCodeClasses.digit): TokenizerState.float,
      (TokenizerState.float, ECharCodeClasses.digit): TokenizerState.float,
      (TokenizerState.doubleQuotedString, ECharCodeClasses.backslash):
          TokenizerState.escapeDoubleQuotedString,
      (TokenizerState.doubleQuotedString, ECharCodeClasses.doubleQuote):
          TokenizerState.acceptDoubleQuotedString,
      (TokenizerState.doubleQuotedRawString, ECharCodeClasses.doubleQuote):
          TokenizerState.acceptDoubleQuotedRawString,
      (TokenizerState.singleQuotedString, ECharCodeClasses.backslash):
          TokenizerState.escapeSingleQuotedString,
      (TokenizerState.singleQuotedString, ECharCodeClasses.singleQuote):
          TokenizerState.acceptSingleQuotedString,
      (TokenizerState.singleQuotedRawString, ECharCodeClasses.singleQuote):
          TokenizerState.acceptSingleQuotedRawString,
      (TokenizerState.colon, ECharCodeClasses.eq):
          TokenizerState.acceptAssignment,
      (TokenizerState.exclamation, ECharCodeClasses.eq):
          TokenizerState.acceptNeq,
      (TokenizerState.exclamation, ECharCodeClasses.tilde):
          TokenizerState.acceptNotMatch,
      (TokenizerState.eq, ECharCodeClasses.gt): TokenizerState.acceptLambda,
      (TokenizerState.lt, ECharCodeClasses.eq): TokenizerState.acceptLtEq,
      (TokenizerState.lt, ECharCodeClasses.gt): TokenizerState.acceptNeq,
      (TokenizerState.gt, ECharCodeClasses.eq): TokenizerState.acceptGtEq,
      (TokenizerState.minus, ECharCodeClasses.minusOp): TokenizerState.comment,
      (TokenizerState.comment, ECharCodeClasses.newline): TokenizerState.start,
    };
  }

  static Map<TokenizerState, TokenizerState> createDefaultTransitionTable() {
    return {
      TokenizerState.r: TokenizerState.acceptIdentifier,
      TokenizerState.identifier: TokenizerState.acceptIdentifier,
      TokenizerState.number: TokenizerState.acceptNumber,
      TokenizerState.float: TokenizerState.acceptFloat,
      TokenizerState.colon: TokenizerState.acceptColon,
      TokenizerState.exclamation: TokenizerState.acceptNot,
      TokenizerState.eq: TokenizerState.acceptEq,
      TokenizerState.gt: TokenizerState.acceptGt,
      TokenizerState.lt: TokenizerState.acceptLt,
      TokenizerState.minus: TokenizerState.acceptMinusOp,
      TokenizerState.doubleQuotedString: TokenizerState.doubleQuotedString,
      TokenizerState.singleQuotedString: TokenizerState.singleQuotedString,
      TokenizerState.doubleQuotedRawString:
          TokenizerState.doubleQuotedRawString,
      TokenizerState.singleQuotedRawString:
          TokenizerState.singleQuotedRawString,
      TokenizerState.escapeDoubleQuotedString:
          TokenizerState.doubleQuotedString,
      TokenizerState.escapeSingleQuotedString:
          TokenizerState.singleQuotedString,
      TokenizerState.comment: TokenizerState.comment,
    };
  }

  static Map<TokenizerState, TokenTypes> createAcceptStateTable() {
    return {
      TokenizerState.acceptComma: TokenTypes.comma,
      TokenizerState.acceptDot: TokenTypes.dot,
      TokenizerState.acceptColon: TokenTypes.colon,
      TokenizerState.acceptSemiColon: TokenTypes.semiColon,
      TokenizerState.acceptAssignment: TokenTypes.assignment,
      TokenizerState.acceptLambda: TokenTypes.lambda,
      TokenizerState.acceptDivOp: TokenTypes.div,
      TokenizerState.acceptModOp: TokenTypes.mod,
      TokenizerState.acceptPowOp: TokenTypes.pow,
      TokenizerState.acceptEq: TokenTypes.eq,
      TokenizerState.acceptFloat: TokenTypes.floatLiteral,
      TokenizerState.acceptMatch: TokenTypes.match,
      TokenizerState.acceptNotMatch: TokenTypes.notMatch,
      TokenizerState.acceptNot: TokenTypes.not,
      TokenizerState.acceptGt: TokenTypes.gt,
      TokenizerState.acceptGtEq: TokenTypes.gtEq,
      TokenizerState.acceptIdentifier: TokenTypes.identifier,
      TokenizerState.acceptLSquareBrack: TokenTypes.lSquareBrack,
      TokenizerState.acceptLPar: TokenTypes.lPar,
      TokenizerState.acceptLBrace: TokenTypes.lBrace,
      TokenizerState.acceptLt: TokenTypes.lt,
      TokenizerState.acceptLtEq: TokenTypes.ltEq,
      TokenizerState.acceptMinusOp: TokenTypes.sub,
      TokenizerState.acceptMulOp: TokenTypes.mul,
      TokenizerState.acceptNeq: TokenTypes.neq,
      TokenizerState.acceptNumber: TokenTypes.integerLiteral,
      TokenizerState.acceptDoubleQuotedString:
          TokenTypes.doubleQuotedStringLiteral,
      TokenizerState.acceptDoubleQuotedRawString:
          TokenTypes.doubleQuotedRawStringLiteral,
      TokenizerState.acceptSingleQuotedString:
          TokenTypes.singleQuotedStringLiteral,
      TokenizerState.acceptSingleQuotedRawString:
          TokenTypes.singleQuotedRawStringLiteral,
      TokenizerState.acceptPlusOp: TokenTypes.add,
      TokenizerState.acceptRSquareBrack: TokenTypes.rSquareBrack,
      TokenizerState.acceptRPar: TokenTypes.rPar,
      TokenizerState.acceptRBrace: TokenTypes.rBrace,
    };
  }

  TokenizerState _state = TokenizerState.start;
  int _lineNumber = 1;
  int _columnNumber = 1;
  StringBuffer _buffer = StringBuffer();
  CodeLocation? _bufferStartLocation;

  static final Map<String, ECharCodeClasses> _charCodeClassTable =
      createCharCodeClassTable();

  static final Map<(TokenizerState, ECharCodeClasses), TokenizerState>
  _transitionTable = createTransitionTable();
  static final Map<TokenizerState, TokenizerState> _defaultTransitionTable =
      createDefaultTransitionTable();
  static final Map<TokenizerState, TokenTypes> _acceptStateTable =
      createAcceptStateTable();
}
