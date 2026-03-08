/// Migrates runnable tests from bytecode_compiler_test.dart to engine_test.dart.
///
/// For each test() in bytecode_compiler_test.dart:
///   1. Extracts the SHQL source from compileMain()/compileProgram() calls.
///   2. Tries to run it through the engine (plain, then with stdlib).
///   3. If runnable → emits a shqlBoth or shqlBothStdlib call.
///   4. If not (undefined variable / runtime error) → prints a comment to keep.
///
/// Run with: dart run tool/migrate_compiler_test.dart > /tmp/additions.dart
///
/// Then manually review and append the output to engine_test.dart.
library;

import 'dart:io';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';

// ---------------------------------------------------------------------------
// Minimal Dart-source parser (same logic as regen_engine_test.dart)
// ---------------------------------------------------------------------------

int _skipWs(String s, int pos) {
  while (pos < s.length) {
    final c = s[pos];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      pos++;
    } else if (c == '/' && pos + 1 < s.length && s[pos + 1] == '/') {
      while (pos < s.length && s[pos] != '\n') pos++;
    } else if (c == '/' && pos + 1 < s.length && s[pos + 1] == '*') {
      pos += 2;
      while (pos + 1 < s.length && !(s[pos] == '*' && s[pos + 1] == '/')) pos++;
      pos += 2;
    } else {
      break;
    }
  }
  return pos;
}

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

(String, int) _parseStr(String s, int pos) {
  bool raw = false;
  if (pos < s.length && s[pos] == 'r') {
    raw = true;
    pos++;
  }
  final q = s[pos];
  pos++;
  bool triple = pos + 1 < s.length && s[pos] == q && s[pos + 1] == q;
  if (triple) pos += 2;
  final buf = StringBuffer();
  while (pos < s.length) {
    if (triple) {
      if (s[pos] == q && pos + 2 < s.length && s[pos + 1] == q && s[pos + 2] == q) {
        pos += 3;
        break;
      }
    } else {
      if (s[pos] == q) { pos++; break; }
    }
    if (!raw && s[pos] == '\\') {
      pos++;
      if (pos < s.length) {
        switch (s[pos]) {
          case 'n': buf.write('\n');
          case 'r': buf.write('\r');
          case 't': buf.write('\t');
          case '\\': buf.write('\\');
          case '\$': buf.write('\$');
          default: buf.write(s[pos]);
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

(String, int) _parseStrArg(String s, int pos) {
  pos = _skipWs(s, pos);
  final buf = StringBuffer();
  while (_isStrStart(s, pos)) {
    final (str, next) = _parseStr(s, pos);
    buf.write(str);
    pos = _skipWs(s, next);
  }
  return (buf.toString(), pos);
}

int _skipArg(String s, int pos) {
  int depth = 0;
  pos = _skipWs(s, pos);
  while (pos < s.length) {
    final c = s[pos];
    if (c == '(' || c == '[' || c == '{') { depth++; pos++; }
    else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) break;
      depth--;
      pos++;
    } else if (c == ',' && depth == 0) {
      break;
    } else if (_isStrStart(s, pos)) {
      final (_, next) = _parseStr(s, pos);
      pos = _skipWs(s, next);
    } else {
      pos++;
    }
  }
  return pos;
}

// ---------------------------------------------------------------------------
// Extract (String rawSrc, String srcText) from compileMain(...) / compileProgram(...)
// Returns null if not parseable.
// ---------------------------------------------------------------------------

String? _extractSrc(String s, int callEnd) {
  // callEnd points past 'compileMain(' or 'compileProgram('
  try {
    final (src, _) = _parseStrArg(s, callEnd);
    return src;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Engine execution helpers
// ---------------------------------------------------------------------------

Future<dynamic> _runEngine(String src) => Engine.execute(src);

late String _stdlibSrc;

Future<dynamic> _runEngineWithStdlib(String src) async {
  final cs = Runtime.prepareConstantsSet();
  final runtime = Runtime.prepareRuntime(cs);
  await Engine.execute(_stdlibSrc, runtime: runtime, constantsSet: cs);
  return Engine.execute(src, runtime: runtime, constantsSet: cs);
}


// ---------------------------------------------------------------------------
// Format a value as a Dart literal suitable for the 3rd argument of shqlBoth.
// ---------------------------------------------------------------------------

String _fmtValue(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return '$v';
  if (v is int) return '$v';
  if (v is double) {
    // Use the full-precision repr.
    if (v == v.truncateToDouble()) {
      // Whole number double — use .0 suffix.
      return '${v.toInt()}.0';
    }
    return '$v';
  }
  if (v is String) {
    final escaped = v.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    return "'$escaped'";
  }
  if (v is List) {
    if (v.isEmpty) return '[]';
    final items = v.map(_fmtValue).join(', ');
    return '[$items]';
  }
  if (v is Map) {
    if (v.isEmpty) return '{}';
    final items = v.entries.map((e) => '${_fmtValue(e.key)}: ${_fmtValue(e.value)}').join(', ');
    return '{$items}';
  }
  // Complex type — not representable as a literal.
  return null.toString(); // fallback: won't be used
}

// ---------------------------------------------------------------------------
// Extract tests from bytecode_compiler_test.dart
// ---------------------------------------------------------------------------

class TestEntry {
  final String name;
  final String src;
  final List<String> bytecodes;

  TestEntry(this.name, this.src, this.bytecodes);
}

List<TestEntry> _parseTests(String content) {
  final entries = <TestEntry>[];
  int pos = 0;

  while (pos < content.length) {
    // Find 'test(' at start of line
    final idx = content.indexOf("test('", pos);
    if (idx == -1) break;
    // Check it's at start of line (only whitespace before it)
    int lineStart = idx;
    while (lineStart > 0 && content[lineStart - 1] != '\n') lineStart--;
    final prefix = content.substring(lineStart, idx);
    if (prefix.trimLeft().isNotEmpty) {
      pos = idx + 6;
      continue;
    }

    pos = idx + 6; // past "test('"
    // Extract test name
    try {
      // We're right at the char after test(' so we already consumed the opening quote.
      // Actually _parseStr expects to be at the quote character.
      // Backtrack: pos points to the char AFTER the opening '.
      final nameStart = idx + 5; // at opening '
      final (name, afterName) = _parseStr(content, nameStart);
      pos = _skipWs(content, afterName);
      if (pos >= content.length || content[pos] != ',') continue;
      pos++;
      pos = _skipWs(content, pos);
      // Skip the () => { or () { wrapper
      // Find compileMain( or compileProgram( within this test body
      // Scan for end of this test (find matching })
      // Simple heuristic: find compileMain( or compileProgram(
      final testBodyStart = pos;
      // Find the closing }) for this test — track brace depth
      int depth = 0;
      int testBodyEnd = pos;
      while (testBodyEnd < content.length) {
        final c = content[testBodyEnd];
        if (c == '{' || c == '(' || c == '[') depth++;
        else if (c == '}' || c == ')' || c == ']') {
          if (depth == 0) break;
          depth--;
        } else if (_isStrStart(content, testBodyEnd)) {
          final (_, next) = _parseStr(content, testBodyEnd);
          testBodyEnd = next;
          continue;
        }
        testBodyEnd++;
      }
      // testBodyEnd is now at the ')' closing the test() call
      final testBody = content.substring(testBodyStart, testBodyEnd);

      // Find compileMain( or compileProgram( in the body
      String? src;
      for (final token in ['compileMain(', 'compileProgram(']) {
        final ti = testBody.indexOf(token);
        if (ti == -1) continue;
        src = _extractSrc(testBody, ti + token.length);
        if (src != null) break;
      }
      if (src == null) {
        pos = testBodyEnd + 1;
        continue;
      }

      // Extract bytecodes: find the list [...] after expect(disasm(...), [
      final expectIdx = testBody.indexOf('expect(disasm(');
      if (expectIdx == -1) {
        pos = testBodyEnd + 1;
        continue;
      }
      // Find the list: after the second argument to expect
      // skip past expect(disasm(...),
      int ep = expectIdx + 14; // past 'expect(disasm('
      ep = _skipArg(testBody, ep); // skip the compileMain(...) arg
      ep = _skipWs(testBody, ep);
      if (ep < testBody.length && testBody[ep] == ')') ep++; // closing of disasm(...)
      ep = _skipWs(testBody, ep);
      if (ep < testBody.length && testBody[ep] == ',') ep++;
      ep = _skipWs(testBody, ep);
      // Now ep should point to [
      if (ep >= testBody.length || testBody[ep] != '[') {
        pos = testBodyEnd + 1;
        continue;
      }
      // Parse the list of string literals
      final bytecodes = <String>[];
      ep++; // past [
      while (true) {
        ep = _skipWs(testBody, ep);
        if (ep >= testBody.length || testBody[ep] == ']') break;
        if (!_isStrStart(testBody, ep)) { ep++; continue; }
        final (bc, next) = _parseStr(testBody, ep);
        bytecodes.add(bc);
        ep = _skipWs(testBody, next);
        if (ep < testBody.length && testBody[ep] == ',') ep++;
      }

      entries.add(TestEntry(name, src, bytecodes));
      pos = testBodyEnd + 1;
    } catch (e) {
      pos++;
    }
  }
  return entries;
}

// ---------------------------------------------------------------------------
// Format bytecode list as Dart source
// ---------------------------------------------------------------------------

String _fmtBc(List<String> bc, String indent) {
  if (bc.isEmpty) return '[]';
  final itemIndent = '$indent    ';
  final closeIndent = '$indent  ';
  final lines = bc.map((i) => "$itemIndent'${i.replaceAll("'", "\\'")}',").join('\n');
  return '[\n$lines\n$closeIndent]';
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() async {
  _stdlibSrc = await File('assets/stdlib.shql').readAsString();

  final content = await File('test/bytecode_compiler_test.dart').readAsString();
  final tests = _parseTests(content);

  stderr.writeln('Parsed ${tests.length} tests.');

  // Try to figure out which SHQL sources are already in engine_test.dart.
  final engineTestContent = await File('test/engine_test.dart').readAsString();

  final runnable = <(TestEntry, bool, dynamic)>[]; // (entry, needsStdlib, result)
  final undefinedVar = <TestEntry>[];

  for (final entry in tests) {
    // Check if already covered in engine_test.dart (exact src match or close)
    final srcEscaped = entry.src.replaceAll("'", "\\'");
    if (engineTestContent.contains("'${entry.src}'") ||
        engineTestContent.contains('"${entry.src}"') ||
        engineTestContent.contains("'$srcEscaped'")) {
      stderr.writeln('SKIP (already in engine_test): ${entry.name}');
      continue;
    }

    // Try plain engine run
    dynamic result;
    bool needsStdlib = false;
    bool failed = false;
    try {
      result = await _runEngine(entry.src);
    } catch (e) {
      // Try with stdlib
      try {
        result = await _runEngineWithStdlib(entry.src);
        needsStdlib = true;
      } catch (e2) {
        // Cannot run — undefined variable or other error
        undefinedVar.add(entry);
        stderr.writeln('UNRUNNABLE: ${entry.name} => $e2');
        failed = true;
      }
    }
    if (!failed) {
      runnable.add((entry, needsStdlib, result));
    }
  }

  stderr.writeln('Runnable: ${runnable.length}, Undefined-var: ${undefinedVar.length}');
  stderr.writeln('');
  stderr.writeln('=== Additions for engine_test.dart ===');
  stderr.writeln('');

  // Print shqlBoth / shqlBothStdlib calls
  for (final (entry, needsStdlib, result) in runnable) {
    final valueStr = _fmtValue(result);
    if (valueStr == 'null' && result != null) {
      // Complex type — skip (or use a comment)
      stderr.writeln('// COMPLEX result for: ${entry.name} => ${result.runtimeType}');
      continue;
    }
    final fn = needsStdlib ? 'shqlBothStdlib' : 'shqlBoth';
    final nameSafe = entry.name.replaceAll("'", "\\'");
    final srcSafe = entry.src.contains('\n') || entry.src.contains("'")
        ? 'r\'\'\'\n${entry.src}\n\'\'\''
        : "'${entry.src.replaceAll("'", "\\'")}'";
    final bc = _fmtBc(entry.bytecodes, '  ');
    print("  $fn('$nameSafe', $srcSafe, $valueStr, $bc);");
  }

  stderr.writeln('');
  stderr.writeln('=== Keep in bytecode_compiler_test.dart ===');
  for (final e in undefinedVar) {
    stderr.writeln('  ${e.name}: ${e.src}');
  }
}
