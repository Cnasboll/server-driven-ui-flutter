/// Script that generates bytecode_compiler_test.dart.
///
/// bytecode_compiler_test.dart covers ONLY SHQL programs that can COMPILE but
/// cannot EXECUTE in the engine (because they reference undefined variables).
/// Every program that can compile AND run belongs exclusively in engine_test.dart.
///
/// Run with: dart run tool/dump_disasm.dart
import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';

BytecodeProgram compileProgram(String src) {
  final cs = Runtime.prepareConstantsSet();
  final tree = Parser.parse(src, cs, sourceCode: src);
  return BytecodeCompiler.compile(tree, cs);
}

BytecodeChunk compileMain(String src) => compileProgram(src)['main'];

const _nameOps = {
  Opcode.loadVar,
  Opcode.storeVar,
  Opcode.getMember,
  Opcode.setMember,
};
const _constOps = {Opcode.pushConst, Opcode.makeClosure};

String _fmtConst(dynamic c) {
  if (c == null) return 'null';
  if (c is String) return '"$c"';
  if (c is ChunkRef) return '.${c.name}';
  return '$c';
}

List<String> disasm(BytecodeChunk chunk) {
  return chunk.code.map((instr) {
    if (!instr.op.hasOperand) return instr.op.mnemonic;
    if (_nameOps.contains(instr.op)) {
      return '${instr.op.mnemonic}(${chunk.constants[instr.operand]})';
    }
    if (_constOps.contains(instr.op)) {
      return '${instr.op.mnemonic}(${_fmtConst(chunk.constants[instr.operand])})';
    }
    return '${instr.op.mnemonic}(${instr.operand})';
  }).toList();
}

String _quoteName(String label) {
  final escaped = label.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  return "'$escaped'";
}

String _quoteSrc(String src) {
  if (src.contains('\n')) {
    return "r'''\n$src\n'''";
  }
  if (src.contains("'")) {
    final escaped = src.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');
    return '"$escaped"';
  }
  return "'$src'";
}

void dump(String label, String src) {
  try {
    final instrs = disasm(compileMain(src));
    print("    test(${_quoteName(label)}, () {");
    print("      expect(disasm(compileMain(${_quoteSrc(src)})), [");
    for (final i in instrs) {
      print("        '$i',");
    }
    print("      ]);");
    print("    });");
    print('');
  } catch (e) {
    print("    // ERROR for '$label': $e");
    print('');
  }
}

void main() {
  // All SHQL below can COMPILE but NOT RUN in the engine because they reference
  // undefined variables.  Programs that can also run belong in engine_test.dart.

  print('// ---- Member / index access (undefined variables) ----');
  dump('obj.x', 'obj.x');
  dump('x[0]', 'x[0]');

  print('// ---- Null-aware relational (x is undefined) ----');
  dump('x > 5', 'x > 5');
  dump('x < 5', 'x < 5');
  dump('x >= 5', 'x >= 5');
  dump('x <= 5', 'x <= 5');
  dump('5 > x', '5 > x');

  print('// ---- AND / OR / XOR (x is undefined) ----');
  dump('x AND TRUE', 'x AND TRUE');
  dump('TRUE AND x', 'TRUE AND x');
  dump('x AND FALSE', 'x AND FALSE');
  dump('(x>5) AND TRUE', '(x>5) AND TRUE');
  dump('x OR TRUE', 'x OR TRUE');
  dump('x OR FALSE', 'x OR FALSE');
  dump('TRUE OR x', 'TRUE OR x');
  dump('FALSE OR x', 'FALSE OR x');
  dump('x XOR TRUE', 'x XOR TRUE');
  dump('x XOR FALSE', 'x XOR FALSE');
  dump('TRUE XOR x', 'TRUE XOR x');

  print('// ---- NOT (x is undefined) ----');
  dump('NOT x', 'NOT x');

  print('// ---- Complex expression with undefined variables ----');
  dump('(height > avg + 2 * stdev) AND (stdev > 0)',
      '(height > avg + 2 * stdev) AND (stdev > 0)');
}
