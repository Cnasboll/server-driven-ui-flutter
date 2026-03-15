/// Compiler bytecode snapshot tests.
///
/// Every test compiles a SHQL™ expression and compares the exact disassembled
/// instruction sequence against a golden list.  Unintentional drift in compiler
/// output is caught automatically; intentional changes require updating the
/// golden lists here.
///
/// Only expressions that reference undefined variables are kept here
/// (they cannot be run through the engine).  All runnable expressions are
/// covered by engine_test.dart via shqlBoth/shqlBothStdlib, which checks both
/// the evaluated result and the bytecode golden in one shot.
library;

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/parser.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

BytecodeProgram compileProgram(String src) {
  final cs = Runtime.prepareConstantsSet();
  final tree = Parser.parse(src, cs, sourceCode: src);
  return BytecodeCompiler.compile(tree, cs);
}

BytecodeChunk compileMain(String src) => compileProgram(src)['main'];

const _nameOps = {Opcode.loadVar, Opcode.storeVar, Opcode.getMember, Opcode.setMember};
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
    if (_nameOps.contains(instr.op)) return '${instr.op.mnemonic}(${chunk.constants[instr.operand]})';
    if (_constOps.contains(instr.op)) return '${instr.op.mnemonic}(${_fmtConst(chunk.constants[instr.operand])})';
    return '${instr.op.mnemonic}(${instr.operand})';
  }).toList();
}

void main() {
// ---- Null-aware relational (with undefined var x) ----
  test('x > 5', () {
    expect(disasm(compileMain('x > 5')), [
      'load_var(X)',
      'jump_null(7)',
      'push_const(5)',
      'jump_null(6)',
      'cmp_gt',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  });

  test('x < 5', () {
    expect(disasm(compileMain('x < 5')), [
      'load_var(X)',
      'jump_null(7)',
      'push_const(5)',
      'jump_null(6)',
      'cmp_lt',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  });

  test('x >= 5', () {
    expect(disasm(compileMain('x >= 5')), [
      'load_var(X)',
      'jump_null(7)',
      'push_const(5)',
      'jump_null(6)',
      'cmp_gte',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  });

  test('x <= 5', () {
    expect(disasm(compileMain('x <= 5')), [
      'load_var(X)',
      'jump_null(7)',
      'push_const(5)',
      'jump_null(6)',
      'cmp_lte',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  });

  test('5 > x', () {
    expect(disasm(compileMain('5 > x')), [
      'push_const(5)',
      'jump_null(7)',
      'load_var(X)',
      'jump_null(6)',
      'cmp_gt',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  });

// ---- AND/OR/XOR with undefined var x ----
  test('x AND TRUE', () {
    expect(disasm(compileMain('x AND TRUE')), [
      'load_var(X)',
      'push_const(true)',
      'log_and',
      'ret',
    ]);
  });

  test('TRUE AND x', () {
    expect(disasm(compileMain('TRUE AND x')), [
      'push_const(true)',
      'load_var(X)',
      'log_and',
      'ret',
    ]);
  });

  test('x AND FALSE', () {
    expect(disasm(compileMain('x AND FALSE')), [
      'load_var(X)',
      'push_const(false)',
      'log_and',
      'ret',
    ]);
  });

  test('(x>5) AND TRUE', () {
    expect(disasm(compileMain('(x>5) AND TRUE')), [
      'load_var(X)',
      'jump_null(7)',
      'push_const(5)',
      'jump_null(6)',
      'cmp_gt',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'push_const(true)',
      'log_and',
      'ret',
    ]);
  });

  test('x OR TRUE', () {
    expect(disasm(compileMain('x OR TRUE')), [
      'load_var(X)',
      'push_const(true)',
      'log_or',
      'ret',
    ]);
  });

  test('x OR FALSE', () {
    expect(disasm(compileMain('x OR FALSE')), [
      'load_var(X)',
      'push_const(false)',
      'log_or',
      'ret',
    ]);
  });

  test('x XOR TRUE', () {
    expect(disasm(compileMain('x XOR TRUE')), [
      'load_var(X)',
      'push_const(true)',
      'log_and',
      'push_const(true)',
      'push_const(true)',
      'log_and',
      'cmp_neq',
      'ret',
    ]);
  });

  test('x XOR FALSE', () {
    expect(disasm(compileMain('x XOR FALSE')), [
      'load_var(X)',
      'push_const(true)',
      'log_and',
      'push_const(false)',
      'push_const(true)',
      'log_and',
      'cmp_neq',
      'ret',
    ]);
  });

// ---- NOT with undefined var x ----
  test('NOT x', () {
    expect(disasm(compileMain('NOT x')), [
      'load_var(X)',
      'jump_null(3)',
      'log_not',
      'ret',
    ]);
  });

// ---- Giants predicate ----
  test('(height > avg + 2 * stdev) AND (stdev > 0)', () {
    expect(disasm(compileMain('(height > avg + 2 * stdev) AND (stdev > 0)')), [
      'load_var(HEIGHT)',
      'jump_null(23)',
      'load_var(AVG)',
      'jump_null(17)',
      'push_const(2)',
      'jump_null(11)',
      'load_var(STDEV)',
      'jump_null(10)',
      'mul',
      'jump(13)',
      'pop',
      'pop',
      'push_const(null)',
      'jump_null(16)',
      'add',
      'jump(19)',
      'pop',
      'pop',
      'push_const(null)',
      'jump_null(22)',
      'cmp_gt',
      'jump(25)',
      'pop',
      'pop',
      'push_const(null)',
      'load_var(STDEV)',
      'jump_null(32)',
      'push_const(0)',
      'jump_null(31)',
      'cmp_gt',
      'jump(34)',
      'pop',
      'pop',
      'push_const(null)',
      'log_and',
      'ret',
    ]);
  });

// ---- Member/index access on undefined vars ----
  test('obj.x', () {
    expect(disasm(compileMain('obj.x')), [
      'load_var(OBJ)',
      'get_member(X)',
      'ret',
    ]);
  });

  test('x[0]', () {
    expect(disasm(compileMain('x[0]')), [
      'load_var(X)',
      'push_const(0)',
      'get_index',
      'ret',
    ]);
  });
}
