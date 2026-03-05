/// Parser for the SHQL™ bytecode text format.
///
/// The format is a sequence of `.chunk` sections, each containing optional
/// `.constants:`, `.params:`, and `.code:` sub-sections.  Comments use the
/// same `--` syntax as SHQL™.
///
/// Tokenisation is performed by the standard SHQL™ [Tokenizer] with a
/// lightweight post-processing step that merges consecutive [TokenTypes.dot]
/// + [TokenTypes.identifier] tokens into a single [TokenTypes.directive] token
/// (e.g., `.chunk`, `.loop_start`).  This keeps the existing SHQL™ state
/// machine untouched.
library;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/tokenizer/token.dart';
import 'package:shql/tokenizer/tokenizer.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class BytecodeParseError implements Exception {
  final String message;

  BytecodeParseError(this.message);

  @override
  String toString() => 'BytecodeParseError: $message';
}

// ---------------------------------------------------------------------------
// Bytecode tokeniser (post-processor)
// ---------------------------------------------------------------------------

/// Runs the SHQL™ [Tokenizer] on [source], then merges every
/// `dot` + `identifier` pair into a single [TokenTypes.directive] token.
List<Token> tokenizeBytecode(String source) {
  final raw = Tokenizer.tokenize(source).toList();
  final result = <Token>[];
  var i = 0;
  while (i < raw.length) {
    final tok = raw[i];
    if (tok.tokenType == TokenTypes.dot &&
        i + 1 < raw.length &&
        raw[i + 1].tokenType == TokenTypes.identifier) {
      final next = raw[i + 1];
      result.add(
        Token.parser(
          TokenTypes.directive,
          '.${next.lexeme}',
          tok.startLocation,
        ),
      );
      i += 2;
    } else {
      result.add(tok);
      i++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class BytecodeParser {
  final List<Token> _tokens;
  int _pos = 0;

  BytecodeParser._(this._tokens);

  factory BytecodeParser.fromSource(String source) =>
      BytecodeParser._(tokenizeBytecode(source));

  // ---- Public entry point -------------------------------------------------

  BytecodeProgram parse() {
    final chunks = <String, BytecodeChunk>{};
    while (_pos < _tokens.length) {
      final chunk = _parseChunk();
      chunks[chunk.name] = chunk;
    }
    if (chunks.isEmpty) {
      throw BytecodeParseError('No chunks found in bytecode source');
    }
    return BytecodeProgram(chunks);
  }

  // ---- Chunk --------------------------------------------------------------

  BytecodeChunk _parseChunk() {
    _expectDirective('.chunk');
    final name = _expectIdentifier();
    _expectTokenType(TokenTypes.colon);

    List<dynamic> constants = const [];
    List<String> params = const [];
    List<Instruction> code = const [];

    while (_pos < _tokens.length) {
      final tok = _peek();
      if (tok == null) break;
      if (!_isDirective(tok)) break;
      if (tok.lexeme == '.chunk') break; // next chunk starts

      _advance();
      switch (tok.lexeme) {
        case '.constants':
          _expectTokenType(TokenTypes.colon);
          constants = _parseConstants();
        case '.params':
          _expectTokenType(TokenTypes.colon);
          params = _parseParams();
        case '.code':
          _expectTokenType(TokenTypes.colon);
          code = _parseCode(constants);
        default:
          throw BytecodeParseError('Unknown section "${tok.lexeme}"');
      }
    }

    return BytecodeChunk(
      name: name,
      constants: constants,
      params: params,
      code: code,
    );
  }

  // ---- .constants: --------------------------------------------------------

  List<dynamic> _parseConstants() {
    final result = <dynamic>[];
    while (_pos < _tokens.length) {
      final tok = _peek();
      if (tok == null) break;
      if (_endsSection(tok)) break;
      if (tok.tokenType != TokenTypes.integerLiteral) break;
      _advance(); // consume index (order is implicit, index ignored)
      _expectTokenType(TokenTypes.colon);
      result.add(_parseConstantValue());
    }
    return result;
  }

  dynamic _parseConstantValue() {
    final tok = _advance();
    if (tok == null) throw BytecodeParseError('Expected constant value, got EOF');

    switch (tok.tokenType) {
      case TokenTypes.integerLiteral:
        return int.parse(tok.lexeme);
      case TokenTypes.floatLiteral:
        return double.parse(tok.lexeme);
      case TokenTypes.doubleQuotedStringLiteral:
        return tok.lexeme.substring(1, tok.lexeme.length - 1);
      case TokenTypes.singleQuotedStringLiteral:
        return tok.lexeme.substring(1, tok.lexeme.length - 1);
      case TokenTypes.identifier:
        // Bare word → identifier name (for loadVar / storeVar operands)
        return tok.lexeme;
      case TokenTypes.directive:
        // .chunkName → ChunkRef (strip leading dot)
        return ChunkRef(tok.lexeme.substring(1));
      case TokenTypes.sub:
        // Negative number
        final num = _advance();
        if (num == null) throw BytecodeParseError('Expected number after "-"');
        if (num.tokenType == TokenTypes.integerLiteral) {
          return -int.parse(num.lexeme);
        }
        if (num.tokenType == TokenTypes.floatLiteral) {
          return -double.parse(num.lexeme);
        }
        throw BytecodeParseError(
          'Expected number after "-", got "${num.lexeme}"',
        );
      default:
        throw BytecodeParseError(
          'Unexpected constant value "${tok.lexeme}" (${tok.tokenType})',
        );
    }
  }

  // ---- .params: -----------------------------------------------------------

  List<String> _parseParams() {
    final result = <String>[];
    while (_pos < _tokens.length) {
      final tok = _peek();
      if (tok == null) break;
      if (_endsSection(tok)) break;
      if (tok.tokenType != TokenTypes.identifier) break;
      result.add(_advance()!.lexeme);
    }
    return result;
  }

  // ---- .code: -------------------------------------------------------------

  List<Instruction> _parseCode(List<dynamic> constants) {
    final instructions = <Instruction>[];
    final labels = <String, int>{}; // directive lexeme → instruction index
    final fixups = <(int instrIdx, String label)>[];

    void resolveFixups(String label) {
      for (final (idx, _) in fixups.where((f) => f.$2 == label).toList()) {
        final old = instructions[idx];
        instructions[idx] = Instruction(old.op, instructions.length);
      }
      fixups.removeWhere((f) => f.$2 == label);
    }

    while (_pos < _tokens.length) {
      final tok = _peek();
      if (tok == null) break;
      if (_endsSection(tok)) break;

      // Directive at this position is either a label definition or an error
      if (_isDirective(tok)) {
        _advance();
        final next = _peek();
        if (next != null && next.tokenType == TokenTypes.colon) {
          _advance(); // consume ':'
          labels[tok.lexeme] = instructions.length;
          resolveFixups(tok.lexeme);
          continue;
        }
        throw BytecodeParseError(
          'Unexpected directive "${tok.lexeme}" in .code — '
          'did you forget the ":" for a label definition?',
        );
      }

      // Must be an opcode (identifier token, which includes SHQL keywords)
      if (tok.tokenType != TokenTypes.identifier) {
        throw BytecodeParseError(
          'Expected opcode, got "${tok.lexeme}" (${tok.tokenType})',
        );
      }
      _advance();
      final opcode = _parseOpcode(tok.lexeme);

      if (_opcodeHasOperand(opcode)) {
        final operandTok = _peek();
        if (operandTok == null) {
          throw BytecodeParseError('Expected operand for opcode "${tok.lexeme}"');
        }

        if (_isDirective(operandTok)) {
          // Jump / closure target: .label_name
          _advance();
          final label = operandTok.lexeme;
          if (labels.containsKey(label)) {
            instructions.add(Instruction(opcode, labels[label]!));
          } else {
            fixups.add((instructions.length, label));
            instructions.add(Instruction(opcode, -1)); // placeholder
          }
        } else if (operandTok.tokenType == TokenTypes.integerLiteral) {
          _advance();
          instructions.add(Instruction(opcode, int.parse(operandTok.lexeme)));
        } else if (operandTok.tokenType == TokenTypes.sub) {
          _advance();
          final num = _advance();
          if (num == null || num.tokenType != TokenTypes.integerLiteral) {
            throw BytecodeParseError('Expected integer after "-" in operand');
          }
          instructions.add(Instruction(opcode, -int.parse(num.lexeme)));
        } else {
          throw BytecodeParseError(
            'Expected operand for "${tok.lexeme}", got "${operandTok.lexeme}"',
          );
        }
      } else {
        instructions.add(Instruction(opcode));
      }
    }

    if (fixups.isNotEmpty) {
      final unresolved = fixups.map((f) => f.$2).toSet();
      throw BytecodeParseError('Unresolved labels: ${unresolved.join(', ')}');
    }

    return instructions;
  }

  // ---- Opcode dispatch table ----------------------------------------------

  static Opcode _parseOpcode(String name) {
    return switch (name.toLowerCase()) {
      'push_const' => Opcode.pushConst,
      'load_var' => Opcode.loadVar,
      'store_var' => Opcode.storeVar,
      'pop' => Opcode.pop,
      'add' => Opcode.add,
      'sub' => Opcode.sub,
      'mul' => Opcode.mul,
      'div' => Opcode.div,
      'mod' => Opcode.mod,
      'neg' => Opcode.neg,
      'cmp_eq' || 'cmpeq' => Opcode.cmpEq,
      'cmp_neq' || 'cmpneq' => Opcode.cmpNeq,
      'cmp_lt' || 'cmplt' => Opcode.cmpLt,
      'cmp_lte' || 'cmplte' => Opcode.cmpLte,
      'cmp_gt' || 'cmpgt' => Opcode.cmpGt,
      'cmp_gte' || 'cmpgte' => Opcode.cmpGte,
      'log_and' || 'logand' => Opcode.logAnd,
      'log_or' || 'logor' => Opcode.logOr,
      'log_not' || 'lognot' => Opcode.logNot,
      'jump' => Opcode.jump,
      'jump_false' || 'jumpfalse' => Opcode.jumpFalse,
      'jump_true' || 'jumptrue' => Opcode.jumpTrue,
      'push_scope' || 'pushscope' => Opcode.pushScope,
      'pop_scope' || 'popscope' => Opcode.popScope,
      'call' => Opcode.call,
      'make_closure' || 'makeclosure' => Opcode.makeClosure,
      'ret' || 'return' => Opcode.ret,
      'get_member' || 'getmember' => Opcode.getMember,
      'set_member' || 'setmember' => Opcode.setMember,
      'get_index' || 'getindex' => Opcode.getIndex,
      'set_index' || 'setindex' => Opcode.setIndex,
      'make_list' || 'makelist' => Opcode.makeList,
      'make_object' || 'makeobject' => Opcode.makeObject,
      _ => throw BytecodeParseError('Unknown opcode: "$name"'),
    };
  }

  static bool _opcodeHasOperand(Opcode op) => switch (op) {
    Opcode.pushConst ||
    Opcode.loadVar ||
    Opcode.storeVar ||
    Opcode.jump ||
    Opcode.jumpFalse ||
    Opcode.jumpTrue ||
    Opcode.call ||
    Opcode.makeClosure ||
    Opcode.getMember ||
    Opcode.setMember ||
    Opcode.makeList ||
    Opcode.makeObject => true,
    _ => false,
  };

  // ---- Helpers ------------------------------------------------------------

  bool _endsSection(Token tok) {
    if (!_isDirective(tok)) return false;
    return tok.lexeme == '.chunk' ||
        tok.lexeme == '.constants' ||
        tok.lexeme == '.params' ||
        tok.lexeme == '.code';
  }

  bool _isDirective(Token tok) => tok.tokenType == TokenTypes.directive;

  void _expectDirective(String expected) {
    final tok = _advance();
    if (tok == null ||
        tok.tokenType != TokenTypes.directive ||
        tok.lexeme != expected) {
      throw BytecodeParseError(
        'Expected "$expected", got "${tok?.lexeme ?? "EOF"}"',
      );
    }
  }

  String _expectIdentifier() {
    final tok = _advance();
    if (tok == null || tok.tokenType != TokenTypes.identifier) {
      throw BytecodeParseError(
        'Expected identifier, got "${tok?.lexeme ?? "EOF"}"',
      );
    }
    return tok.lexeme;
  }

  void _expectTokenType(TokenTypes type) {
    final tok = _advance();
    if (tok == null || tok.tokenType != type) {
      throw BytecodeParseError(
        'Expected ${type.name}, got "${tok?.lexeme ?? "EOF"}"',
      );
    }
  }

  Token? _peek() => _pos < _tokens.length ? _tokens[_pos] : null;

  Token? _advance() => _pos < _tokens.length ? _tokens[_pos++] : null;
}
