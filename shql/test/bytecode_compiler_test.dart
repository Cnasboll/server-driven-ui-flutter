/// Compiler bytecode snapshot tests.
///
/// Every test compiles a SHQL expression and compares the exact disassembled
/// instruction sequence against a golden list.  Unintentional drift in compiler
/// output is caught automatically; intentional changes require updating the
/// golden lists here.
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
// ---- Arithmetic ----
    test('10+2', () {
      expect(disasm(compileMain('10+2')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10+13*37+1', () {
      expect(disasm(compileMain('10+13*37+1')), [
        'push_const(10)',
        'jump_null(15)',
        'push_const(13)',
        'jump_null(9)',
        'push_const(37)',
        'jump_null(8)',
        'mul',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(14)',
        'add',
        'jump(17)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(23)',
        'push_const(1)',
        'jump_null(22)',
        'add',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10+13*(37+1)', () {
      expect(disasm(compileMain('10+13*(37+1)')), [
        'push_const(10)',
        'jump_null(23)',
        'push_const(13)',
        'jump_null(17)',
        'push_const(37)',
        'jump_null(11)',
        'push_const(1)',
        'jump_null(10)',
        'add',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(16)',
        'mul',
        'jump(19)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(22)',
        'add',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10+13*37-1', () {
      expect(disasm(compileMain('10+13*37-1')), [
        'push_const(10)',
        'jump_null(15)',
        'push_const(13)',
        'jump_null(9)',
        'push_const(37)',
        'jump_null(8)',
        'mul',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(14)',
        'add',
        'jump(17)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(23)',
        'push_const(1)',
        'jump_null(22)',
        'sub',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10+13*37/2-1', () {
      expect(disasm(compileMain('10+13*37/2-1')), [
        'push_const(10)',
        'jump_null(23)',
        'push_const(13)',
        'jump_null(9)',
        'push_const(37)',
        'jump_null(8)',
        'mul',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(17)',
        'push_const(2)',
        'jump_null(16)',
        'div',
        'jump(19)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(22)',
        'add',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(31)',
        'push_const(1)',
        'jump_null(30)',
        'sub',
        'jump(33)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('9%2', () {
      expect(disasm(compileMain('9%2')), [
        'push_const(9)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mod',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('-5+11', () {
      expect(disasm(compileMain('-5+11')), [
        'push_const(5)',
        'jump_null(3)',
        'neg',
        'jump_null(9)',
        'push_const(11)',
        'jump_null(8)',
        'add',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('+5+11', () {
      expect(disasm(compileMain('+5+11')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(11)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('2^10', () {
      expect(disasm(compileMain('2^10')), [
        'push_const(2)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'pow',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('f:=x=>x^2;f(3)', () {
      expect(disasm(compileMain('f:=x=>x^2;f(3)')), [
        'make_closure(.__lambda_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(3)',
        'call(1)',
        'ret',
      ]);
    });

// ---- Constants ----
    test('PI*2', () {
      expect(disasm(compileMain('PI*2')), [
        'push_const(3.141592653589793)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('ANSWER', () {
      expect(disasm(compileMain('ANSWER')), [
        'push_const(42)',
        'ret',
      ]);
    });

    test('TRUE', () {
      expect(disasm(compileMain('TRUE')), [
        'push_const(true)',
        'ret',
      ]);
    });

    test('FALSE', () {
      expect(disasm(compileMain('FALSE')), [
        'push_const(false)',
        'ret',
      ]);
    });

// ---- Comparison ----
    test('5*2 = 2+8', () {
      expect(disasm(compileMain('5*2 = 2+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_eq',
        'ret',
      ]);
    });

    test('5*2 = 1+8', () {
      expect(disasm(compileMain('5*2 = 1+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(1)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_eq',
        'ret',
      ]);
    });

    test('5*2 <> 1+8', () {
      expect(disasm(compileMain('5*2 <> 1+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(1)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_neq',
        'ret',
      ]);
    });

    test('5*2 != 1+8', () {
      expect(disasm(compileMain('5*2 != 1+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(1)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_neq',
        'ret',
      ]);
    });

    test('5*2 <> 2+8', () {
      expect(disasm(compileMain('5*2 <> 2+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_neq',
        'ret',
      ]);
    });

    test('5*2 != 2+8', () {
      expect(disasm(compileMain('5*2 != 2+8')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(8)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'cmp_neq',
        'ret',
      ]);
    });

    test('1<10', () {
      expect(disasm(compileMain('1<10')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10<1', () {
      expect(disasm(compileMain('10<1')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('1<=10', () {
      expect(disasm(compileMain('1<=10')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_lte',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10<=1', () {
      expect(disasm(compileMain('10<=1')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_lte',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10>1', () {
      expect(disasm(compileMain('10>1')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('1>10', () {
      expect(disasm(compileMain('1>10')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('10>=1', () {
      expect(disasm(compileMain('10>=1')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_gte',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('1>=10', () {
      expect(disasm(compileMain('1>=10')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gte',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- Logic ----
    test('1<10 AND 2<9', () {
      expect(disasm(compileMain('1<10 AND 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(9)',
        'jump_null(15)',
        'cmp_lt',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    });

    test('1>10 AND 2<9', () {
      expect(disasm(compileMain('1>10 AND 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(9)',
        'jump_null(15)',
        'cmp_lt',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    });

    test('1<10 OCH 2<9', () {
      expect(disasm(compileMain('1<10 OCH 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(9)',
        'jump_null(15)',
        'cmp_lt',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    });

    test('1>10 OR 2<9', () {
      expect(disasm(compileMain('1>10 OR 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(9)',
        'jump_null(15)',
        'cmp_lt',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'log_or',
        'ret',
      ]);
    });

    test('1>10 ELLER 2<9', () {
      expect(disasm(compileMain('1>10 ELLER 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(2)',
        'jump_null(16)',
        'push_const(9)',
        'jump_null(15)',
        'cmp_lt',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'log_or',
        'ret',
      ]);
    });

    test('1>10 XOR 2<9', () {
      expect(disasm(compileMain('1>10 XOR 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'push_const(2)',
        'jump_null(18)',
        'push_const(9)',
        'jump_null(17)',
        'cmp_lt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
    });

    test('10>1 XOR 2<9', () {
      expect(disasm(compileMain('10>1 XOR 2<9')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'push_const(2)',
        'jump_null(18)',
        'push_const(9)',
        'jump_null(17)',
        'cmp_lt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
    });

    test('1>10 ANTINGEN_ELLER 2<9', () {
      expect(disasm(compileMain('1>10 ANTINGEN_ELLER 2<9')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_gt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'push_const(2)',
        'jump_null(18)',
        'push_const(9)',
        'jump_null(17)',
        'cmp_lt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
    });

    test('NOT 11', () {
      expect(disasm(compileMain('NOT 11')), [
        'push_const(11)',
        'jump_null(3)',
        'log_not',
        'ret',
      ]);
    });

    test('INTE 11', () {
      expect(disasm(compileMain('INTE 11')), [
        'push_const(11)',
        'jump_null(3)',
        'log_not',
        'ret',
      ]);
    });

    test('!11', () {
      expect(disasm(compileMain('!11')), [
        'push_const(11)',
        'jump_null(3)',
        'log_not',
        'ret',
      ]);
    });

// ---- Pattern / membership ----
    test('"Batman" ~ "batman"', () {
      expect(disasm(compileMain('"Batman" ~ "batman"')), [
        'push_const("Batman")',
        'jump_null(7)',
        'push_const("batman")',
        'jump_null(6)',
        'op_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Batman" ~ "bat.*"', () {
      expect(disasm(compileMain('"Batman" ~ "bat.*"')), [
        'push_const("Batman")',
        'jump_null(7)',
        'push_const("bat.*")',
        'jump_null(6)',
        'op_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Robin" ~ "bat.*"', () {
      expect(disasm(compileMain('"Robin" ~ "bat.*"')), [
        'push_const("Robin")',
        'jump_null(7)',
        'push_const("bat.*")',
        'jump_null(6)',
        'op_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Super Man" ~ r"Super\\s*Man"', () {
      expect(disasm(compileMain('"Super Man" ~ r"Super\s*Man"')), [
        'push_const("Super Man")',
        'jump_null(7)',
        'push_const("Super\s*Man")',
        'jump_null(6)',
        'op_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Robin" !~ "bat.*"', () {
      expect(disasm(compileMain('"Robin" !~ "bat.*"')), [
        'push_const("Robin")',
        'jump_null(7)',
        'push_const("bat.*")',
        'jump_null(6)',
        'op_not_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Batman" !~ "bat.*"', () {
      expect(disasm(compileMain('"Batman" !~ "bat.*"')), [
        'push_const("Batman")',
        'jump_null(7)',
        'push_const("bat.*")',
        'jump_null(6)',
        'op_not_match',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Batman" in ["Batman","Robin"]', () {
      expect(disasm(compileMain('"Batman" in ["Batman","Robin"]')), [
        'push_const("Batman")',
        'jump_null(9)',
        'push_const("Batman")',
        'push_const("Robin")',
        'make_list(2)',
        'jump_null(8)',
        'op_in',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Superman" in ["Batman","Robin"]', () {
      expect(disasm(compileMain('"Superman" in ["Batman","Robin"]')), [
        'push_const("Superman")',
        'jump_null(9)',
        'push_const("Batman")',
        'push_const("Robin")',
        'make_list(2)',
        'jump_null(8)',
        'op_in',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Batman" finns_i ["Batman","Robin"]', () {
      expect(disasm(compileMain('"Batman" finns_i ["Batman","Robin"]')), [
        'push_const("Batman")',
        'jump_null(9)',
        'push_const("Batman")',
        'push_const("Robin")',
        'make_list(2)',
        'jump_null(8)',
        'op_in',
        'jump(11)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"Bat" in "Batman"', () {
      expect(disasm(compileMain('"Bat" in "Batman"')), [
        'push_const("Bat")',
        'jump_null(7)',
        'push_const("Batman")',
        'jump_null(6)',
        'op_in',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('"bat" in "Batman"', () {
      expect(disasm(compileMain('"bat" in "Batman"')), [
        'push_const("bat")',
        'jump_null(7)',
        'push_const("Batman")',
        'jump_null(6)',
        'op_in',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- Variables ----
    test('i:=42', () {
      expect(disasm(compileMain('i:=42')), [
        'push_const(42)',
        'store_var(I)',
        'load_var(I)',
        'ret',
      ]);
    });

    test('i:=41;i:=i+1', () {
      expect(disasm(compileMain('i:=41;i:=i+1')), [
        'push_const(41)',
        'store_var(I)',
        'load_var(I)',
        'pop',
        'load_var(I)',
        'jump_null(11)',
        'push_const(1)',
        'jump_null(10)',
        'add',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(I)',
        'load_var(I)',
        'ret',
      ]);
    });

    test('10;11', () {
      expect(disasm(compileMain('10;11')), [
        'push_const(10)',
        'pop',
        'push_const(11)',
        'ret',
      ]);
    });

    test('10;11;', () {
      expect(disasm(compileMain('10;11;')), [
        'push_const(10)',
        'pop',
        'push_const(11)',
        'ret',
      ]);
    });

    test('my_global := 42; GET_GLOBAL() := my_global; GET_GLOBAL()', () {
      expect(disasm(compileMain('my_global := 42; GET_GLOBAL() := my_global; GET_GLOBAL()')), [
        'push_const(42)',
        'store_var(MY_GLOBAL)',
        'load_var(MY_GLOBAL)',
        'pop',
        'make_closure(.__GET_GLOBAL_0)',
        'store_var(GET_GLOBAL)',
        'load_var(GET_GLOBAL)',
        'pop',
        'load_var(GET_GLOBAL)',
        'call(0)',
        'ret',
      ]);
    });

    test('my_global := 10; ADD(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD(5)', () {
      expect(disasm(compileMain('my_global := 10; ADD(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD(5)')), [
        'push_const(10)',
        'store_var(MY_GLOBAL)',
        'load_var(MY_GLOBAL)',
        'pop',
        'make_closure(.__ADD_0)',
        'store_var(ADD)',
        'load_var(ADD)',
        'pop',
        'load_var(ADD)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

// ---- Native functions ----
    test('SQRT(4)', () {
      expect(disasm(compileMain('SQRT(4)')), [
        'load_var(SQRT)',
        'push_const(4)',
        'call(1)',
        'ret',
      ]);
    });

    test('POW(2,2)', () {
      expect(disasm(compileMain('POW(2,2)')), [
        'load_var(POW)',
        'push_const(2)',
        'push_const(2)',
        'call(2)',
        'ret',
      ]);
    });

    test('POW(2,2)+SQRT(4)', () {
      expect(disasm(compileMain('POW(2,2)+SQRT(4)')), [
        'load_var(POW)',
        'push_const(2)',
        'push_const(2)',
        'call(2)',
        'jump_null(12)',
        'load_var(SQRT)',
        'push_const(4)',
        'call(1)',
        'jump_null(11)',
        'add',
        'jump(14)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('SQRT(POW(2,2))', () {
      expect(disasm(compileMain('SQRT(POW(2,2))')), [
        'load_var(SQRT)',
        'load_var(POW)',
        'push_const(2)',
        'push_const(2)',
        'call(2)',
        'call(1)',
        'ret',
      ]);
    });

    test('SQRT(POW(2,2)+10)', () {
      expect(disasm(compileMain('SQRT(POW(2,2)+10)')), [
        'load_var(SQRT)',
        'load_var(POW)',
        'push_const(2)',
        'push_const(2)',
        'call(2)',
        'jump_null(11)',
        'push_const(10)',
        'jump_null(10)',
        'add',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'call(1)',
        'ret',
      ]);
    });

    test('LOWERCASE("Hello")', () {
      expect(disasm(compileMain('LOWERCASE("Hello")')), [
        'load_var(LOWERCASE)',
        'push_const("Hello")',
        'call(1)',
        'ret',
      ]);
    });

    test('UPPERCASE("hello")', () {
      expect(disasm(compileMain('UPPERCASE("hello")')), [
        'load_var(UPPERCASE)',
        'push_const("hello")',
        'call(1)',
        'ret',
      ]);
    });

    test('TRIM("  hello  ")', () {
      expect(disasm(compileMain('TRIM("  hello  ")')), [
        'load_var(TRIM)',
        'push_const("  hello  ")',
        'call(1)',
        'ret',
      ]);
    });

    test('STRING(42)', () {
      expect(disasm(compileMain('STRING(42)')), [
        'load_var(STRING)',
        'push_const(42)',
        'call(1)',
        'ret',
      ]);
    });

    test('INT(3.9)', () {
      expect(disasm(compileMain('INT(3.9)')), [
        'load_var(INT)',
        'push_const(3.9)',
        'call(1)',
        'ret',
      ]);
    });

    test('ROUND(3.6)', () {
      expect(disasm(compileMain('ROUND(3.6)')), [
        'load_var(ROUND)',
        'push_const(3.6)',
        'call(1)',
        'ret',
      ]);
    });

    test('MIN(3, 7)', () {
      expect(disasm(compileMain('MIN(3, 7)')), [
        'load_var(MIN)',
        'push_const(3)',
        'push_const(7)',
        'call(2)',
        'ret',
      ]);
    });

    test('MAX(3, 7)', () {
      expect(disasm(compileMain('MAX(3, 7)')), [
        'load_var(MAX)',
        'push_const(3)',
        'push_const(7)',
        'call(2)',
        'ret',
      ]);
    });

    test('SUBSTRING("hello world", 0, 5)', () {
      expect(disasm(compileMain('SUBSTRING("hello world", 0, 5)')), [
        'load_var(SUBSTRING)',
        'push_const("hello world")',
        'push_const(0)',
        'push_const(5)',
        'call(3)',
        'ret',
      ]);
    });

    test('LENGTH("hello")', () {
      expect(disasm(compileMain('LENGTH("hello")')), [
        'load_var(LENGTH)',
        'push_const("hello")',
        'call(1)',
        'ret',
      ]);
    });

    test('LENGTH([1,2,3])', () {
      expect(disasm(compileMain('LENGTH([1,2,3])')), [
        'load_var(LENGTH)',
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'call(1)',
        'ret',
      ]);
    });

    test('LENGTH([])', () {
      expect(disasm(compileMain('LENGTH([])')), [
        'load_var(LENGTH)',
        'make_list(0)',
        'call(1)',
        'ret',
      ]);
    });

    test('LOWERCASE("Robin") in ["batman","robin"]', () {
      expect(disasm(compileMain('LOWERCASE("Robin") in ["batman","robin"]')), [
        'load_var(LOWERCASE)',
        'push_const("Robin")',
        'call(1)',
        'jump_null(11)',
        'push_const("batman")',
        'push_const("robin")',
        'make_list(2)',
        'jump_null(10)',
        'op_in',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); GET_LENGTH()', () {
      expect(disasm(compileMain('my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); GET_LENGTH()')), [
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'store_var(MY_ARRAY)',
        'load_var(MY_ARRAY)',
        'pop',
        'make_closure(.__GET_LENGTH_0)',
        'store_var(GET_LENGTH)',
        'load_var(GET_LENGTH)',
        'pop',
        'load_var(GET_LENGTH)',
        'call(0)',
        'ret',
      ]);
    });

    test('my_array := [1, 2, 3]; PUSH(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH(4)', () {
      expect(disasm(compileMain('my_array := [1, 2, 3]; PUSH(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH(4)')), [
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'store_var(MY_ARRAY)',
        'load_var(MY_ARRAY)',
        'pop',
        'make_closure(.__PUSH_0)',
        'store_var(PUSH)',
        'load_var(PUSH)',
        'pop',
        'load_var(PUSH)',
        'push_const(4)',
        'call(1)',
        'ret',
      ]);
    });

// ---- User functions ----
    test('f(x):=x*2;f(2)', () {
      expect(disasm(compileMain('f(x):=x*2;f(2)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(2)',
        'call(1)',
        'ret',
      ]);
    });

    test('f(a,b):=a-b;f(10,2)', () {
      expect(disasm(compileMain('f(a,b):=a-b;f(10,2)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(10)',
        'push_const(2)',
        'call(2)',
        'ret',
      ]);
    });

    test('fac(x):=IF x<=1 THEN 1 ELSE x*fac(x-1);fac(3)', () {
      expect(disasm(compileMain('fac(x):=IF x<=1 THEN 1 ELSE x*fac(x-1);fac(3)')), [
        'make_closure(.__FAC_0)',
        'store_var(FAC)',
        'load_var(FAC)',
        'pop',
        'load_var(FAC)',
        'push_const(3)',
        'call(1)',
        'ret',
      ]);
    });

    test('sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,1,2,3)', () {
      expect(disasm(compileMain('sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,1,2,3)')), [
        'make_closure(.__SUM_0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'make_closure(.__F1_1)',
        'store_var(F1)',
        'load_var(F1)',
        'pop',
        'load_var(F1)',
        'load_var(SUM)',
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'call(4)',
        'ret',
      ]);
    });

    test('sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,10,20,5)', () {
      expect(disasm(compileMain('sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,10,20,5)')), [
        'make_closure(.__SUM_0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'make_closure(.__F1_1)',
        'store_var(F1)',
        'load_var(F1)',
        'pop',
        'load_var(F1)',
        'load_var(SUM)',
        'push_const(10)',
        'push_const(20)',
        'push_const(5)',
        'call(4)',
        'ret',
      ]);
    });

    test('test():=TRUE;test()', () {
      expect(disasm(compileMain('test():=TRUE;test()')), [
        'make_closure(.__TEST_0)',
        'store_var(TEST)',
        'load_var(TEST)',
        'pop',
        'load_var(TEST)',
        'call(0)',
        'ret',
      ]);
    });

// ---- Lambda expressions ----
    test('f:=x=>x^2;f(3)', () {
      expect(disasm(compileMain('f:=x=>x^2;f(3)')), [
        'make_closure(.__lambda_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(3)',
        'call(1)',
        'ret',
      ]);
    });

    test('(x=>x^2)(3)', () {
      expect(disasm(compileMain('(x=>x^2)(3)')), [
        'make_closure(.__lambda_0)',
        'push_const(3)',
        'call(1)',
        'ret',
      ]);
    });

    test('(()=>9)()', () {
      expect(disasm(compileMain('(()=>9)()')), [
        'make_closure(.__lambda_0)',
        'call(0)',
        'ret',
      ]);
    });

// ---- Return statement ----
    test('f(x):=IF x%2=0 THEN RETURN x+1 ELSE RETURN x;f(2)', () {
      expect(disasm(compileMain('f(x):=IF x%2=0 THEN RETURN x+1 ELSE RETURN x;f(2)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(2)',
        'call(1)',
        'ret',
      ]);
    });

    test('f(x):=BEGIN IF x%2=0 THEN RETURN x+1; RETURN x; END;f(2)', () {
      expect(disasm(compileMain('f(x):=BEGIN IF x%2=0 THEN RETURN x+1; RETURN x; END;f(2)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(2)',
        'call(1)',
        'ret',
      ]);
    });

    test('f(x):=BEGIN IF x<=1 THEN RETURN 1; RETURN x*f(x-1); END;f(5)', () {
      expect(disasm(compileMain('f(x):=BEGIN IF x<=1 THEN RETURN 1; RETURN x*f(x-1); END;f(5)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

// ---- IF statement ----
    test('IF 1<10 THEN 42 ELSE 0', () {
      expect(disasm(compileMain('IF 1<10 THEN 42 ELSE 0')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(10)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(12)',
        'push_const(42)',
        'jump(13)',
        'push_const(0)',
        'ret',
      ]);
    });

    test('IF 10<1 THEN 42 ELSE 0', () {
      expect(disasm(compileMain('IF 10<1 THEN 42 ELSE 0')), [
        'push_const(10)',
        'jump_null(7)',
        'push_const(1)',
        'jump_null(6)',
        'cmp_lt',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(12)',
        'push_const(42)',
        'jump(13)',
        'push_const(0)',
        'ret',
      ]);
    });

    test('IF TRUE THEN 42', () {
      expect(disasm(compileMain('IF TRUE THEN 42')), [
        'push_const(true)',
        'jump_false(4)',
        'push_const(42)',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
    });

    test('IF FALSE THEN 42', () {
      expect(disasm(compileMain('IF FALSE THEN 42')), [
        'push_const(false)',
        'jump_false(4)',
        'push_const(42)',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
    });

    test('IF 1=1 AND (2=2) THEN "yes" ELSE "no"', () {
      expect(disasm(compileMain('IF 1=1 AND (2=2) THEN "yes" ELSE "no"')), [
        'push_const(1)',
        'push_const(1)',
        'cmp_eq',
        'push_const(2)',
        'push_const(2)',
        'cmp_eq',
        'log_and',
        'jump_false(10)',
        'push_const("yes")',
        'jump(11)',
        'push_const("no")',
        'ret',
      ]);
    });

    test('(5)-3', () {
      expect(disasm(compileMain('(5)-3')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(3)',
        'jump_null(6)',
        'sub',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('(5)+3', () {
      expect(disasm(compileMain('(5)+3')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(3)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- WHILE loop ----
    test('x:=0; WHILE x<10 DO x:=x+1; x', () {
      expect(disasm(compileMain('x:=0; WHILE x<10 DO x:=x+1; x')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(13)',
        'push_const(10)',
        'jump_null(12)',
        'cmp_lt',
        'jump(15)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(29)',
        'load_var(X)',
        'jump_null(23)',
        'push_const(1)',
        'jump_null(22)',
        'add',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'store_reg(0)',
        'jump(6)',
        'load_reg(0)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

    test('x:=0; WHILE TRUE DO BEGIN x:=x+1; IF x=10 THEN BREAK; END; x', () {
      expect(disasm(compileMain('x:=0; WHILE TRUE DO BEGIN x:=x+1; IF x=10 THEN BREAK; END; x')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'push_const(true)',
        'jump_false(31)',
        'push_scope',
        'load_var(X)',
        'jump_null(16)',
        'push_const(1)',
        'jump_null(15)',
        'add',
        'jump(18)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(10)',
        'cmp_eq',
        'jump_false(27)',
        'jump(31)',
        'jump(28)',
        'push_const(null)',
        'pop_scope',
        'store_reg(0)',
        'jump(6)',
        'load_reg(0)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

    test('x:=0; y:=0; WHILE x<10 DO BEGIN x:=x+1; IF x%2=0 THEN CONTINUE; y:=y+1; END; y', () {
      expect(disasm(compileMain('x:=0; y:=0; WHILE x<10 DO BEGIN x:=x+1; IF x%2=0 THEN CONTINUE; y:=y+1; END; y')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(0)',
        'store_var(Y)',
        'load_var(Y)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(17)',
        'push_const(10)',
        'jump_null(16)',
        'cmp_lt',
        'jump(19)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(63)',
        'push_scope',
        'load_var(X)',
        'jump_null(28)',
        'push_const(1)',
        'jump_null(27)',
        'add',
        'jump(30)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(40)',
        'push_const(2)',
        'jump_null(39)',
        'mod',
        'jump(42)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(0)',
        'cmp_eq',
        'jump_false(47)',
        'jump(10)',
        'jump(48)',
        'push_const(null)',
        'pop',
        'load_var(Y)',
        'jump_null(56)',
        'push_const(1)',
        'jump_null(55)',
        'add',
        'jump(58)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(Y)',
        'load_var(Y)',
        'pop_scope',
        'store_reg(0)',
        'jump(10)',
        'load_reg(0)',
        'pop',
        'load_var(Y)',
        'ret',
      ]);
    });

    test('WHILE FALSE DO TRUE', () {
      expect(disasm(compileMain('WHILE FALSE DO TRUE')), [
        'push_const(null)',
        'store_reg(0)',
        'push_const(false)',
        'jump_false(7)',
        'push_const(true)',
        'store_reg(0)',
        'jump(2)',
        'load_reg(0)',
        'ret',
      ]);
    });

    test('x := 0; WHILE x < 3 DO BEGIN x := x + 1; x^2 END', () {
      expect(disasm(compileMain('x := 0; WHILE x < 3 DO BEGIN x := x + 1; x^2 END')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(13)',
        'push_const(3)',
        'jump_null(12)',
        'cmp_lt',
        'jump(15)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(41)',
        'push_scope',
        'load_var(X)',
        'jump_null(24)',
        'push_const(1)',
        'jump_null(23)',
        'add',
        'jump(26)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(36)',
        'push_const(2)',
        'jump_null(35)',
        'pow',
        'jump(38)',
        'pop',
        'pop',
        'push_const(null)',
        'pop_scope',
        'store_reg(0)',
        'jump(6)',
        'load_reg(0)',
        'ret',
      ]);
    });

// ---- FOR loop ----
    test('sum:=0; FOR i:=1 TO 10 DO sum:=sum+i; sum', () {
      expect(disasm(compileMain('sum:=0; FOR i:=1 TO 10 DO sum:=sum+i; sum')), [
        'push_const(0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'push_const(1)',
        'store_var(I)',
        'load_var(I)',
        'pop',
        'load_var(I)',
        'store_reg(0)',
        'push_const(false)',
        'store_reg(1)',
        'load_var(SUM)',
        'jump_null(19)',
        'load_var(I)',
        'jump_null(18)',
        'add',
        'jump(21)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'load_reg(1)',
        'jump_true(66)',
        'push_const(10)',
        'store_reg(2)',
        'load_reg(2)',
        'load_reg(0)',
        'cmp_gte',
        'store_reg(3)',
        'load_reg(3)',
        'jump_false(36)',
        'push_const(1)',
        'jump(37)',
        'push_const(-1)',
        'store_reg(4)',
        'load_var(I)',
        'load_reg(4)',
        'add',
        'store_reg(5)',
        'load_reg(3)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_gt',
        'log_and',
        'load_reg(3)',
        'log_not',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_lt',
        'log_and',
        'log_or',
        'store_reg(6)',
        'load_reg(6)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_eq',
        'log_or',
        'store_reg(1)',
        'load_reg(6)',
        'jump_true(66)',
        'load_reg(5)',
        'store_var(I)',
        'jump(12)',
        'push_const(null)',
        'pop',
        'load_var(SUM)',
        'ret',
      ]);
    });

    test('sum:=0; FOR i:=1 TO 10 STEP 2 DO sum:=sum+i; sum', () {
      expect(disasm(compileMain('sum:=0; FOR i:=1 TO 10 STEP 2 DO sum:=sum+i; sum')), [
        'push_const(0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'push_const(1)',
        'store_var(I)',
        'load_var(I)',
        'pop',
        'load_var(I)',
        'store_reg(0)',
        'push_const(false)',
        'store_reg(1)',
        'load_var(SUM)',
        'jump_null(19)',
        'load_var(I)',
        'jump_null(18)',
        'add',
        'jump(21)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'load_reg(1)',
        'jump_true(62)',
        'push_const(10)',
        'store_reg(2)',
        'load_reg(2)',
        'load_reg(0)',
        'cmp_gte',
        'store_reg(3)',
        'push_const(2)',
        'store_reg(4)',
        'load_var(I)',
        'load_reg(4)',
        'add',
        'store_reg(5)',
        'load_reg(3)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_gt',
        'log_and',
        'load_reg(3)',
        'log_not',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_lt',
        'log_and',
        'log_or',
        'store_reg(6)',
        'load_reg(6)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_eq',
        'log_or',
        'store_reg(1)',
        'load_reg(6)',
        'jump_true(62)',
        'load_reg(5)',
        'store_var(I)',
        'jump(12)',
        'push_const(null)',
        'pop',
        'load_var(SUM)',
        'ret',
      ]);
    });

    test('sum:=0; FOR i:=10 TO 1 STEP -1 DO sum:=sum+i; sum', () {
      expect(disasm(compileMain('sum:=0; FOR i:=10 TO 1 STEP -1 DO sum:=sum+i; sum')), [
        'push_const(0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'push_const(10)',
        'store_var(I)',
        'load_var(I)',
        'pop',
        'load_var(I)',
        'store_reg(0)',
        'push_const(false)',
        'store_reg(1)',
        'load_var(SUM)',
        'jump_null(19)',
        'load_var(I)',
        'jump_null(18)',
        'add',
        'jump(21)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'load_reg(1)',
        'jump_true(64)',
        'push_const(1)',
        'store_reg(2)',
        'load_reg(2)',
        'load_reg(0)',
        'cmp_gte',
        'store_reg(3)',
        'push_const(1)',
        'jump_null(35)',
        'neg',
        'store_reg(4)',
        'load_var(I)',
        'load_reg(4)',
        'add',
        'store_reg(5)',
        'load_reg(3)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_gt',
        'log_and',
        'load_reg(3)',
        'log_not',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_lt',
        'log_and',
        'log_or',
        'store_reg(6)',
        'load_reg(6)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_eq',
        'log_or',
        'store_reg(1)',
        'load_reg(6)',
        'jump_true(64)',
        'load_reg(5)',
        'store_var(I)',
        'jump(12)',
        'push_const(null)',
        'pop',
        'load_var(SUM)',
        'ret',
      ]);
    });

    test('sum:=0; FOR i:=0 TO 0 DO sum:=sum+1; sum', () {
      expect(disasm(compileMain('sum:=0; FOR i:=0 TO 0 DO sum:=sum+1; sum')), [
        'push_const(0)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'push_const(0)',
        'store_var(I)',
        'load_var(I)',
        'pop',
        'load_var(I)',
        'store_reg(0)',
        'push_const(false)',
        'store_reg(1)',
        'load_var(SUM)',
        'jump_null(19)',
        'push_const(1)',
        'jump_null(18)',
        'add',
        'jump(21)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(SUM)',
        'load_var(SUM)',
        'pop',
        'load_reg(1)',
        'jump_true(66)',
        'push_const(0)',
        'store_reg(2)',
        'load_reg(2)',
        'load_reg(0)',
        'cmp_gte',
        'store_reg(3)',
        'load_reg(3)',
        'jump_false(36)',
        'push_const(1)',
        'jump(37)',
        'push_const(-1)',
        'store_reg(4)',
        'load_var(I)',
        'load_reg(4)',
        'add',
        'store_reg(5)',
        'load_reg(3)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_gt',
        'log_and',
        'load_reg(3)',
        'log_not',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_lt',
        'log_and',
        'log_or',
        'store_reg(6)',
        'load_reg(6)',
        'load_reg(5)',
        'load_reg(2)',
        'cmp_eq',
        'log_or',
        'store_reg(1)',
        'load_reg(6)',
        'jump_true(66)',
        'load_reg(5)',
        'store_var(I)',
        'jump(12)',
        'push_const(null)',
        'pop',
        'load_var(SUM)',
        'ret',
      ]);
    });

    test('FOR CONTINUE with IF', () {
      expect(disasm(compileMain(r'''
__test():=BEGIN
  __result:=[];
  FOR __i:=0 TO 2 DO BEGIN
    IF __i=1 THEN CONTINUE;
    __result:=__result+[__i];
  END;
  RETURN __result;
END;
__test()

''')), [
        'make_closure(.____TEST_0)',
        'store_var(__TEST)',
        'load_var(__TEST)',
        'pop',
        'load_var(__TEST)',
        'call(0)',
        'ret',
      ]);
    });

    test('FOR CONTINUE with nested IF-ELSE IF', () {
      expect(disasm(compileMain(r'''
__test():=BEGIN
  __result:=[];
  FOR __i:=0 TO 2 DO BEGIN
    IF __i=0 THEN __result:=__result+['zero']
    ELSE IF __i=1 THEN BEGIN
      __result:=__result+['skip'];
      CONTINUE;
    END
    ELSE __result:=__result+['two'];
    __result:=__result+['after'];
  END;
  RETURN __result;
END;
__test()

''')), [
        'make_closure(.____TEST_0)',
        'store_var(__TEST)',
        'load_var(__TEST)',
        'pop',
        'load_var(__TEST)',
        'call(0)',
        'ret',
      ]);
    });

    test('FOR CONTINUE inside nested IF-THEN-BEGIN-END', () {
      expect(disasm(compileMain(r'''
__test():=BEGIN
  __result:=[];
  __flag:=TRUE;
  FOR __i:=0 TO 2 DO BEGIN
    IF __flag THEN BEGIN
      IF __i=1 THEN BEGIN
        __result:=__result+['skip'];
        CONTINUE;
      END;
    END;
    __result:=__result+[__i];
  END;
  RETURN __result;
END;
__test()

''')), [
        'make_closure(.____TEST_0)',
        'store_var(__TEST)',
        'load_var(__TEST)',
        'pop',
        'load_var(__TEST)',
        'call(0)',
        'ret',
      ]);
    });

    test('FOR CONTINUE with ELSE IF BREAK pattern', () {
      expect(disasm(compileMain(r'''
__test():=BEGIN
  __result:=[];
  __flag:=TRUE;
  __action:='skip';
  FOR __i:=0 TO 2 DO BEGIN
    IF __flag THEN BEGIN
      IF __action='saveAll' THEN __result:=__result+['saveAll']
      ELSE IF __action='cancel' THEN BEGIN
        __result:=__result+['cancel'];
        BREAK;
      END
      ELSE IF __action<>'save' THEN BEGIN
        __result:=__result+['skipped'];
        CONTINUE;
      END;
    END;
    __result:=__result+['after:'+STRING(__i)];
  END;
  RETURN __result;
END;
__test()

''')), [
        'make_closure(.____TEST_0)',
        'store_var(__TEST)',
        'load_var(__TEST)',
        'pop',
        'load_var(__TEST)',
        'call(0)',
        'ret',
      ]);
    });

// ---- REPEAT/UNTIL ----
    test('x:=0; REPEAT x:=x+1 UNTIL x=10; x', () {
      expect(disasm(compileMain('x:=0; REPEAT x:=x+1 UNTIL x=10; x')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(13)',
        'push_const(1)',
        'jump_null(12)',
        'add',
        'jump(15)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'store_reg(0)',
        'load_var(X)',
        'push_const(10)',
        'cmp_eq',
        'jump_false(6)',
        'load_reg(0)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

    test('x := 0; REPEAT BEGIN x := x + 1; x^2 END UNTIL x >= 3', () {
      expect(disasm(compileMain('x := 0; REPEAT BEGIN x := x + 1; x^2 END UNTIL x >= 3')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'push_scope',
        'load_var(X)',
        'jump_null(14)',
        'push_const(1)',
        'jump_null(13)',
        'add',
        'jump(16)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(26)',
        'push_const(2)',
        'jump_null(25)',
        'pow',
        'jump(28)',
        'pop',
        'pop',
        'push_const(null)',
        'pop_scope',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(37)',
        'push_const(3)',
        'jump_null(36)',
        'cmp_gte',
        'jump(39)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(6)',
        'load_reg(0)',
        'ret',
      ]);
    });

// ---- Lists ----
    test('[1,2,3]', () {
      expect(disasm(compileMain('[1,2,3]')), [
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'ret',
      ]);
    });

    test('[]', () {
      expect(disasm(compileMain('[]')), [
        'make_list(0)',
        'ret',
      ]);
    });

    test('[1,2]+[3,4]', () {
      expect(disasm(compileMain('[1,2]+[3,4]')), [
        'push_const(1)',
        'push_const(2)',
        'make_list(2)',
        'jump_null(11)',
        'push_const(3)',
        'push_const(4)',
        'make_list(2)',
        'jump_null(10)',
        'add',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('x:=[10,20,30]; x[1]', () {
      expect(disasm(compileMain('x:=[10,20,30]; x[1]')), [
        'push_const(10)',
        'push_const(20)',
        'push_const(30)',
        'make_list(3)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(1)',
        'get_index',
        'ret',
      ]);
    });

    test('x:=[10,20,30]; x[1]:=99; x[1]', () {
      expect(disasm(compileMain('x:=[10,20,30]; x[1]:=99; x[1]')), [
        'push_const(10)',
        'push_const(20)',
        'push_const(30)',
        'make_list(3)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(1)',
        'push_const(99)',
        'set_index',
        'pop',
        'load_var(X)',
        'push_const(1)',
        'get_index',
        'ret',
      ]);
    });

// ---- Maps ----
    test('{\'a\':1,\'b\':2}', () {
      expect(disasm(compileMain("{'a':1,'b':2}")), [
        'push_const("a")',
        'push_const(1)',
        'push_const("b")',
        'push_const(2)',
        'make_map(2)',
        'ret',
      ]);
    });

    test('x:={\'a\':1,\'b\':2}; x[\'a\']', () {
      expect(disasm(compileMain("x:={'a':1,'b':2}; x['a']")), [
        'push_const("a")',
        'push_const(1)',
        'push_const("b")',
        'push_const(2)',
        'make_map(2)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const("a")',
        'get_index',
        'ret',
      ]);
    });

    test('x:={\'a\':1,\'b\':2}; x[\'b\']:=99; x[\'b\']', () {
      expect(disasm(compileMain("x:={'a':1,'b':2}; x['b']:=99; x['b']")), [
        'push_const("a")',
        'push_const(1)',
        'push_const("b")',
        'push_const(2)',
        'make_map(2)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const("b")',
        'push_const(99)',
        'set_index',
        'pop',
        'load_var(X)',
        'push_const("b")',
        'get_index',
        'ret',
      ]);
    });

    test('k:=\'name\'; {k:\'Alice\'}', () {
      expect(disasm(compileMain("k:='name'; {k:'Alice'}")), [
        'push_const("name")',
        'store_var(K)',
        'load_var(K)',
        'pop',
        'push_const("K")',
        'push_const("Alice")',
        'make_map(1)',
        'ret',
      ]);
    });

    test('{\'a\':1,\'b\':2}[\'a\']', () {
      expect(disasm(compileMain("{'a':1,'b':2}['a']")), [
        'push_const("a")',
        'push_const(1)',
        'push_const("b")',
        'push_const(2)',
        'make_map(2)',
        'push_const("a")',
        'get_index',
        'ret',
      ]);
    });

    test('k:=\'name\'; {k:\'Alice\'}[\'name\']', () {
      expect(disasm(compileMain("k:='name'; {k:'Alice'}['name']")), [
        'push_const("name")',
        'store_var(K)',
        'load_var(K)',
        'pop',
        'push_const("K")',
        'push_const("Alice")',
        'make_map(1)',
        'push_const("name")',
        'get_index',
        'ret',
      ]);
    });

    test('x:={\'a\':1,\'b\':2}; x[\'b\']:=99; x[\'b\']', () {
      expect(disasm(compileMain("x:={'a':1,'b':2}; x['b']:=99; x['b']")), [
        'push_const("a")',
        'push_const(1)',
        'push_const("b")',
        'push_const(2)',
        'make_map(2)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const("b")',
        'push_const(99)',
        'set_index',
        'pop',
        'load_var(X)',
        'push_const("b")',
        'get_index',
        'ret',
      ]);
    });

// ---- SHQL Objects ----
    test('OBJECT{name:"Alice",age:30}', () {
      expect(disasm(compileMain('OBJECT{name:"Alice",age:30}')), [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'push_const("AGE")',
        'push_const(30)',
        'make_object_here(2)',
        'pop_scope',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,y:20}; obj.x', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,y:20}; obj.x')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("Y")',
        'push_const(20)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(X)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,y:20}; obj.x:=100; obj.x', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,y:20}; obj.x:=100; obj.x')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("Y")',
        'push_const(20)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'push_const(100)',
        'set_member(X)',
        'pop',
        'load_var(OBJ)',
        'get_member(X)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{person:OBJECT{name:"Bob",age:25}}; obj.person.name', () {
      expect(disasm(compileMain('obj:=OBJECT{person:OBJECT{name:"Bob",age:25}}; obj.person.name')), [
        'push_scope',
        'push_const("PERSON")',
        'push_scope',
        'push_const("NAME")',
        'push_const("Bob")',
        'push_const("AGE")',
        'push_const(25)',
        'make_object_here(2)',
        'pop_scope',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(PERSON)',
        'get_member(NAME)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{inner:OBJECT{value:5}}; obj.inner.value:=42; obj.inner.value', () {
      expect(disasm(compileMain('obj:=OBJECT{inner:OBJECT{value:5}}; obj.inner.value:=42; obj.inner.value')), [
        'push_scope',
        'push_const("INNER")',
        'push_scope',
        'push_const("VALUE")',
        'push_const(5)',
        'make_object_here(1)',
        'pop_scope',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INNER)',
        'push_const(42)',
        'set_member(VALUE)',
        'pop',
        'load_var(OBJ)',
        'get_member(INNER)',
        'get_member(VALUE)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{counter:0}; obj.counter:=obj.counter+1; obj.counter', () {
      expect(disasm(compileMain('obj:=OBJECT{counter:0}; obj.counter:=obj.counter+1; obj.counter')), [
        'push_scope',
        'push_const("COUNTER")',
        'push_const(0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'load_var(OBJ)',
        'get_member(COUNTER)',
        'jump_null(17)',
        'push_const(1)',
        'jump_null(16)',
        'add',
        'jump(19)',
        'pop',
        'pop',
        'push_const(null)',
        'set_member(COUNTER)',
        'pop',
        'load_var(OBJ)',
        'get_member(COUNTER)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{list:[1,2,3],sum:1+2}; obj.sum', () {
      expect(disasm(compileMain('obj:=OBJECT{list:[1,2,3],sum:1+2}; obj.sum')), [
        'push_scope',
        'push_const("LIST")',
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'push_const("SUM")',
        'push_const(1)',
        'jump_null(14)',
        'push_const(2)',
        'jump_null(13)',
        'add',
        'jump(16)',
        'pop',
        'pop',
        'push_const(null)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(SUM)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{title:null}; obj.title', () {
      expect(disasm(compileMain('obj:=OBJECT{title:null}; obj.title')), [
        'push_scope',
        'push_const("TITLE")',
        'push_const(null)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(TITLE)',
        'ret',
      ]);
    });

// ---- Object methods ----
    test('obj:=OBJECT{x:10,getX:()=>x}; obj.getX()', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,getX:()=>x}; obj.getX()')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("GETX")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETX)',
        'call(0)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,y:20,sum:()=>x+y}; obj.sum()', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,y:20,sum:()=>x+y}; obj.sum()')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("Y")',
        'push_const(20)',
        'push_const("SUM")',
        'make_closure(.__lambda_0)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(SUM)',
        'call(0)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.n', () {
      expect(disasm(compileMain('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.n')), [
        'push_scope',
        'push_const("N")',
        'push_const(0)',
        'push_const("INC")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INC)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(N)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.inc(); obj.inc(); obj.n', () {
      expect(disasm(compileMain('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.inc(); obj.inc(); obj.n')), [
        'push_scope',
        'push_const("N")',
        'push_const(0)',
        'push_const("INC")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INC)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INC)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INC)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(N)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,add:(delta)=>x+delta}; obj.add(5)', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,add:(delta)=>x+delta}; obj.add(5)')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("ADD")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ADD)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,setX:(newX)=>x:=newX}; obj.setX(42); obj.x', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,setX:(newX)=>x:=newX}; obj.setX(42); obj.x')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("SETX")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(SETX)',
        'push_const(42)',
        'call(1)',
        'pop',
        'load_var(OBJ)',
        'get_member(X)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{inner:OBJECT{value:5},getInnerValue:()=>inner.value}; obj.getInnerValue()', () {
      expect(disasm(compileMain('obj:=OBJECT{inner:OBJECT{value:5},getInnerValue:()=>inner.value}; obj.getInnerValue()')), [
        'push_scope',
        'push_const("INNER")',
        'push_scope',
        'push_const("VALUE")',
        'push_const(5)',
        'make_object_here(1)',
        'pop_scope',
        'push_const("GETINNERVALUE")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETINNERVALUE)',
        'call(0)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,useParam:(x)=>x}; obj.useParam(42)', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,useParam:(x)=>x}; obj.useParam(42)')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("USEPARAM")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(USEPARAM)',
        'push_const(42)',
        'call(1)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:10,getX:()=>x,doubleX:()=>getX()*2}; obj.doubleX()', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,getX:()=>x,doubleX:()=>getX()*2}; obj.doubleX()')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("GETX")',
        'make_closure(.__lambda_0)',
        'push_const("DOUBLEX")',
        'make_closure(.__lambda_1)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(DOUBLEX)',
        'call(0)',
        'ret',
      ]);
    });

// ---- THIS self-reference ----
    test('obj:=OBJECT{x:10,getThis:()=>THIS}; obj.getThis().x', () {
      expect(disasm(compileMain('obj:=OBJECT{x:10,getThis:()=>THIS}; obj.getThis().x')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("GETTHIS")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETTHIS)',
        'call(0)',
        'get_member(X)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{x:42,getX:()=>THIS.x}; obj.getX()', () {
      expect(disasm(compileMain('obj:=OBJECT{x:42,getX:()=>THIS.x}; obj.getX()')), [
        'push_scope',
        'push_const("X")',
        'push_const(42)',
        'push_const("GETX")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETX)',
        'call(0)',
        'ret',
      ]);
    });

// ---- Cross-object ----
    test('A:=OBJECT{x:10,count:0,SET_COUNT:(v)=>BEGIN count:=v; END}; B:=OBJECT{notify:()=>BEGIN A.SET_COUNT(A.x+5); END}; B.notify(); A.count', () {
      expect(disasm(compileMain('A:=OBJECT{x:10,count:0,SET_COUNT:(v)=>BEGIN count:=v; END}; B:=OBJECT{notify:()=>BEGIN A.SET_COUNT(A.x+5); END}; B.notify(); A.count')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("COUNT")',
        'push_const(0)',
        'push_const("SET_COUNT")',
        'make_closure(.__lambda_0)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(A)',
        'load_var(A)',
        'pop',
        'push_scope',
        'push_const("NOTIFY")',
        'make_closure(.__lambda_1)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(B)',
        'load_var(B)',
        'pop',
        'load_var(B)',
        'get_member(NOTIFY)',
        'call(0)',
        'pop',
        'load_var(A)',
        'get_member(COUNT)',
        'ret',
      ]);
    });

// ---- Null value handling ----
    test('x:=null; x', () {
      expect(disasm(compileMain('x:=null; x')), [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

    test('x:=null; y:=5; x=null', () {
      expect(disasm(compileMain('x:=null; y:=5; x=null')), [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(5)',
        'store_var(Y)',
        'load_var(Y)',
        'pop',
        'load_var(X)',
        'push_const(null)',
        'cmp_eq',
        'ret',
      ]);
    });

    test('f(x):=x; f(null)', () {
      expect(disasm(compileMain('f(x):=x; f(null)')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(null)',
        'call(1)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{title:null}; obj.title', () {
      expect(disasm(compileMain('obj:=OBJECT{title:null}; obj.title')), [
        'push_scope',
        'push_const("TITLE")',
        'push_const(null)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(TITLE)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{getNull:()=>null}; obj.getNull()', () {
      expect(disasm(compileMain('obj:=OBJECT{getNull:()=>null}; obj.getNull()')), [
        'push_scope',
        'push_const("GETNULL")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETNULL)',
        'call(0)',
        'ret',
      ]);
    });

    test('posts:=[{"title":null}]; title:=posts[0]["title"]; title', () {
      expect(disasm(compileMain('posts:=[{"title":null}]; title:=posts[0]["title"]; title')), [
        'push_const("title")',
        'push_const(null)',
        'make_map(1)',
        'make_list(1)',
        'store_var(POSTS)',
        'load_var(POSTS)',
        'pop',
        'load_var(POSTS)',
        'push_const(0)',
        'get_index',
        'push_const("title")',
        'get_index',
        'store_var(TITLE)',
        'load_var(TITLE)',
        'pop',
        'load_var(TITLE)',
        'ret',
      ]);
    });

    test('m:={"a":null}; m["a"]', () {
      expect(disasm(compileMain('m:={"a":null}; m["a"]')), [
        'push_const("a")',
        'push_const(null)',
        'make_map(1)',
        'store_var(M)',
        'load_var(M)',
        'pop',
        'load_var(M)',
        'push_const("a")',
        'get_index',
        'ret',
      ]);
    });

// ---- Null-aware arithmetic ----
    test('NULL+5', () {
      expect(disasm(compileMain('NULL+5')), [
        'push_const(null)',
        'jump_null(7)',
        'push_const(5)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('5+NULL', () {
      expect(disasm(compileMain('5+NULL')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(null)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('NULL-5', () {
      expect(disasm(compileMain('NULL-5')), [
        'push_const(null)',
        'jump_null(7)',
        'push_const(5)',
        'jump_null(6)',
        'sub',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('NULL*5', () {
      expect(disasm(compileMain('NULL*5')), [
        'push_const(null)',
        'jump_null(7)',
        'push_const(5)',
        'jump_null(6)',
        'mul',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('NULL/5', () {
      expect(disasm(compileMain('NULL/5')), [
        'push_const(null)',
        'jump_null(7)',
        'push_const(5)',
        'jump_null(6)',
        'div',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('NULL^2', () {
      expect(disasm(compileMain('NULL^2')), [
        'push_const(null)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'pow',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('NULL < 5', () {
      expect(disasm(compileMain('NULL < 5')), [
        'push_const(null)',
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

    test('NOT NULL', () {
      expect(disasm(compileMain('NOT NULL')), [
        'push_const(null)',
        'jump_null(3)',
        'log_not',
        'ret',
      ]);
    });

// ---- Null-aware relational (with var x) ----
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

// ---- AND/OR/XOR with null ----
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

// ---- NOT with null ----
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

// ---- Two sequential IFs ----
    test('two simple IFs', () {
      expect(disasm(compileMain(r'''
f():=BEGIN
  IF 1=0 THEN RETURN "first";
  IF 1=1 THEN RETURN "second";
  RETURN "third";
END;
f()
''')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);
    });

    test('first IF RETURN with map', () {
      expect(disasm(compileMain(r'''
f():=BEGIN
  IF 1=0 THEN RETURN [{"type":"A","data":"empty"}];
  IF 1=1 THEN RETURN [{"type":"B","data":"match"}];
  RETURN [];
END;
f()
''')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);
    });

// ---- IF without ELSE branch ----
    test('IF FALSE THEN "FOO"', () {
      expect(disasm(compileMain('IF FALSE THEN "FOO"')), [
        'push_const(false)',
        'jump_false(4)',
        'push_const("FOO")',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
    });

    test('IF TRUE THEN "FOO"', () {
      expect(disasm(compileMain('IF TRUE THEN "FOO"')), [
        'push_const(true)',
        'jump_false(4)',
        'push_const("FOO")',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- WHILE result ----
    test('WHILE FALSE DO TRUE', () {
      expect(disasm(compileMain('WHILE FALSE DO TRUE')), [
        'push_const(null)',
        'store_reg(0)',
        'push_const(false)',
        'jump_false(7)',
        'push_const(true)',
        'store_reg(0)',
        'jump(2)',
        'load_reg(0)',
        'ret',
      ]);
    });

    test('x := 0; WHILE x < 3 DO BEGIN x := x + 1; x^2 END', () {
      expect(disasm(compileMain('x := 0; WHILE x < 3 DO BEGIN x := x + 1; x^2 END')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(13)',
        'push_const(3)',
        'jump_null(12)',
        'cmp_lt',
        'jump(15)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(41)',
        'push_scope',
        'load_var(X)',
        'jump_null(24)',
        'push_const(1)',
        'jump_null(23)',
        'add',
        'jump(26)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(36)',
        'push_const(2)',
        'jump_null(35)',
        'pow',
        'jump(38)',
        'pop',
        'pop',
        'push_const(null)',
        'pop_scope',
        'store_reg(0)',
        'jump(6)',
        'load_reg(0)',
        'ret',
      ]);
    });

// ---- REPEAT result ----
    test('x := 0; REPEAT BEGIN x := x + 1; x^2 END UNTIL x >= 3', () {
      expect(disasm(compileMain('x := 0; REPEAT BEGIN x := x + 1; x^2 END UNTIL x >= 3')), [
        'push_const(0)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(null)',
        'store_reg(0)',
        'push_scope',
        'load_var(X)',
        'jump_null(14)',
        'push_const(1)',
        'jump_null(13)',
        'add',
        'jump(16)',
        'pop',
        'pop',
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(26)',
        'push_const(2)',
        'jump_null(25)',
        'pow',
        'jump(28)',
        'pop',
        'pop',
        'push_const(null)',
        'pop_scope',
        'store_reg(0)',
        'load_var(X)',
        'jump_null(37)',
        'push_const(3)',
        'jump_null(36)',
        'cmp_gte',
        'jump(39)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_false(6)',
        'load_reg(0)',
        'ret',
      ]);
    });

// ---- IF with AND parenthesised sub-expr ----
    test('IF 1 = 1 AND (2 = 2) THEN "yes" ELSE "no"', () {
      expect(disasm(compileMain('IF 1 = 1 AND (2 = 2) THEN "yes" ELSE "no"')), [
        'push_const(1)',
        'push_const(1)',
        'cmp_eq',
        'push_const(2)',
        'push_const(2)',
        'cmp_eq',
        'log_and',
        'jump_false(10)',
        'push_const("yes")',
        'jump(11)',
        'push_const("no")',
        'ret',
      ]);
    });

    test('IF 1 = 1 AND (2 = 3) THEN "yes" ELSE "no"', () {
      expect(disasm(compileMain('IF 1 = 1 AND (2 = 3) THEN "yes" ELSE "no"')), [
        'push_const(1)',
        'push_const(1)',
        'cmp_eq',
        'push_const(2)',
        'push_const(3)',
        'cmp_eq',
        'log_and',
        'jump_false(10)',
        'push_const("yes")',
        'jump(11)',
        'push_const("no")',
        'ret',
      ]);
    });

// ---- (expr) not implicit multiply ----
    test('(5)-3', () {
      expect(disasm(compileMain('(5)-3')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(3)',
        'jump_null(6)',
        'sub',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('(5)+3', () {
      expect(disasm(compileMain('(5)+3')), [
        'push_const(5)',
        'jump_null(7)',
        'push_const(3)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- Object with standalone lambda values ----
    test('obj:=OBJECT{acc:(x)=>x+1}; obj.acc(5)', () {
      expect(disasm(compileMain('obj:=OBJECT{acc:(x)=>x+1}; obj.acc(5)')), [
        'push_scope',
        'push_const("ACC")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ACC)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

    test('obj:=OBJECT{acc:x=>x+1}; obj.acc(5)', () {
      expect(disasm(compileMain('obj:=OBJECT{acc:x=>x+1}; obj.acc(5)')), [
        'push_scope',
        'push_const("ACC")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ACC)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

    test('fields:=[OBJECT{prop:"x",accessor:(v)=>v+10}]; fields[0].accessor(5)', () {
      expect(disasm(compileMain('fields:=[OBJECT{prop:"x",accessor:(v)=>v+10}]; fields[0].accessor(5)')), [
        'push_scope',
        'push_const("PROP")',
        'push_const("x")',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'make_list(1)',
        'store_var(FIELDS)',
        'load_var(FIELDS)',
        'pop',
        'load_var(FIELDS)',
        'push_const(0)',
        'get_index',
        'get_member(ACCESSOR)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    });

    test('f0:=OBJECT{accessor:(v)=>v+1}; f1:=OBJECT{accessor:(v)=>v*2}; f0.accessor(10)+f1.accessor(10)', () {
      expect(disasm(compileMain('f0:=OBJECT{accessor:(v)=>v+1}; f1:=OBJECT{accessor:(v)=>v*2}; f0.accessor(10)+f1.accessor(10)')), [
        'push_scope',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(F0)',
        'load_var(F0)',
        'pop',
        'push_scope',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_1)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(F1)',
        'load_var(F1)',
        'pop',
        'load_var(F0)',
        'get_member(ACCESSOR)',
        'push_const(10)',
        'call(1)',
        'jump_null(29)',
        'load_var(F1)',
        'get_member(ACCESSOR)',
        'push_const(10)',
        'call(1)',
        'jump_null(28)',
        'add',
        'jump(31)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- parenthesised IF as map value ----
    test('x:=1; obj:={"label":(IF x=1 THEN "one" ELSE "other"),"score":42}; obj["label"]', () {
      expect(disasm(compileMain('x:=1; obj:={"label":(IF x=1 THEN "one" ELSE "other"),"score":42}; obj["label"]')), [
        'push_const(1)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const("label")',
        'load_var(X)',
        'push_const(1)',
        'cmp_eq',
        'jump_false(11)',
        'push_const("one")',
        'jump(12)',
        'push_const("other")',
        'push_const("score")',
        'push_const(42)',
        'make_map(2)',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'push_const("label")',
        'get_index',
        'ret',
      ]);
    });

// ---- Drift-detection: standalone literals ----
    test('42', () {
      expect(disasm(compileMain('42')), [
        'push_const(42)',
        'ret',
      ]);
    });

    test('null', () {
      expect(disasm(compileMain('null')), [
        'push_const(null)',
        'ret',
      ]);
    });

// ---- Drift-detection: plain binary (no null-aware wrap) ----
    test('1=1', () {
      expect(disasm(compileMain('1=1')), [
        'push_const(1)',
        'push_const(1)',
        'cmp_eq',
        'ret',
      ]);
    });

    test('1<>2', () {
      expect(disasm(compileMain('1<>2')), [
        'push_const(1)',
        'push_const(2)',
        'cmp_neq',
        'ret',
      ]);
    });

// ---- Drift-detection: null-aware binary (specific values) ----
    test('1+2', () {
      expect(disasm(compileMain('1+2')), [
        'push_const(1)',
        'jump_null(7)',
        'push_const(2)',
        'jump_null(6)',
        'add',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    test('2^3', () {
      expect(disasm(compileMain('2^3')), [
        'push_const(2)',
        'jump_null(7)',
        'push_const(3)',
        'jump_null(6)',
        'pow',
        'jump(9)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

// ---- Drift-detection: variable load ----
    test('x:=5;x', () {
      expect(disasm(compileMain('x:=5;x')), [
        'push_const(5)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

// ---- Drift-detection: IF structure ----
    test('IF TRUE THEN 1 ELSE 2', () {
      expect(disasm(compileMain('IF TRUE THEN 1 ELSE 2')), [
        'push_const(true)',
        'jump_false(4)',
        'push_const(1)',
        'jump(5)',
        'push_const(2)',
        'ret',
      ]);
    });

// ---- Drift-detection: object / member / index / map ----
    test('OBJECT{x:1}', () {
      expect(disasm(compileMain('OBJECT{x:1}')), [
        'push_scope',
        'push_const("X")',
        'push_const(1)',
        'make_object_here(1)',
        'pop_scope',
        'ret',
      ]);
    });

    test('OBJECT{x:10}', () {
      expect(disasm(compileMain('OBJECT{x:10}')), [
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'make_object_here(1)',
        'pop_scope',
        'ret',
      ]);
    });

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

    test('{"a":1}', () {
      expect(disasm(compileMain('{"a":1}')), [
        'push_const("a")',
        'push_const(1)',
        'make_map(1)',
        'ret',
      ]);
    });

// ---- Drift-detection: function/lambda chunk structure ----
    test('f(x):=x*2', () {
      expect(disasm(compileMain('f(x):=x*2')), [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'ret',
      ]);
    });

    test('x=>x+1', () {
      expect(disasm(compileMain('x=>x+1')), [
        'make_closure(.__lambda_0)',
        'ret',
      ]);
    });

// ---- Navigation stack ----
    test('navigation_stack_pattern', () {
      expect(disasm(compileMain(r'''
navigation_stack:=['main'];
PUSH_ROUTE(route):=BEGIN
  IF LENGTH(navigation_stack)=0 THEN BEGIN
    navigation_stack:=[route];
  END ELSE BEGIN
    IF navigation_stack[LENGTH(navigation_stack)-1]!=route THEN BEGIN
      navigation_stack:=navigation_stack+[route];
    END;
  END;
  RETURN navigation_stack;
END;
POP_ROUTE():=BEGIN
  IF LENGTH(navigation_stack)>1 THEN BEGIN
    RETURN navigation_stack[LENGTH(navigation_stack)-1];
  END ELSE BEGIN
    RETURN 'main';
  END;
END;
PUSH_ROUTE('screen1');
PUSH_ROUTE('screen2');
POP_ROUTE()
''')), [
        'push_const("main")',
        'make_list(1)',
        'store_var(NAVIGATION_STACK)',
        'load_var(NAVIGATION_STACK)',
        'pop',
        'make_closure(.__PUSH_ROUTE_0)',
        'store_var(PUSH_ROUTE)',
        'load_var(PUSH_ROUTE)',
        'pop',
        'make_closure(.__POP_ROUTE_1)',
        'store_var(POP_ROUTE)',
        'load_var(POP_ROUTE)',
        'pop',
        'load_var(PUSH_ROUTE)',
        'push_const("screen1")',
        'call(1)',
        'pop',
        'load_var(PUSH_ROUTE)',
        'push_const("screen2")',
        'call(1)',
        'pop',
        'load_var(POP_ROUTE)',
        'call(0)',
        'ret',
      ]);
    });

}
