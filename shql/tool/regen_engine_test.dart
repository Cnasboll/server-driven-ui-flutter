/// Regenerates engine_test.dart by compiling every shqlBoth() and
/// shqlBothStdlib() call's SHQL source and filling in (or updating) the
/// golden expectedBytecode list (4th positional argument).
///
/// Run with: dart run tool/regen_engine_test.dart
///
/// The script reads test/engine_test.dart as plain text, locates every
/// `shqlBoth(` and `shqlBothStdlib(` call, extracts the second argument
/// (the SHQL source string, including adjacent-string forms), compiles it,
/// disassembles the `main` chunk, and rewrites the call to include a 4th
/// positional argument:
///   , [
///       'instr1',
///       ...
///   ]
/// If a 4th positional list (or legacy `expectedBytecode:` named arg) is
/// already present it is replaced with the freshly compiled version.
library;

import 'dart:io';
import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';

// ---------------------------------------------------------------------------
// Disasm helpers — identical logic to the helpers in engine_test.dart
// ---------------------------------------------------------------------------

const _nameOpMnemonics = {'load_var', 'store_var', 'get_member', 'set_member'};
const _constOpMnemonics = {'push_const', 'make_closure'};

String _fmtConst(dynamic c) {
  if (c == null) return 'null';
  if (c is bool) return '$c';
  if (c is String) return '"${c.replaceAll('\\', '\\\\')}"';
  if (c is num) return '$c';
  return '.${(c as dynamic).name}'; // ChunkRef
}

List<String> _disasm(dynamic chunk) {
  final constants = chunk.constants as List;
  return (chunk.code as List).map<String>((instr) {
    final mnemonic = (instr.op as dynamic).mnemonic as String;
    final hasOperand = (instr.op as dynamic).hasOperand as bool;
    if (!hasOperand) return mnemonic;
    final operand = instr.operand as int;
    // Only index into constants for name/const ops; jump ops use instruction indices.
    if (_nameOpMnemonics.contains(mnemonic)) return '$mnemonic(${constants[operand]})';
    if (_constOpMnemonics.contains(mnemonic)) return '$mnemonic(${_fmtConst(constants[operand])})';
    return '$mnemonic($operand)';
  }).toList();
}

/// Returns null if compilation fails.
List<String>? _compileAndDisasm(String src) {
  try {
    final cs = Runtime.prepareConstantsSet();
    final tree = Parser.parse(src, cs, sourceCode: src);
    final program = BytecodeCompiler.compile(tree, cs);
    final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
    return _disasm(decoded['main']);
  } catch (e, st) {
    stderr.writeln('  compile exception: $e\n$st');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Dart source parser (minimal, handles patterns found in engine_test.dart)
// ---------------------------------------------------------------------------

int _skipWs(String s, int pos) {
  while (pos < s.length) {
    final c = s[pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      pos++;
    } else if (c == '/' && pos + 1 < s.length && s[pos + 1] == '/') {
      // line comment
      while (pos < s.length && s[pos] != '\n') pos++;
    } else if (c == '/' && pos + 1 < s.length && s[pos + 1] == '*') {
      // block comment
      pos += 2;
      while (pos + 1 < s.length && !(s[pos] == '*' && s[pos + 1] == '/')) pos++;
      pos += 2;
    } else {
      break;
    }
  }
  return pos;
}

/// Returns true when [s[pos]..] starts a Dart string literal (possibly raw).
bool _isStrStart(String s, int pos) {
  if (pos >= s.length) return false;
  final c = s[pos];
  if (c == "'" || c == '"') return true;
  if (c == 'r' && pos + 1 < s.length) {
    final n = s[pos + 1];
    return n == "'" || n == '"';
  }
  return false;
}

/// Parse one Dart string literal starting at [pos].
/// Returns (decoded_value, pos_after).
(String, int) _parseStr(String s, int pos) {
  bool raw = false;
  if (pos < s.length && s[pos] == 'r') {
    raw = true;
    pos++;
  }
  final q = s[pos]; // ' or "
  pos++;
  bool triple = pos + 1 < s.length && s[pos] == q && s[pos + 1] == q;
  if (triple) pos += 2;

  final buf = StringBuffer();
  while (pos < s.length) {
    if (triple) {
      if (s[pos] == q &&
          pos + 2 < s.length &&
          s[pos + 1] == q &&
          s[pos + 2] == q) {
        pos += 3;
        break;
      }
    } else {
      if (s[pos] == q) {
        pos++;
        break;
      }
    }
    if (!raw && s[pos] == '\\') {
      pos++;
      if (pos < s.length) {
        switch (s[pos]) {
          case 'n':
            buf.write('\n');
          case 'r':
            buf.write('\r');
          case 't':
            buf.write('\t');
          case '\\':
            buf.write('\\');
          case '\$':
            buf.write('\$');
          default:
            buf.write(s[pos]);
        }
        pos++;
      }
    } else {
      buf.write(s[pos]);
      pos++;
    }
  }
  return (buf.toString(), pos);
}

/// Parse one or more adjacent Dart string literals (Dart string concatenation).
/// Returns (concatenated_value, pos_after).
(String, int) _parseStrArg(String s, int pos) {
  pos = _skipWs(s, pos);
  if (!_isStrStart(s, pos)) {
    throw FormatException(
        'Expected string literal at $pos, got: ${s.substring(pos, (pos + 30).clamp(0, s.length))}');
  }
  final buf = StringBuffer();
  while (_isStrStart(s, pos)) {
    final (str, next) = _parseStr(s, pos);
    buf.write(str);
    pos = _skipWs(s, next);
  }
  return (buf.toString(), pos);
}

/// Skip one Dart expression argument, stopping at an unmatched `,` or `)` / `]` / `}`.
/// Returns the position OF the stopping delimiter (not past it).
int _skipArg(String s, int pos) {
  int depth = 0;
  pos = _skipWs(s, pos);
  while (pos < s.length) {
    final c = s[pos];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
      pos++;
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
      pos++;
    } else if (c == ',' && depth == 0) {
      break;
    } else if (_isStrStart(s, pos)) {
      // Skip string literal (no content needed here).
      final (_, next) = _parseStr(s, pos);
      pos = _skipWs(s, next);
    } else {
      pos++;
    }
  }
  return pos;
}

/// True if s[pos..] (after whitespace) starts with identifier [id] not followed
/// by another identifier char.
bool _startsWithId(String s, int pos, String id) {
  pos = _skipWs(s, pos);
  if (pos + id.length > s.length) return false;
  if (s.substring(pos, pos + id.length) != id) return false;
  final after = pos + id.length;
  if (after >= s.length) return true;
  return !RegExp(r'[a-zA-Z0-9_]').hasMatch(s[after]);
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

String _fmtBytecodeArg(List<String> bc, String callIndent) {
  if (bc.isEmpty) return ', []';
  final itemIndent = '$callIndent    '; // 4 extra spaces
  final closeIndent = '$callIndent  '; // 2 extra spaces
  final lines = bc.map((i) => "$itemIndent'${i.replaceAll("'", "\\'")}',").join('\n');
  return ', [\n$lines\n$closeIndent]';
}

// ---------------------------------------------------------------------------
// Main processing
// ---------------------------------------------------------------------------

String _regen(String content) {
  final out = StringBuffer();
  int pos = 0;
  int processed = 0;
  int errors = 0;

  while (pos < content.length) {
    // Find whichever of shqlBoth( or shqlBothStdlib( comes first.
    final idx1 = content.indexOf('shqlBoth(', pos);       // 9 chars
    final idx2 = content.indexOf('shqlBothStdlib(', pos); // 15 chars

    // Pick the earlier occurrence.
    final int idx;
    final int tokenLen;
    if (idx1 == -1 && idx2 == -1) {
      out.write(content.substring(pos));
      break;
    } else if (idx1 == -1) {
      idx = idx2; tokenLen = 15;
    } else if (idx2 == -1) {
      idx = idx1; tokenLen = 9;
    } else if (idx1 <= idx2) {
      idx = idx1; tokenLen = 9;
    } else {
      idx = idx2; tokenLen = 15;
    }

    // Reject function/method definitions: if there is non-whitespace text
    // before the token on the same line, this is a definition, not a call.
    int lineStart = idx;
    while (lineStart > 0 && content[lineStart - 1] != '\n') lineStart--;
    final rawPrefix = content.substring(lineStart, idx);
    if (rawPrefix.trimLeft().isNotEmpty) {
      out.write(content.substring(pos, idx + tokenLen));
      pos = idx + tokenLen;
      continue;
    }

    // Copy everything before this call.
    out.write(content.substring(pos, idx));
    final callIndent =
        RegExp(r'^[ \t]*').firstMatch(rawPrefix)?.group(0) ?? '';

    int argPos = idx + tokenLen; // right after 'shqlBoth(' or 'shqlBothStdlib('

    try {
      // 1. Skip name argument.
      argPos = _skipWs(content, argPos);
      argPos = _skipArg(content, argPos);

      // 2. Skip comma between name and src.
      argPos = _skipWs(content, argPos);
      if (argPos >= content.length || content[argPos] != ',') {
        throw FormatException('Expected , after name arg');
      }
      argPos++;

      // 3. Extract src argument (may be adjacent string literals).
      argPos = _skipWs(content, argPos);
      final (shqlSrc, afterSrc) = _parseStrArg(content, argPos);
      argPos = afterSrc; // position of , or ) after src

      // 4. Skip comma between src and expected.
      argPos = _skipWs(content, argPos);
      if (argPos >= content.length || content[argPos] != ',') {
        throw FormatException('Expected , after src arg');
      }
      argPos++;

      // 5. Skip expected argument.
      argPos = _skipWs(content, argPos);
      final afterExpected = _skipArg(content, argPos);
      argPos = afterExpected;
      argPos = _skipWs(content, argPos);

      // 6. Detect existing expectedBytecode argument (positional list or legacy named).
      int existingBcStart = -1; // position of the ',' that precedes the bytecode
      int existingBcEnd = -1;   // position right after the list value

      if (argPos < content.length && content[argPos] == ',') {
        final peekPos = _skipWs(content, argPos + 1);
        if (_startsWithId(content, peekPos, 'expectedBytecode')) {
          // Legacy named style: , expectedBytecode: [...]
          existingBcStart = argPos;
          int ep = argPos + 1;
          ep = _skipWs(content, ep);
          while (ep < content.length &&
              RegExp(r'[a-zA-Z0-9_]').hasMatch(content[ep])) ep++;
          ep = _skipWs(content, ep);
          if (ep < content.length && content[ep] == ':') ep++;
          ep = _skipWs(content, ep);
          ep = _skipArg(content, ep);
          existingBcEnd = ep;
        } else if (peekPos < content.length && content[peekPos] == '[') {
          // Positional style: , [...]
          existingBcStart = argPos;
          int ep = peekPos;
          ep = _skipArg(content, ep);
          existingBcEnd = ep;
        }
      }

      // 7. Compile and disassemble.
      final bc = _compileAndDisasm(shqlSrc);
      if (bc == null) {
        errors++;
        stderr.writeln('WARN: compile failed for: '
            '${shqlSrc.length > 60 ? "${shqlSrc.substring(0, 60)}..." : shqlSrc}');
        // Leave this call unchanged.
        final end = existingBcEnd >= 0 ? existingBcEnd : argPos;
        out.write(content.substring(idx, end));
        pos = end;
        continue;
      }

      // 8. Write the rewritten call.
      final bcArg = _fmtBytecodeArg(bc, callIndent);
      if (existingBcStart >= 0) {
        // Replace existing arg: copy from idx to the comma, then new arg.
        out.write(content.substring(idx, existingBcStart));
        out.write(bcArg);
        pos = existingBcEnd;
      } else {
        // Insert before the closing ')': copy from idx to argPos, then new arg.
        out.write(content.substring(idx, argPos));
        out.write(bcArg);
        pos = argPos;
      }
      processed++;
    } catch (e) {
      errors++;
      stderr.writeln('ERROR at position $idx: $e\n'
          '  context: ${content.substring(idx, (idx + 80).clamp(0, content.length))}');
      // Copy the token we were at unchanged and continue.
      out.write(content.substring(idx, idx + tokenLen));
      pos = idx + tokenLen;
    }
  }

  stderr.writeln('Done: $processed shqlBoth/shqlBothStdlib calls updated, $errors errors.');
  return out.toString();
}

void main() {
  final file = File('test/engine_test.dart');
  final content = file.readAsStringSync();
  final result = _regen(content);
  file.writeAsStringSync(result);
  stdout.writeln('engine_test.dart rewritten.');
}
