import 'dart:io' show File;
import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/lookahead_iterator.dart';
import 'package:shql/parser/parser.dart';
import 'package:shql/tokenizer/token.dart';
import 'package:shql/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Bytecode disassembly helpers — no dependency on bytecode.dart types.
// Uses mnemonic strings and dynamic access so this file needs no extra import.
// ---------------------------------------------------------------------------
const _nameOpMnemonics = {'load_var', 'store_var', 'get_member', 'set_member'};
const _constOpMnemonics = {'push_const', 'make_closure'};

String _fmtConst(dynamic c) {
  if (c == null) return 'null';
  if (c is bool) return '$c';
  if (c is String) return '"$c"';
  if (c is num) return '$c';
  return '.${(c as dynamic).name}'; // ChunkRef
}

/// Disassemble [chunk] into human-readable instruction strings.
/// [chunk] is a BytecodeChunk accessed dynamically to avoid importing bytecode.dart.
List<String> disasm(dynamic chunk) {
  final constants = chunk.constants as List;
  return (chunk.code as List).map<String>((instr) {
    final mnemonic = (instr.op as dynamic).mnemonic as String;
    final hasOperand = (instr.op as dynamic).hasOperand as bool;
    if (!hasOperand) return mnemonic;
    final operand = instr.operand as int;
    if (_nameOpMnemonics.contains(mnemonic)) return '$mnemonic(${constants[operand]})';
    if (_constOpMnemonics.contains(mnemonic)) return '$mnemonic(${_fmtConst(constants[operand])})';
    return '$mnemonic($operand)';
  }).toList();
}

/// Thin wrapper over [Engine.execute] — exact current semantics, no change.
Future<dynamic> evalEngine(
  String src, {
  Runtime? runtime,
  ConstantsSet? constantsSet,
  Map<String, dynamic>? boundValues,
  Scope? startingScope,
}) => Engine.execute(
  src,
  runtime: runtime,
  constantsSet: constantsSet,
  boundValues: boundValues,
  startingScope: startingScope,
);

/// Compile [src] to bytecode, binary-round-trip it, then execute on the VM.
///
/// Always asserts that the disassembly of the `main` chunk after the
/// encode→decode round-trip equals [expectedBytecode] — preventing silent
/// compiler drift between the engine and VM paths.
Future<dynamic> evalBytecode(
  String src,
  List<String> expectedBytecode, {
  Runtime? runtime,
  ConstantsSet? cs,
  Map<String, dynamic>? boundValues,
  Scope? startingScope,
}) {
  cs ??= Runtime.prepareConstantsSet();
  runtime ??= Runtime.prepareRuntime(cs);
  final tree = Parser.parse(src, cs, sourceCode: src);
  final program = BytecodeCompiler.compile(tree, cs);
  final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
  expect(disasm(decoded['main']), expectedBytecode);
  return BytecodeInterpreter(decoded, runtime).executeScoped(
    'main',
    boundValues: boundValues,
    startingScope: startingScope,
  );
}

late String _stdlibSrc;

void shqlBoth(String name, String src, dynamic expected, List<String> expectedBytecode,
    {Map<String, dynamic>? boundValues}) {
  test('$name [engine]', () async => expect(await evalEngine(src, boundValues: boundValues), expected));
  test('$name [bytecode]', () async =>
      expect(await evalBytecode(src, expectedBytecode, boundValues: boundValues), expected));
}

/// Tests [src] against both the engine and bytecode VM, with stdlib pre-loaded
/// as a separate program (not concatenated) — mirroring how herodex_3000 loads
/// stdlib.shql once, then evaluates individual SHQL programs against that runtime.
void shqlBothStdlib(String name, String src, dynamic expected, List<String> expectedBytecode) {
  test('$name [engine]', () async {
    final cs = Runtime.prepareConstantsSet();
    final runtime = Runtime.prepareRuntime(cs);
    await Engine.execute(_stdlibSrc, runtime: runtime, constantsSet: cs);
    expect(await Engine.execute(src, runtime: runtime, constantsSet: cs), expected);
  });
  test('$name [bytecode]', () async {
    final cs = Runtime.prepareConstantsSet();
    final runtime = Runtime.prepareRuntime(cs);
    // Run stdlib as a separate bytecode program to populate the runtime.
    final stdlibTree = Parser.parse(_stdlibSrc, cs, sourceCode: _stdlibSrc);
    final stdlibProg = BytecodeCompiler.compile(stdlibTree, cs);
    final stdlibDecoded = BytecodeDecoder.decode(BytecodeEncoder.encode(stdlibProg));
    await BytecodeInterpreter(stdlibDecoded, runtime).executeScoped('main');
    // Compile src alone with the same cs (identifiers shared), assert its bytecode.
    final srcTree = Parser.parse(src, cs, sourceCode: src);
    final srcProg = BytecodeCompiler.compile(srcTree, cs);
    final srcDecoded = BytecodeDecoder.decode(BytecodeEncoder.encode(srcProg));
    expect(disasm(srcDecoded['main']), expectedBytecode);
    // Execute src against the stdlib-populated runtime.
    expect(
      await BytecodeInterpreter(srcDecoded, runtime).executeScoped('main'),
      expected,
    );
  });
}

void main() {
  setUpAll(() async {
    _stdlibSrc = await File('assets/stdlib.shql').readAsString();
  });

  test('Parse addition', () {
    var v = Tokenizer.tokenize('10+2').toList();
    var constantsSet = ConstantsSet();
    var p = Parser.parseExpression(v.lookahead(), constantsSet);
    expect(p.symbol, Symbols.add);
    expect(p.children[0].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[0].qualifier!), 10);
    expect(p.children[1].symbol, Symbols.integerLiteral);
    expect(constantsSet.getConstantByIndex(p.children[1].qualifier!), 2);
  });

  // Minimal literal / operator programs (drift-detection against bytecode_compiler_test)
  shqlBoth('integer literal 42', '42', 42, [
      'push_const(42)',
      'ret',
    ]);
  shqlBoth('null literal', 'null', null, [
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('1=1', '1=1', true, [
      'push_const(1)',
      'push_const(1)',
      'cmp_eq',
      'ret',
    ]);
  shqlBoth('1<>2', '1<>2', true, [
      'push_const(1)',
      'push_const(2)',
      'cmp_neq',
      'ret',
    ]);
  shqlBoth('1+2', '1+2', 3, [
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
  shqlBoth('2^3', '2^3', 8, [
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
  shqlBoth('x:=5; x', 'x:=5; x', 5, [
      'push_const(5)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(X)',
      'ret',
    ]);
  shqlBoth('IF TRUE THEN 1 ELSE 2', 'IF TRUE THEN 1 ELSE 2', 1, [
      'push_const(true)',
      'jump_false(4)',
      'push_const(1)',
      'jump(5)',
      'push_const(2)',
      'ret',
    ]);
  shqlBoth('OBJECT literal', 'OBJECT{x:1}.x', 1, [
      'push_scope',
      'push_const("X")',
      'push_const(1)',
      'make_object_here(1)',
      'pop_scope',
      'get_member(X)',
      'ret',
    ]);
  shqlBoth('map literal', '{"a":1}["a"]', 1, [
      'push_const("a")',
      'push_const(1)',
      'make_map(1)',
      'push_const("a")',
      'get_index',
      'ret',
    ]);
  shqlBoth('NULL < 5 is null', 'NULL < 5', null, [
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
  shqlBoth('NOT NULL is null', 'NOT NULL', null, [
      'push_const(null)',
      'jump_null(3)',
      'log_not',
      'ret',
    ]);

  shqlBoth('Execute addition', '10+2', 12, [
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
  shqlBoth('Execute addition and multiplication', '10+13*37+1', 492, [
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
  shqlBoth('Execute implicit constant multiplication with parenthesis', 'ANSWER(2)', 84, [
      'push_const(42)',
      'push_const(2)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Execute implicit constant multiplication with parenthesis first', '(2)ANSWER', 84, [
      'push_const(2)',
      'jump_null(7)',
      'push_const(42)',
      'jump_null(6)',
      'mul',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Execute implicit constant multiplication with constant within parenthesis first', '(ANSWER)2', 84, [
      'push_const(42)',
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
  shqlBoth('Execute implicit multiplication with parenthesis', '2(3)', 6, [
      'push_const(2)',
      'push_const(3)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Execute addition and multiplication with parenthesis', '10+13*(37+1)', 504, [
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
  shqlBoth('Execute addition and implicit multiplication with parenthesis', '10+13(37+1)', 504, [
      'push_const(10)',
      'jump_null(17)',
      'push_const(13)',
      'push_const(37)',
      'jump_null(10)',
      'push_const(1)',
      'jump_null(9)',
      'add',
      'jump(12)',
      'pop',
      'pop',
      'push_const(null)',
      'call(1)',
      'jump_null(16)',
      'add',
      'jump(19)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Execute addition, multiplication and subtraction', '10+13*37-1', 490, [
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
  shqlBoth('Execute addition, implicit multiplication and subtraction', '10+13(37)-1', 490, [
      'push_const(10)',
      'jump_null(9)',
      'push_const(13)',
      'push_const(37)',
      'call(1)',
      'jump_null(8)',
      'add',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'jump_null(17)',
      'push_const(1)',
      'jump_null(16)',
      'sub',
      'jump(19)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Execute addition, multiplication, subtraction and division', '10+13*37/2-1', 249.5, [
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
  shqlBoth('Execute addition, implicit multiplication, subtraction and division', '10+13(37)/2-1', 249.5, [
      'push_const(10)',
      'jump_null(17)',
      'push_const(13)',
      'push_const(37)',
      'call(1)',
      'jump_null(11)',
      'push_const(2)',
      'jump_null(10)',
      'div',
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
      'jump_null(25)',
      'push_const(1)',
      'jump_null(24)',
      'sub',
      'jump(27)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);

  shqlBoth('Execute modulus', '9%2', 1, [
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
  shqlBoth('exponentiation 2^10', '2^10', 1024, [
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
  shqlBoth('Execute equality true', '5*2 = 2+8', true, [
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
  shqlBoth('Execute equality false', '5*2 = 1+8', false, [
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
  shqlBoth('Execute not equal true', '5*2 <> 1+8', true, [
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
  shqlBoth('Execute not equal true with exclamation equals', '5*2 != 1+8', true, [
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

  shqlBoth('Evaluate match — Superman regex', r'"Super Man" ~  r"Super\s*Man"', true, [
      'push_const("Super Man")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate match — Superman plain', r'"Superman" ~  r"Super\s*Man"', true, [
      'push_const("Superman")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate match — Batman case-insensitive', '"Batman" ~  "batman"', true, [
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
  shqlBoth('Evaluate match false — Bat Man', r'"Bat Man" ~  r"Super\s*Man"', false, [
      'push_const("Bat Man")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate match false — Batman', r'"Batman" ~  r"Super\s*Man"', false, [
      'push_const("Batman")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate mismatch true — Bat Man', r'"Bat Man" !~  r"Super\s*Man"', true, [
      'push_const("Bat Man")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_not_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate mismatch true — Batman', r'"Batman" !~  r"Super\s*Man"', true, [
      'push_const("Batman")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_not_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate mismatch false — Superman', r'"Super Man" !~  r"Super\s*Man"', false, [
      'push_const("Super Man")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_not_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('Evaluate mismatch false — Superman2', r'"Superman" !~  r"Super\s*Man"', false, [
      'push_const("Superman")',
      'jump_null(7)',
      'push_const("Super\\s*Man")',
      'jump_null(6)',
      'op_not_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);

  shqlBoth('Evaluate match — bat.* true', '"Batman" ~  "bat.*"', true, [
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
  shqlBoth('Evaluate match — bat.* false', '"Robin" ~  "bat.*"', false, [
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
  shqlBoth('Evaluate mismatch — bat.* true (Robin)', '"Robin" !~  "bat.*"', true, [
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
  shqlBoth('Evaluate mismatch — bat.* false (Batman)', '"Batman" !~  "bat.*"', false, [
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

  shqlBoth('in string — Bat in Batman', '"Bat" in "Batman"', true, [
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
  shqlBoth('in string — bat in Batman (case-sensitive)', '"bat" in "Batman"', false, [
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

  shqlBoth('in list — Super Man found', '"Super Man" in ["Super Man", "Batman"]', true, [
      'push_const("Super Man")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('in list — Super Man found (finns_i)', '"Super Man" finns_i ["Super Man", "Batman"]', true, [
      'push_const("Super Man")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('in list — Batman found', '"Batman" in  ["Super Man", "Batman"]', true, [
      'push_const("Batman")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('in list — Batman found (finns_i)', '"Batman" finns_i  ["Super Man", "Batman"]', true, [
      'push_const("Batman")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('in list — Robin not found', '"Robin" in  ["Super Man", "Batman"]', false, [
      'push_const("Robin")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('in list — Superman not found', '"Superman" in ["Super Man", "Batman"]', false, [
      'push_const("Superman")',
      'jump_null(9)',
      'push_const("Super Man")',
      'push_const("Batman")',
      'make_list(2)',
      'jump_null(8)',
      'op_in',
      'jump(11)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBothStdlib('in list — lowercase Robin found', 'lowercase("Robin") in  ["batman", "robin"]', true, [
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
  shqlBothStdlib('in list — lowercase Batman found', 'lowercase("Batman") in  ["batman", "robin"]', true, [
      'load_var(LOWERCASE)',
      'push_const("Batman")',
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
  shqlBothStdlib('in list — lowercase robin not found', 'lowercase("robin") in  ["super man", "batman"]', false, [
      'load_var(LOWERCASE)',
      'push_const("robin")',
      'call(1)',
      'jump_null(11)',
      'push_const("super man")',
      'push_const("batman")',
      'make_list(2)',
      'jump_null(10)',
      'op_in',
      'jump(13)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBothStdlib('in list — lowercase robin not found (finns_i)', 'lowercase("robin") finns_i  ["super man", "batman"]', false, [
      'load_var(LOWERCASE)',
      'push_const("robin")',
      'call(1)',
      'jump_null(11)',
      'push_const("super man")',
      'push_const("batman")',
      'make_list(2)',
      'jump_null(10)',
      'op_in',
      'jump(13)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBothStdlib('in list — lowercase superman not found', 'lowercase("superman") in  ["super man", "batman"]', false, [
      'load_var(LOWERCASE)',
      'push_const("superman")',
      'call(1)',
      'jump_null(11)',
      'push_const("super man")',
      'push_const("batman")',
      'make_list(2)',
      'jump_null(10)',
      'op_in',
      'jump(13)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBothStdlib('in list — lowercase superman not found (finns_i)', 'lowercase("superman") finns_i  ["super man", "batman"]', false, [
      'load_var(LOWERCASE)',
      'push_const("superman")',
      'call(1)',
      'jump_null(11)',
      'push_const("super man")',
      'push_const("batman")',
      'make_list(2)',
      'jump_null(10)',
      'op_in',
      'jump(13)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);

  shqlBoth('Execute not equal false', '5*2 <> 2+8', false, [
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
  shqlBoth('Execute not equal false with exclamation equals', '5*2 != 2+8', false, [
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
  shqlBoth('Execute less than false', '10<1', false, [
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
  shqlBoth('Execute less than true', '1<10', true, [
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
  shqlBoth('Execute less than or equal false', '10<=1', false, [
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
  shqlBoth('Execute less than or equal true', '1<=10', true, [
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
  shqlBoth('Execute greater than false', '1>10', false, [
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
  shqlBoth('Execute greater than true', '10>1', true, [
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
  shqlBoth('Execute greater than or equal false', '1>=10', false, [
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
  shqlBoth('Execute greater than or equal true', '10>=1', true, [
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

  shqlBoth('AND true', '1<10 AND 2<9', true, [
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
  shqlBoth('AND true (OCH)', '1<10 OCH 2<9', true, [
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
  shqlBoth('AND false', '1>10 AND 2<9', false, [
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
  shqlBoth('AND false (OCH)', '1>10 OCH 2<9', false, [
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
  shqlBoth('OR true', '1>10 OR 2<9', true, [
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
  shqlBoth('OR true (ELLER)', '1>10 ELLER 2<9', true, [
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
  shqlBoth('XOR true', '1>10 XOR 2<9', true, [
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
  shqlBoth('XOR true (ANTINGEN_ELLER)', '1>10 ANTINGEN_ELLER 2<9', true, [
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
  shqlBoth('XOR false', '10>1 XOR 2<9', false, [
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
  shqlBoth('XOR false (ANTINGEN_ELLER)', '10>1 ANTINGEN_ELLER 2<9', false, [
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
  shqlBoth('NOT true number', 'NOT 11', false, [
      'push_const(11)',
      'jump_null(3)',
      'log_not',
      'ret',
    ]);
  shqlBoth('NOT true number (INTE)', 'INTE 11', false, [
      'push_const(11)',
      'jump_null(3)',
      'log_not',
      'ret',
    ]);

  shqlBoth('calculate_negation with exclamation', '!11', false, [
      'push_const(11)',
      'jump_null(3)',
      'log_not',
      'ret',
    ]);
  shqlBoth('Execute unary minus', '-5+11', 6, [
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
  shqlBoth('Execute unary plus', '+5+11', 16, [
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
  shqlBoth('Execute with constants', 'PI * 2', 3.1415926535897932 * 2, [
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
  shqlBoth('Execute with lowercase constants', 'pi * 2', 3.1415926535897932 * 2, [
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
  shqlBoth('ANSWER constant', 'ANSWER', 42, [
      'push_const(42)',
      'ret',
    ]);
  shqlBoth('TRUE constant', 'TRUE', true, [
      'push_const(true)',
      'ret',
    ]);
  shqlBoth('FALSE constant', 'FALSE', false, [
      'push_const(false)',
      'ret',
    ]);

  shqlBothStdlib('Execute with functions', 'POW(2,2)', 4, [
      'load_var(POW)',
      'push_const(2)',
      'push_const(2)',
      'call(2)',
      'ret',
    ]);
  shqlBothStdlib('Execute with two functions', 'POW(2,2)+SQRT(4)', 6, [
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
  shqlBothStdlib('Calculate library function', 'SQRT(4)', 2, [
      'load_var(SQRT)',
      'push_const(4)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('Execute nested function call', 'SQRT(POW(2,2))', 2, [
      'load_var(SQRT)',
      'load_var(POW)',
      'push_const(2)',
      'push_const(2)',
      'call(2)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('Execute nested function call with expression', 'SQRT(POW(2,2)+10)', 3.7416573867739413, [
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
  shqlBothStdlib('LOWERCASE', "LOWERCASE(\"Hello\")", 'hello', [
      'load_var(LOWERCASE)',
      'push_const("Hello")',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('UPPERCASE', "UPPERCASE(\"hello\")", 'HELLO', [
      'load_var(UPPERCASE)',
      'push_const("hello")',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('STRING', "STRING(42)", '42', [
      'load_var(STRING)',
      'push_const(42)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('INT truncates float', 'INT(3.9)', 3, [
      'load_var(INT)',
      'push_const(3.9)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('ROUND', 'ROUND(3.6)', 4, [
      'load_var(ROUND)',
      'push_const(3.6)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('MIN', 'MIN(3, 7)', 3, [
      'load_var(MIN)',
      'push_const(3)',
      'push_const(7)',
      'call(2)',
      'ret',
    ]);
  shqlBothStdlib('MAX', 'MAX(3, 7)', 7, [
      'load_var(MAX)',
      'push_const(3)',
      'push_const(7)',
      'call(2)',
      'ret',
    ]);
  shqlBothStdlib('SUBSTRING', "SUBSTRING(\"hello world\", 0, 5)", 'hello', [
      'load_var(SUBSTRING)',
      'push_const("hello world")',
      'push_const(0)',
      'push_const(5)',
      'call(3)',
      'ret',
    ]);
  shqlBothStdlib('LENGTH of string', "LENGTH(\"hello\")", 5, [
      'load_var(LENGTH)',
      'push_const("hello")',
      'call(1)',
      'ret',
    ]);

  shqlBoth('Execute two expressions', '10;11', 11, [
      'push_const(10)',
      'pop',
      'push_const(11)',
      'ret',
    ]);
  shqlBoth('Execute two expressions with final semicolon', '10;11;', 11, [
      'push_const(10)',
      'pop',
      'push_const(11)',
      'ret',
    ]);
  shqlBoth('sequence of two expressions', 'r := BEGIN 10;11 END; r', 11, [
      'push_scope',
      'push_const(10)',
      'pop',
      'push_const(11)',
      'pop_scope',
      'store_var(R)',
      'load_var(R)',
      'pop',
      'load_var(R)',
      'ret',
    ]);
  shqlBoth('sequence with trailing semicolon', 'r := BEGIN 10;11; END; r', 11, [
      'push_scope',
      'push_const(10)',
      'pop',
      'push_const(11)',
      'pop_scope',
      'store_var(R)',
      'load_var(R)',
      'pop',
      'load_var(R)',
      'ret',
    ]);
  shqlBoth('Test assignment', 'i:=42', 42, [
      'push_const(42)',
      'store_var(I)',
      'load_var(I)',
      'ret',
    ]);
  shqlBoth('Test increment', 'i:=41; i:=i+1', 42, [
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

  shqlBoth('standalone function def', 'f(x):=x*2', isNotNull, [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'ret',
    ]);
  shqlBoth('standalone lambda def', 'x=>x+1', isNotNull, [
      'make_closure(.__lambda_0)',
      'ret',
    ]);

  test('Test function definition', () async {
    const src = 'f(x):=x*2';
    expect(await evalEngine(src), isA<UserFunction>());
    expect(await evalBytecode(src, ['make_closure(.__F_0)', 'store_var(F)', 'load_var(F)', 'ret']), isNotNull);
  });

  shqlBoth('Test user function', 'f(x):=x*2; f(2)', 4, [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'push_const(2)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test two argument user function', 'f(a,b):=a-b; f(10,2)', 8, [
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
  shqlBoth('Test recursion', 'fac(x) := IF x <= 1 THEN 1 ELSE x * fac(x-1); fac(3)', 6, [
      'make_closure(.__FAC_0)',
      'store_var(FAC)',
      'load_var(FAC)',
      'pop',
      'load_var(FAC)',
      'push_const(3)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test while loop', 'x := 0; WHILE x < 10 DO x := x + 1; x', 10, [
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
  shqlBoth('Test lambda function', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 1,2,3)', 6, [
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
  shqlBoth('Test lambda function with user function argument', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 10,20,5)', 35, [
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
  shqlBoth('Test lambda expression', 'f:= x => x^2; f(3)', 9, [
      'make_closure(.__lambda_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'push_const(3)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test anonymous lambda expression', '(x => x^2)(3)', 9, [
      'make_closure(.__lambda_0)',
      'push_const(3)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test nullary anonymous lambda expression', '(() => 9)()', 9, [
      'make_closure(.__lambda_0)',
      'call(0)',
      'ret',
    ]);
  shqlBoth('Test return', 'f(x) := IF x % 2 = 0 THEN RETURN x+1 ELSE RETURN x; f(2)', 3, [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'push_const(2)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test block return', 'f(x) := BEGIN IF x % 2 = 0 THEN RETURN x+1; RETURN x; END; f(2)', 3, [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'push_const(2)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test factorial with return', 'f(x) := BEGIN IF x <= 1 THEN RETURN 1; RETURN x * f(x-1); END; f(5)', 120, [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'push_const(5)',
      'call(1)',
      'ret',
    ]);
  shqlBoth('Test break', 'x := 0; WHILE TRUE DO BEGIN x := x + 1; IF x = 10 THEN BREAK; END; x', 10, [
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
  shqlBoth('Test continue', 'x := 0; y := 0; WHILE x < 10 DO BEGIN x := x + 1; IF x % 2 = 0 THEN CONTINUE; y := y + 1; END; y', 5, [
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

  shqlBoth('FOR CONTINUE with IF', r'''
      __test() := BEGIN
        __result := [];
        FOR __i := 0 TO 2 DO BEGIN
          IF __i = 1 THEN CONTINUE;
          __result := __result + [__i];
        END;
        RETURN __result;
      END;
      __test()
    ''', [0, 2], [
      'make_closure(.____TEST_0)',
      'store_var(__TEST)',
      'load_var(__TEST)',
      'pop',
      'load_var(__TEST)',
      'call(0)',
      'ret',
    ]);

  shqlBoth('FOR CONTINUE with nested IF-ELSE IF', r'''
      __test() := BEGIN
        __result := [];
        FOR __i := 0 TO 2 DO BEGIN
          IF __i = 0 THEN __result := __result + ['zero']
          ELSE IF __i = 1 THEN BEGIN
            __result := __result + ['skip'];
            CONTINUE;
          END
          ELSE __result := __result + ['two'];
          __result := __result + ['after'];
        END;
        RETURN __result;
      END;
      __test()
    ''', ['zero', 'after', 'skip', 'two', 'after'], [
      'make_closure(.____TEST_0)',
      'store_var(__TEST)',
      'load_var(__TEST)',
      'pop',
      'load_var(__TEST)',
      'call(0)',
      'ret',
    ]);

  shqlBoth('FOR CONTINUE inside nested IF-THEN-BEGIN-END', r'''
      __test() := BEGIN
        __result := [];
        __flag := TRUE;
        FOR __i := 0 TO 2 DO BEGIN
          IF __flag THEN BEGIN
            IF __i = 1 THEN BEGIN
              __result := __result + ['skip'];
              CONTINUE;
            END;
          END;
          __result := __result + [__i];
        END;
        RETURN __result;
      END;
      __test()
    ''', [0, 'skip', 2], [
      'make_closure(.____TEST_0)',
      'store_var(__TEST)',
      'load_var(__TEST)',
      'pop',
      'load_var(__TEST)',
      'call(0)',
      'ret',
    ]);

  shqlBothStdlib('FOR CONTINUE with nested ELSE IF BREAK pattern', r'''
      __test() := BEGIN
        __result := [];
        __flag := TRUE;
        __action := 'skip';
        FOR __i := 0 TO 2 DO BEGIN
          IF __flag THEN BEGIN
            IF __action = 'saveAll' THEN __result := __result + ['saveAll']
            ELSE IF __action = 'cancel' THEN BEGIN
              __result := __result + ['cancel'];
              BREAK;
            END
            ELSE IF __action <> 'save' THEN BEGIN
              __result := __result + ['skipped'];
              CONTINUE;
            END;
          END;
          __result := __result + ['after:' + STRING(__i)];
        END;
        RETURN __result;
      END;
      __test()
    ''', ['skipped', 'skipped', 'skipped'], [
      'make_closure(.____TEST_0)',
      'store_var(__TEST)',
      'load_var(__TEST)',
      'pop',
      'load_var(__TEST)',
      'call(0)',
      'ret',
    ]);

  shqlBoth('Test repeat until', 'x := 0; REPEAT x := x + 1 UNTIL x = 10; x', 10, [
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
  shqlBoth('Test for loop', 'sum := 0; FOR i := 1 TO 10 DO sum := sum + i; sum', 55, [
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
  shqlBoth('FOR 0 TO 0 iterates once', 'sum:=0; FOR i:=0 TO 0 DO sum:=sum+1; sum', 1, [
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

  const _listUtilsCode = """
-- This function is now only used to generate the initial cache.
_GEN_LIST_ITEM_TEMPLATE(i) := {
    "type": "Container",
    "props": {
        "height": 50,
        "color": '0xFF' + SUBSTRING(MD5('item' + STRING(i)), 0, 6),
        "padding": { "left": 16, "right": 16 }
    },
    "child": {
        "type": "Row",
        "children": [
            {
                "type": "Text",
                "props": {
                    "data": ""  -- The data will be injected dynamically.
                }
            },
            { "type": "Spacer" },
            {
                "type": "ElevatedButton",
                "props": {
                    "onPressed": "shql: INCREMENT_ITEM(" + STRING(i-1) + ")"
                },
                "child": {
                    "type": "Text",
                    "props": { "data": "+" }
                }
            }
        ]
    }
};

-- This is the new, fast function that the UI will call on every rebuild.
GENERATE_WIDGETS(n) := BEGIN
    -- If the cache is empty, populate it once.
    IF LENGTH(_list_item_cache) = 0 THEN BEGIN
        FOR i := 1 TO n DO
            _list_item_cache := _list_item_cache + [_GEN_LIST_ITEM_TEMPLATE(i)];
    END;

    -- Now, create the final list by injecting the current counts into the cached templates.
    items := [];
    FOR i := 1 TO n DO
        -- Important: We need to create a copy of the map from the cache,
        -- otherwise we would be modifying the cache itself.
        item_template := CLONE(_list_item_cache[i-1]);

        -- Inject the current count into the Text widget's data property.
        item_template["child"]["children"][0]["props"]["data"] := 'Item ' + STRING(i) + ': ' + STRING(item_counts[i-1]);

        items := items + [item_template];
    RETURN items;
END;
""";

  shqlBothStdlib('Test list utils - item', '$_listUtilsCode\nlist := [_GEN_LIST_ITEM_TEMPLATE(1)]; list[0]', isA<Map>(), []);
  shqlBothStdlib('Test list utils - props', "$_listUtilsCode\nlist := [_GEN_LIST_ITEM_TEMPLATE(1)]; list[0]['props']", isA<Map>(), []);

  shqlBoth('Test for loop with step', 'sum := 0; FOR i := 1 TO 10 STEP 2 DO sum := sum + i; sum', 25, [
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
  shqlBoth('Test for loop counting down', 'sum := 0; FOR i := 10 TO 1 STEP -1 DO sum := sum + i; sum', 55, [
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

  shqlBoth('Can assign to list variable', 'x := [1,2,3]; x[0]', 1, [
      'push_const(1)',
      'push_const(2)',
      'push_const(3)',
      'make_list(3)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(X)',
      'push_const(0)',
      'get_index',
      'ret',
    ]);
  shqlBoth('Can assign to list member', 'x := [1,2,3]; x[1]:=4; x[1]', 4, [
      'push_const(1)',
      'push_const(2)',
      'push_const(3)',
      'make_list(3)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(X)',
      'push_const(1)',
      'push_const(4)',
      'set_index',
      'pop',
      'load_var(X)',
      'push_const(1)',
      'get_index',
      'ret',
    ]);
  shqlBoth('list literal', '[1,2,3]', [1,2,3], [
      'push_const(1)',
      'push_const(2)',
      'push_const(3)',
      'make_list(3)',
      'ret',
    ]);
  shqlBoth('empty list literal', '[]', [], [
      'make_list(0)',
      'ret',
    ]);
  shqlBoth('list concatenation', '[1,2]+[3,4]', [1,2,3,4], [
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
  shqlBoth('list index read', 'x:=[10,20,30]; x[1]', 20, [
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

  shqlBoth('Can create thread', 'THREAD( () => 9 ) <> null', true, [
      'load_var(THREAD)',
      'make_closure(.__lambda_0)',
      'call(1)',
      'push_const(null)',
      'cmp_neq',
      'ret',
    ]);

  shqlBoth('Can assign to map variable', "x := {'a':1,'b':2,'c':3}; x['a']", 1, [
      'push_const("a")',
      'push_const(1)',
      'push_const("b")',
      'push_const(2)',
      'push_const("c")',
      'push_const(3)',
      'make_map(3)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(X)',
      'push_const("a")',
      'get_index',
      'ret',
    ]);
  shqlBoth('Can assign to map member', "x := {'a':1,'b':2,'c':3}; x['b']:=4; x['b']", 4, [
      'push_const("a")',
      'push_const(1)',
      'push_const("b")',
      'push_const(2)',
      'push_const("c")',
      'push_const(3)',
      'make_map(3)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(X)',
      'push_const("b")',
      'push_const(4)',
      'set_index',
      'pop',
      'load_var(X)',
      'push_const("b")',
      'get_index',
      'ret',
    ]);
  shqlBoth('map literal index read', "{'a':1,'b':2}['a']", 1, [
      'push_const("a")',
      'push_const(1)',
      'push_const("b")',
      'push_const(2)',
      'make_map(2)',
      'push_const("a")',
      'get_index',
      'ret',
    ]);
  shqlBoth('map index write', "x:={'a':1,'b':2}; x['b']:=99; x['b']", 99, [
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

  shqlBoth('Can start thread', "x := 0; t := THREAD( () => BEGIN FOR i := 1 TO 1000 DO x := x + 1; END ); JOIN(t); x", 1000, [
      'push_const(0)',
      'store_var(X)',
      'load_var(X)',
      'pop',
      'load_var(THREAD)',
      'make_closure(.__lambda_0)',
      'call(1)',
      'store_var(T)',
      'load_var(T)',
      'pop',
      'load_var(JOIN)',
      'load_var(T)',
      'call(1)',
      'pop',
      'load_var(X)',
      'ret',
    ]);

  shqlBoth('Global variable accessed in function',
      'my_global := 42; GET_GLOBAL() := my_global; GET_GLOBAL()', 42, [
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
  shqlBoth('Global variable modified in function',
      'my_global := 10; ADD_TO_GLOBAL(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD_TO_GLOBAL(5)', 15, [
      'push_const(10)',
      'store_var(MY_GLOBAL)',
      'load_var(MY_GLOBAL)',
      'pop',
      'make_closure(.__ADD_TO_GLOBAL_0)',
      'store_var(ADD_TO_GLOBAL)',
      'load_var(ADD_TO_GLOBAL)',
      'pop',
      'load_var(ADD_TO_GLOBAL)',
      'push_const(5)',
      'call(1)',
      'ret',
    ]);
  shqlBothStdlib('Global array accessed in function',
      'my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); GET_LENGTH()', 3, [
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
  shqlBothStdlib('Global array modified in function — element at 3',
      'my_array := [1, 2, 3]; PUSH_TO_ARRAY(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH_TO_ARRAY(4)[3]', 4, [
      'push_const(1)',
      'push_const(2)',
      'push_const(3)',
      'make_list(3)',
      'store_var(MY_ARRAY)',
      'load_var(MY_ARRAY)',
      'pop',
      'make_closure(.__PUSH_TO_ARRAY_0)',
      'store_var(PUSH_TO_ARRAY)',
      'load_var(PUSH_TO_ARRAY)',
      'pop',
      'load_var(PUSH_TO_ARRAY)',
      'push_const(4)',
      'call(1)',
      'push_const(3)',
      'get_index',
      'ret',
    ]);
  shqlBothStdlib('Navigation stack push/pop pattern', r'''
navigation_stack := ['main'];
PUSH_ROUTE(route) := BEGIN
  IF LENGTH(navigation_stack) = 0 THEN BEGIN
    navigation_stack := [route];
  END ELSE BEGIN
    IF navigation_stack[LENGTH(navigation_stack) - 1] != route THEN BEGIN
      navigation_stack := navigation_stack + [route];
    END;
  END;
  RETURN navigation_stack;
END;
POP_ROUTE() := BEGIN
  IF LENGTH(navigation_stack) > 1 THEN BEGIN
    RETURN navigation_stack[LENGTH(navigation_stack) - 1];
  END ELSE BEGIN
    RETURN 'main';
  END;
END;
PUSH_ROUTE('screen1');
PUSH_ROUTE('screen2');
POP_ROUTE()
''', 'screen2', [
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

  shqlBoth('User function can access constants like TRUE', 'test() := TRUE; test()', true, [
      'make_closure(.__TEST_0)',
      'store_var(TEST)',
      'load_var(TEST)',
      'pop',
      'load_var(TEST)',
      'call(0)',
      'ret',
    ]);

  group('Error reporting tests', () {
    test('Should show correct line numbers in error messages', () async {
      const src = 'test() := undefinedFunction(); test()';

      // Engine reports source location and identifier name.
      try {
        await evalEngine(src);
        fail('Expected RuntimeException to be thrown');
      } catch (e) {
        expect(e.toString(), contains('Line 1:'));
        expect(e.toString(), contains('undefinedFunction'));
      }

      // Bytecode must also throw on the same SHQL.
      try {
        await evalBytecode(src, ['make_closure(.__TEST_0)', 'store_var(TEST)', 'load_var(TEST)', 'pop', 'load_var(TEST)', 'call(0)', 'ret']);
        fail('Expected bytecode to throw');
      } catch (e) {
        if (e is TestFailure) rethrow;
      }
    });
  });

  group('startingScope and boundValues injection', () {
    shqlBoth('boundValues visible', 'x + 1', 11,
        ['load_var(X)', 'jump_null(7)', 'push_const(1)', 'jump_null(6)', 'add', 'jump(9)', 'pop', 'pop', 'push_const(null)', 'ret'],
        boundValues: {'x': 10});
    test('boundValues shadow global', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      rt.globalScope.setVariable(cs.identifiers.include('X'), 99);
      expect(await evalEngine('x', runtime: rt, constantsSet: cs, boundValues: {'x': 42}), 42);
      expect(await evalBytecode('x', ['load_var(X)', 'ret'], runtime: rt, cs: cs, boundValues: {'x': 42}), 42);
    });
    test('startingScope variables visible', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('LABEL'), 'hello');
      expect(await evalEngine('label', runtime: rt, constantsSet: cs, startingScope: scope), 'hello');
      expect(await evalBytecode('label', ['load_var(LABEL)', 'ret'], cs: cs, runtime: rt, startingScope: scope), 'hello');
    });
    test('boundValues shadow startingScope', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('X'), 1);
      expect(await evalEngine('x', runtime: rt, constantsSet: cs, startingScope: scope, boundValues: {'x': 2}), 2);
      expect(await evalBytecode('x', ['load_var(X)', 'ret'], cs: cs, runtime: rt, startingScope: scope, boundValues: {'x': 2}), 2);
    });
  });

  group('List utility functions', () {
    shqlBothStdlib('LENGTH of 3-element list', 'LENGTH([1, 2, 3])', 3, [
        'load_var(LENGTH)',
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'call(1)',
        'ret',
      ]);
    shqlBothStdlib('LENGTH of empty list', 'LENGTH([])', 0, [
        'load_var(LENGTH)',
        'make_list(0)',
        'call(1)',
        'ret',
      ]);
  });

  group('Object member access with dot operator', () {
    shqlBoth('Should access Object members using dot notation',
        'person := OBJECT{name: "Alice", age: 30}; [person.name, person.age]', ["Alice", 30], [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'push_const("AGE")',
        'push_const(30)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(PERSON)',
        'load_var(PERSON)',
        'pop',
        'load_var(PERSON)',
        'get_member(NAME)',
        'load_var(PERSON)',
        'get_member(AGE)',
        'make_list(2)',
        'ret',
      ]);
    shqlBoth('Should wrap Object in Scope for member access',
        'config := OBJECT{host: "localhost", port: 8080}; [config.host, config.port]', ["localhost", 8080], [
        'push_scope',
        'push_const("HOST")',
        'push_const("localhost")',
        'push_const("PORT")',
        'push_const(8080)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(CONFIG)',
        'load_var(CONFIG)',
        'pop',
        'load_var(CONFIG)',
        'get_member(HOST)',
        'load_var(CONFIG)',
        'get_member(PORT)',
        'make_list(2)',
        'ret',
      ]);
    shqlBoth('Should support nested object access (a.b.c.d)', '''
        db := OBJECT{host: "db.example.com", port: 5432};
        server := OBJECT{database: db, name: "prod-server"};
        app := OBJECT{server: server, version: "1.0.0"};
        [app.server.database.host, app.server.database.port, app.server.name, app.version]
    ''', ["db.example.com", 5432, "prod-server", "1.0.0"], [
        'push_scope',
        'push_const("HOST")',
        'push_const("db.example.com")',
        'push_const("PORT")',
        'push_const(5432)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(DB)',
        'load_var(DB)',
        'pop',
        'push_scope',
        'push_const("DATABASE")',
        'load_var(DB)',
        'push_const("NAME")',
        'push_const("prod-server")',
        'make_object_here(2)',
        'pop_scope',
        'store_var(SERVER)',
        'load_var(SERVER)',
        'pop',
        'push_scope',
        'push_const("SERVER")',
        'load_var(SERVER)',
        'push_const("VERSION")',
        'push_const("1.0.0")',
        'make_object_here(2)',
        'pop_scope',
        'store_var(APP)',
        'load_var(APP)',
        'pop',
        'load_var(APP)',
        'get_member(SERVER)',
        'get_member(DATABASE)',
        'get_member(HOST)',
        'load_var(APP)',
        'get_member(SERVER)',
        'get_member(DATABASE)',
        'get_member(PORT)',
        'load_var(APP)',
        'get_member(SERVER)',
        'get_member(NAME)',
        'load_var(APP)',
        'get_member(VERSION)',
        'make_list(4)',
        'ret',
      ]);
  });

  group('Object literal with OBJECT keyword', () {
    shqlBoth('OBJECT literal keys are unquoted identifiers',
        'obj := OBJECT{name: "Alice", age: 30}; [obj.name, obj.age]', ["Alice", 30], [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'push_const("AGE")',
        'push_const(30)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(NAME)',
        'load_var(OBJ)',
        'get_member(AGE)',
        'make_list(2)',
        'ret',
      ]);

    shqlBoth('Object literal dot — x', 'obj := OBJECT{x: 10, y: 20}; obj.x', 10, [
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
    shqlBoth('Object literal dot — y', 'obj := OBJECT{x: 10, y: 20}; obj.y', 20, [
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
        'get_member(Y)',
        'ret',
      ]);
    shqlBoth('Nested Objects — person.name', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.name', 'Bob', [
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
    shqlBoth('Nested Objects — person.age', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.age', 25, [
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
        'get_member(AGE)',
        'ret',
      ]);
    shqlBoth('Object complex value — list element', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; list := obj.list; list[1]', 2, [
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
        'get_member(LIST)',
        'store_var(LIST)',
        'load_var(LIST)',
        'pop',
        'load_var(LIST)',
        'push_const(1)',
        'get_index',
        'ret',
      ]);
    shqlBoth('Object complex value — sum', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; obj.sum', 3, [
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
    shqlBoth('Object member assignment — x', 'obj := OBJECT{x: 10, y: 20}; obj.x := 100; obj.x', 100, [
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
    shqlBoth('Object member assignment — y', 'obj := OBJECT{x: 10, y: 20}; obj.y := 200; obj.y', 200, [
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
        'push_const(200)',
        'set_member(Y)',
        'pop',
        'load_var(OBJ)',
        'get_member(Y)',
        'ret',
      ]);

    shqlBoth('OBJECT literal is not a Map', 'OBJECT{name: "Alice"}', isA<Object>(), [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'make_object_here(1)',
        'pop_scope',
        'ret',
      ]);
    shqlBoth('variable-keyed brace literal is a Map', 'x := "name"; {x: "Alice"}', isA<Map>(), [
        'push_const("name")',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const("Alice")',
        'make_map(1)',
        'ret',
      ]);
    shqlBoth('number-keyed brace literal is a Map', '{42: "answer"}', isA<Map>(), [
        'push_const(42)',
        'push_const("answer")',
        'make_map(1)',
        'ret',
      ]);

    shqlBoth('Should assign to nested Object members', 'obj := OBJECT{inner: OBJECT{value: 5}}; obj.inner.value := 42; obj.inner.value', 42, [
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
    shqlBoth('Should modify Object member and read it back', 'obj := OBJECT{counter: 0}; obj.counter := obj.counter + 1; obj.counter', 1, [
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

  group('Object methods with proper scope', () {
    shqlBoth('Should access object members from method', 'obj := OBJECT{x: 10, getX: () => x}; obj.getX()', 10, [
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
    shqlBoth('Should access multiple object members from method', 'obj := OBJECT{x: 10, y: 20, sum: () => x + y}; obj.sum()', 30, [
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
    shqlBoth('Should modify object members from method', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.counter', 1, [
        'push_scope',
        'push_const("COUNTER")',
        'push_const(0)',
        'push_const("INCREMENT")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(COUNTER)',
        'ret',
      ]);
    shqlBoth('Should call method multiple times and modify state', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.increment(); obj.increment(); obj.counter', 3, [
        'push_scope',
        'push_const("COUNTER")',
        'push_const(0)',
        'push_const("INCREMENT")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(COUNTER)',
        'ret',
      ]);
    shqlBoth('Should access method parameters and object members', 'obj := OBJECT{x: 10, add: (delta) => x + delta}; obj.add(5)', 15, [
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
    shqlBoth('Should modify object member with parameter', 'obj := OBJECT{x: 10, setX: (newX) => x := newX}; obj.setX(42); obj.x', 42, [
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
    shqlBoth('Should access nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, getInnerValue: () => inner.value}; obj.getInnerValue()', 5, [
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
    shqlBoth('Should modify nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, incrementInner: () => inner.value := inner.value + 1}; obj.incrementInner(); obj.inner.value', 6, [
        'push_scope',
        'push_const("INNER")',
        'push_scope',
        'push_const("VALUE")',
        'push_const(5)',
        'make_object_here(1)',
        'pop_scope',
        'push_const("INCREMENTINNER")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENTINNER)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INNER)',
        'get_member(VALUE)',
        'ret',
      ]);
    shqlBoth('Method should have access to closure variables', 'outerVar := 100; obj := OBJECT{x: 10, addOuter: () => x + outerVar}; obj.addOuter()', 110, [
        'push_const(100)',
        'store_var(OUTERVAR)',
        'load_var(OUTERVAR)',
        'pop',
        'push_scope',
        'push_const("X")',
        'push_const(10)',
        'push_const("ADDOUTER")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ADDOUTER)',
        'call(0)',
        'ret',
      ]);
    shqlBoth('Method parameters should shadow object members', 'obj := OBJECT{x: 10, useParam: (x) => x}; obj.useParam(42)', 42, [
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
    shqlBoth('Should support method calling another method', 'obj := OBJECT{x: 10, getX: () => x, doubleX: () => getX() * 2}; obj.doubleX()', 20, [
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

    shqlBoth('Should create object with counter and multiple methods', '''
          obj := OBJECT{
            count: 0,
            increment: () => count := count + 1,
            decrement: () => count := count - 1,
            getCount: () => count
          };
          obj.increment();
          obj.increment();
          obj.decrement();
          obj.getCount()
          ''', 1, [
        'push_scope',
        'push_const("COUNT")',
        'push_const(0)',
        'push_const("INCREMENT")',
        'make_closure(.__lambda_0)',
        'push_const("DECREMENT")',
        'make_closure(.__lambda_1)',
        'push_const("GETCOUNT")',
        'make_closure(.__lambda_2)',
        'make_object_here(4)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(INCREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(DECREMENT)',
        'call(0)',
        'pop',
        'load_var(OBJ)',
        'get_member(GETCOUNT)',
        'call(0)',
        'ret',
      ]);
  });

  group('THIS self-reference in OBJECT', () {
    shqlBoth('THIS resolves to the object itself', '''
          obj := OBJECT{x: 10, getThis: () => THIS};
          obj.getThis().x
        ''', 10, [
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

    shqlBoth('THIS.field works for dot access', '''
          obj := OBJECT{x: 42, getX: () => THIS.x};
          obj.getX()
        ''', 42, [
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

    shqlBoth('THIS enables fluent/builder pattern', '''
          builder := OBJECT{
            value: 0,
            setValue: (v) => BEGIN value := v; RETURN THIS; END
          };
          builder.setValue(99).value
        ''', 99, [
        'push_scope',
        'push_const("VALUE")',
        'push_const(0)',
        'push_const("SETVALUE")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'store_var(BUILDER)',
        'load_var(BUILDER)',
        'pop',
        'load_var(BUILDER)',
        'get_member(SETVALUE)',
        'push_const(99)',
        'call(1)',
        'get_member(VALUE)',
        'ret',
      ]);

    shqlBoth('Nested objects have independent THIS — inner', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  outer.inner.getName()
''', 'inner', [
        'push_scope',
        'push_const("NAME")',
        'push_const("outer")',
        'push_const("INNER")',
        'push_scope',
        'push_const("NAME")',
        'push_const("inner")',
        'push_const("GETNAME")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'push_const("GETNAME")',
        'make_closure(.__lambda_1)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(OUTER)',
        'load_var(OUTER)',
        'pop',
        'load_var(OUTER)',
        'get_member(INNER)',
        'get_member(GETNAME)',
        'call(0)',
        'ret',
      ]);
    shqlBoth('Nested objects have independent THIS — outer', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  outer.getName()
''', 'outer', [
        'push_scope',
        'push_const("NAME")',
        'push_const("outer")',
        'push_const("INNER")',
        'push_scope',
        'push_const("NAME")',
        'push_const("inner")',
        'push_const("GETNAME")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'push_const("GETNAME")',
        'make_closure(.__lambda_1)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(OUTER)',
        'load_var(OUTER)',
        'pop',
        'load_var(OUTER)',
        'get_member(GETNAME)',
        'call(0)',
        'ret',
      ]);

    shqlBoth('THIS is mutable (can be reassigned)', '''
          obj := OBJECT{x: 10, getX: () => THIS.x};
          obj.getX()
        ''', 10, [
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

  group('Cross-object member access', () {
    shqlBoth('Object B method can access Object A members via global', '''
          A := OBJECT{
            x: 10,
            count: 0,
            SET_COUNT: (v) => BEGIN count := v; END
          };
          B := OBJECT{
            notify: () => BEGIN
              A.SET_COUNT(A.x + 5);
            END
          };
          B.notify();
          A.count
        ''', 15, [
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

    shqlBoth('Field name colliding with global name (case-insensitive) from external scope', '''
          Filters := OBJECT{
            filters: [10, 20, 30],
            filter_counts: [],
            SET_FILTER_COUNTS: (value) => BEGIN
              filter_counts := value;
            END
          };
          Heroes := OBJECT{
            notify: () => BEGIN
              Filters.SET_FILTER_COUNTS(Filters.filter_counts);
            END
          };
          Heroes.notify();
          Filters.filter_counts
        ''', [], [
        'push_scope',
        'push_const("FILTERS")',
        'push_const(10)',
        'push_const(20)',
        'push_const(30)',
        'make_list(3)',
        'push_const("FILTER_COUNTS")',
        'make_list(0)',
        'push_const("SET_FILTER_COUNTS")',
        'make_closure(.__lambda_0)',
        'make_object_here(3)',
        'pop_scope',
        'store_var(FILTERS)',
        'load_var(FILTERS)',
        'pop',
        'push_scope',
        'push_const("NOTIFY")',
        'make_closure(.__lambda_1)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(HEROES)',
        'load_var(HEROES)',
        'pop',
        'load_var(HEROES)',
        'get_member(NOTIFY)',
        'call(0)',
        'pop',
        'load_var(FILTERS)',
        'get_member(FILTER_COUNTS)',
        'ret',
      ]);
  });

  group('Null value handling', () {
    shqlBoth('Should distinguish between undefined and null variables', 'x := null; x', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    shqlBoth('Should allow null in expressions', 'x := null; y := 5; x = null', true, [
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
    shqlBoth('Should allow calling functions with null arguments', 'f(x) := x; f(null)', null, [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'push_const(null)',
        'call(1)',
        'ret',
      ]);
    shqlBoth('Should access object members that are null', 'obj := OBJECT{title: null}; obj.title', null, [
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
    shqlBoth('Should call object methods that return null', 'obj := OBJECT{getNull: () => null}; obj.getNull()', null, [
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
    shqlBoth('Should allow assigning null from map/list access', 'posts := [{"title": null}]; title := posts[0]["title"]; title', null, [
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
    shqlBoth('Should distinguish null value from missing key in map', 'm := {"a": null}; m["a"]', null, [
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

  group('Object literal with standalone lambda values', () {
    // These tests verify that lambda values stored in an OBJECT can be
    // retrieved and called from outside the object, with parameters binding
    // correctly (not referencing object members).

    shqlBoth('Parenthesized param — simple value', 'obj := OBJECT{accessor: (x) => x + 1}; obj.accessor(5)', 6, [
        'push_scope',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ACCESSOR)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);
    shqlBoth('Unparenthesized param — simple value', 'obj := OBJECT{accessor: x => x + 1}; obj.accessor(5)', 6, [
        'push_scope',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(OBJ)',
        'load_var(OBJ)',
        'pop',
        'load_var(OBJ)',
        'get_member(ACCESSOR)',
        'push_const(5)',
        'call(1)',
        'ret',
      ]);

    shqlBoth('Parenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: (p) => p.name}; '
        "meta.getName(person)", 'Alice', [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'make_object_here(1)',
        'pop_scope',
        'store_var(PERSON)',
        'load_var(PERSON)',
        'pop',
        'push_scope',
        'push_const("GETNAME")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(META)',
        'load_var(META)',
        'pop',
        'load_var(META)',
        'get_member(GETNAME)',
        'load_var(PERSON)',
        'call(1)',
        'ret',
      ]);

    shqlBoth('Unparenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: p => p.name}; '
        "meta.getName(person)", 'Alice', [
        'push_scope',
        'push_const("NAME")',
        'push_const("Alice")',
        'make_object_here(1)',
        'pop_scope',
        'store_var(PERSON)',
        'load_var(PERSON)',
        'pop',
        'push_scope',
        'push_const("GETNAME")',
        'make_closure(.__lambda_0)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(META)',
        'load_var(META)',
        'pop',
        'load_var(META)',
        'get_member(GETNAME)',
        'load_var(PERSON)',
        'call(1)',
        'ret',
      ]);

    shqlBothStdlib('Lambda calling NVL with parameter',
        'GET(hero, f, default) := NVL(hero, f, default); '
        'meta := OBJECT{accessor: (hero) => GET(hero, h => h.name, "none")}; '
        "person := OBJECT{name: \"Bob\"}; "
        "meta.accessor(person)", 'Bob', [
        'make_closure(.__GET_0)',
        'store_var(GET)',
        'load_var(GET)',
        'pop',
        'push_scope',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_1)',
        'make_object_here(1)',
        'pop_scope',
        'store_var(META)',
        'load_var(META)',
        'pop',
        'push_scope',
        'push_const("NAME")',
        'push_const("Bob")',
        'make_object_here(1)',
        'pop_scope',
        'store_var(PERSON)',
        'load_var(PERSON)',
        'pop',
        'load_var(META)',
        'get_member(ACCESSOR)',
        'load_var(PERSON)',
        'call(1)',
        'ret',
      ]);

    shqlBoth('Lambda stored in list of OBJECTs',
        'fields := [OBJECT{prop: "x", accessor: (v) => v + 10}]; '
        'fields[0].accessor(5)', 15, [
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

    shqlBoth('Iterating OBJECT list and calling stored lambdas',
        'fields := ['
        '  OBJECT{prop: "a", accessor: (v) => v + 1},'
        '  OBJECT{prop: "b", accessor: (v) => v * 2}'
        ']; '
        'f0 := fields[0]; f1 := fields[1]; '
        'f0.accessor(10) + f1.accessor(10)', 31, [
        'push_scope',
        'push_const("PROP")',
        'push_const("a")',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_0)',
        'make_object_here(2)',
        'pop_scope',
        'push_scope',
        'push_const("PROP")',
        'push_const("b")',
        'push_const("ACCESSOR")',
        'make_closure(.__lambda_1)',
        'make_object_here(2)',
        'pop_scope',
        'make_list(2)',
        'store_var(FIELDS)',
        'load_var(FIELDS)',
        'pop',
        'load_var(FIELDS)',
        'push_const(0)',
        'get_index',
        'store_var(F0)',
        'load_var(F0)',
        'pop',
        'load_var(FIELDS)',
        'push_const(1)',
        'get_index',
        'store_var(F1)',
        'load_var(F1)',
        'pop',
        'load_var(F0)',
        'get_member(ACCESSOR)',
        'push_const(10)',
        'call(1)',
        'jump_null(43)',
        'load_var(F1)',
        'get_member(ACCESSOR)',
        'push_const(10)',
        'call(1)',
        'jump_null(42)',
        'add',
        'jump(45)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);

    shqlBothStdlib('TRIM strips whitespace', "TRIM(\"  hello  \")", 'hello', [
        'load_var(TRIM)',
        'push_const("  hello  ")',
        'call(1)',
        'ret',
      ]);

    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns true for null', 'IS_NULL_OR_WHITESPACE(null)', true, [
        'load_var(IS_NULL_OR_WHITESPACE)',
        'push_const(null)',
        'call(1)',
        'ret',
      ]);
    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns true for whitespace-only', 'IS_NULL_OR_WHITESPACE("   ")', true, [
        'load_var(IS_NULL_OR_WHITESPACE)',
        'push_const("   ")',
        'call(1)',
        'ret',
      ]);
    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns false for non-blank string', 'IS_NULL_OR_WHITESPACE("batman")', false, [
        'load_var(IS_NULL_OR_WHITESPACE)',
        'push_const("batman")',
        'call(1)',
        'ret',
      ]);

    shqlBoth('Parenthesised IF-THEN-ELSE as value in map literal',
        'x := 1; '
        'obj := {"label": (IF x = 1 THEN "one" ELSE "other"), "score": 42}; '
        "obj[\"label\"]", 'one', [
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

    shqlBoth('Parenthesised IF-THEN-ELSE as value in list of maps',
        'q := "batman"; '
        r'''result := [{"type": "Text", "data": (IF q <> "" THEN "no match: " + q ELSE "No match")}]; '''
        "result[0][\"data\"]", 'no match: batman', [
        'push_const("batman")',
        'store_var(Q)',
        'load_var(Q)',
        'pop',
        'push_const("type")',
        'push_const("Text")',
        'push_const("data")',
        'load_var(Q)',
        'push_const("")',
        'cmp_neq',
        'jump_false(21)',
        'push_const("no match: ")',
        'jump_null(18)',
        'load_var(Q)',
        'jump_null(17)',
        'add',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'jump(22)',
        'push_const("No match")',
        'make_map(2)',
        'make_list(1)',
        'store_var(RESULT)',
        'load_var(RESULT)',
        'pop',
        'load_var(RESULT)',
        'push_const(0)',
        'get_index',
        'push_const("data")',
        'get_index',
        'ret',
      ]);
  });

  // Regression tests: two sequential IF statements where the first IF's THEN
  // body is RETURN with a deeply nested JSON structure (like herodex.shql
  // GENERATE_SAVED_HEROES_CARDS). Caused "Expected THEN after IF condition".
  group('Two sequential IFs — first RETURN with nested JSON', () {
    shqlBoth('Two simple IFs in BEGIN — baseline',
        'f() := BEGIN '
        '    IF 1 = 0 THEN RETURN "first"; '
        '    IF 1 = 1 THEN RETURN "second"; '
        '    RETURN "third"; '
        'END; '
        "f()", 'second', [
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);

    shqlBoth('First IF RETURN with one-level map, second IF fires',
        'heroes := []; '
        'f() := BEGIN '
        '    IF 1 = 0 THEN '
        '        RETURN [{"type": "A", "data": "empty"}]; '
        '    IF 1 = 1 THEN '
        '        RETURN [{"type": "B", "data": "match"}]; '
        '    RETURN []; '
        'END; '
        'f()', [{'type': 'B', 'data': 'match'}], [
        'make_list(0)',
        'store_var(HEROES)',
        'load_var(HEROES)',
        'pop',
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);

    shqlBoth('First IF RETURN with two-level nesting, second IF parses',
        'heroes := []; '
        'displayed := []; '
        'idx := -1; '
        'f() := BEGIN '
        '    IF 1 = 0 THEN '
        '        RETURN [{"type": "Center", "child": {"type": "Text", "props": {"data": "Empty"}}}]; '
        '    IF 1 = 1 AND idx >= 0 THEN '
        '        RETURN [{"type": "Text", "props": {"data": "No match"}}]; '
        '    RETURN []; '
        'END; '
        'f()', [], [
        'make_list(0)',
        'store_var(HEROES)',
        'load_var(HEROES)',
        'pop',
        'make_list(0)',
        'store_var(DISPLAYED)',
        'load_var(DISPLAYED)',
        'pop',
        'push_const(1)',
        'jump_null(11)',
        'neg',
        'store_var(IDX)',
        'load_var(IDX)',
        'pop',
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);

    shqlBoth('First IF RETURN with three-level nesting, second IF parses',
        'heroes := []; '
        'displayed := []; '
        'idx := -1; '
        'f() := BEGIN '
        '    IF 1 = 0 THEN '
        '        RETURN [{"type": "Center", "child": {"type": "Column", "props": {"children": [{"type": "Icon", "props": {"icon": "x", "size": 64}}, {"type": "Text", "props": {"data": "No heroes"}}]}}}]; '
        '    IF 1 = 1 AND idx >= 0 THEN '
        '        RETURN [{"type": "Text", "props": {"data": "No match"}}]; '
        '    RETURN []; '
        'END; '
        'f()', [], [
        'make_list(0)',
        'store_var(HEROES)',
        'load_var(HEROES)',
        'pop',
        'make_list(0)',
        'store_var(DISPLAYED)',
        'load_var(DISPLAYED)',
        'pop',
        'push_const(1)',
        'jump_null(11)',
        'neg',
        'store_var(IDX)',
        'load_var(IDX)',
        'pop',
        'make_closure(.__F_0)',
        'store_var(F)',
        'load_var(F)',
        'pop',
        'load_var(F)',
        'call(0)',
        'ret',
      ]);

    shqlBothStdlib('GENERATE_SAVED_HEROES_CARDS with no conditions', r'''
_heroes := [];
_displayed_heroes := [];
_active_filter_index := -1;
_current_query := '';
GENERATE_SAVED_HEROES_CARDS() := BEGIN
    IF 1 = 0 THEN
        RETURN [{"type": "Center", "child": {"type": "Column", "props": {"mainAxisAlignment": "center", "children": [{"type": "Icon", "props": {"icon": "bookmark_border", "size": 64, "color": "0xFF9E9E9E"}}, {"type": "SizedBox", "props": {"height": 16}}, {"type": "Text", "props": {"data": "No heroes saved yet", "style": {"fontSize": 18}}}, {"type": "SizedBox", "props": {"height": 8}}, {"type": "Text", "props": {"data": "Search and save heroes to build your database!", "style": {"color": "0xFF9E9E9E"}}}]}}}];
    IF 1 = 0 AND (_active_filter_index >= 0 OR NOT (IS_NULL_OR_WHITESPACE(_current_query))) THEN BEGIN
        RETURN [{"type": "Center", "child": {"type": "Text", "props": {"data": "No match", "style": {"fontSize": 16, "color": "0xFF757575"}}}}];
    END;
    RETURN [];
END;
GENERATE_SAVED_HEROES_CARDS()
''', [], [
        'make_list(0)',
        'store_var(_HEROES)',
        'load_var(_HEROES)',
        'pop',
        'make_list(0)',
        'store_var(_DISPLAYED_HEROES)',
        'load_var(_DISPLAYED_HEROES)',
        'pop',
        'push_const(1)',
        'jump_null(11)',
        'neg',
        'store_var(_ACTIVE_FILTER_INDEX)',
        'load_var(_ACTIVE_FILTER_INDEX)',
        'pop',
        'push_const("")',
        'store_var(_CURRENT_QUERY)',
        'load_var(_CURRENT_QUERY)',
        'pop',
        'make_closure(.__GENERATE_SAVED_HEROES_CARDS_0)',
        'store_var(GENERATE_SAVED_HEROES_CARDS)',
        'load_var(GENERATE_SAVED_HEROES_CARDS)',
        'pop',
        'load_var(GENERATE_SAVED_HEROES_CARDS)',
        'call(0)',
        'ret',
      ]);
  });

  group('IF without ELSE branch', () {
    shqlBoth('IF FALSE THEN returns null', 'IF FALSE THEN "FOO"', null, [
        'push_const(false)',
        'jump_false(4)',
        'push_const("FOO")',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('IF TRUE THEN returns value', "IF TRUE THEN 'FOO'", 'FOO', [
        'push_const(true)',
        'jump_false(4)',
        'push_const("FOO")',
        'jump(5)',
        'push_const(null)',
        'ret',
      ]);
  });

  group('IF with ELSE branch', () {
    shqlBoth('IF true branch', 'IF 1<10 THEN 42 ELSE 0', 42, [
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
    shqlBoth('IF false branch', 'IF 10<1 THEN 42 ELSE 0', 0, [
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

  group('WHILE loop result', () {
    shqlBoth('WHILE that never executes returns null', 'WHILE FALSE DO TRUE', null, [
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
    shqlBoth('WHILE returns last body expression', 'x := 0; WHILE x < 3 DO BEGIN x := x + 1; x^2 END', 9, [
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

  group('REPEAT loop result', () {
    shqlBoth('REPEAT returns last body expression', 'x := 0; REPEAT BEGIN x := x + 1; x^2 END UNTIL x >= 3', 9, [
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

  group('IF condition ending with parenthesised sub-expression', () {
    // Regression: the implicit-multiplication check consumed THEN as an
    // identifier after a single-element tuple, e.g. `AND (expr) THEN` would
    // swallow THEN, causing "Expected THEN after IF condition".
    shqlBoth('IF x AND (y) THEN evaluates correctly', "IF 1 = 1 AND (2 = 2) THEN \"yes\" ELSE \"no\"", 'yes', [
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
    shqlBoth('IF x AND (y) THEN — false branch', "IF 1 = 1 AND (2 = 3) THEN \"yes\" ELSE \"no\"", 'no', [
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

  group('Implicit multiplication with value-expression keywords', () {
    shqlBoth('(3)IF FALSE THEN 2 ELSE 3 = 9', '(3)IF FALSE THEN 2 ELSE 3', 9, [
        'push_const(3)',
        'jump_null(11)',
        'push_const(false)',
        'jump_false(6)',
        'push_const(2)',
        'jump(7)',
        'push_const(3)',
        'jump_null(10)',
        'mul',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('(3)IF TRUE THEN 2 ELSE 0 = 6', '(3)IF TRUE THEN 2 ELSE 0', 6, [
        'push_const(3)',
        'jump_null(11)',
        'push_const(true)',
        'jump_false(6)',
        'push_const(2)',
        'jump(7)',
        'push_const(0)',
        'jump_null(10)',
        'mul',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
  });

  group('(expr) followed by infix operator is NOT implicit multiplication', () {
    // (5)-3 must be subtraction (= 2), not 5 * (-3) = -15.
    // (5)+3 must be addition  (= 8), not 5 * (+3) =  15.
    shqlBoth('(5)-3 = 2', '(5)-3', 2, [
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
    shqlBoth('(5)+3 = 8', '(5)+3', 8, [
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

  group('Null-aware arithmetic', () {
    shqlBoth('null+number is null', 'NULL+5', null, [
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
    shqlBoth('number+null is null', '5+NULL', null, [
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
    shqlBoth('null-number is null', 'NULL-5', null, [
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
    shqlBoth('null*number is null', 'NULL*5', null, [
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
    shqlBoth('null/number is null', 'NULL/5', null, [
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
    shqlBoth('null^number is null', 'NULL^2', null, [
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

  // Null-aware relational operators (>, <, >=, <=) return null when either
  // operand is null. Boolean operators (AND, OR, XOR) must treat null as
  // falsy — Dart's `null != 0` is `true`, but logically null means
  // "unknown / not applicable" and must not satisfy a condition.
  group('Null-aware relational operators return null', () {
    shqlBoth('null > number returns null', 'x := null; x > 5', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_gt',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('null < number returns null', 'x := null; x < 5', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_lt',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('null >= number returns null', 'x := null; x >= 5', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_gte',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('null <= number returns null', 'x := null; x <= 5', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_lte',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    shqlBoth('number > null returns null', 'x := null; 5 > x', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(5)',
        'jump_null(11)',
        'load_var(X)',
        'jump_null(10)',
        'cmp_gt',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
  });

  group('AND treats null as falsy', () {
    shqlBoth('null AND true is false', 'x := null; x AND TRUE', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(true)',
        'log_and',
        'ret',
      ]);
    shqlBoth('true AND null is false', 'x := null; TRUE AND x', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(true)',
        'load_var(X)',
        'log_and',
        'ret',
      ]);
    shqlBoth('null AND false is false', 'x := null; x AND FALSE', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(false)',
        'log_and',
        'ret',
      ]);
    shqlBoth('(null > 5) AND true is false', 'x := null; (x > 5) AND TRUE', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_gt',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(true)',
        'log_and',
        'ret',
      ]);
    shqlBoth('(null > 5) AND (3 > 0) is false', 'x := null; (x > 5) AND (3 > 0)', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(11)',
        'push_const(5)',
        'jump_null(10)',
        'cmp_gt',
        'jump(13)',
        'pop',
        'pop',
        'push_const(null)',
        'push_const(3)',
        'jump_null(20)',
        'push_const(0)',
        'jump_null(19)',
        'cmp_gt',
        'jump(22)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
  });

  group('OR treats null as falsy', () {
    shqlBoth('null OR true is true', 'x := null; x OR TRUE', true, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(true)',
        'log_or',
        'ret',
      ]);
    shqlBoth('null OR false is false', 'x := null; x OR FALSE', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(false)',
        'log_or',
        'ret',
      ]);
    shqlBoth('true OR null is true', 'x := null; TRUE OR x', true, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(true)',
        'load_var(X)',
        'log_or',
        'ret',
      ]);
    shqlBoth('false OR null is false', 'x := null; FALSE OR x', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(false)',
        'load_var(X)',
        'log_or',
        'ret',
      ]);
  });

  group('NOT with null', () {
    shqlBoth('NOT null returns null (null-aware unary)', 'x := null; NOT x', null, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'jump_null(7)',
        'log_not',
        'ret',
      ]);
  });

  group('XOR treats null as falsy', () {
    shqlBoth('null XOR true is true', 'x := null; x XOR TRUE', true, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(true)',
        'log_and',
        'push_const(true)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
    shqlBoth('null XOR false is false', 'x := null; x XOR FALSE', false, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'push_const(true)',
        'log_and',
        'push_const(false)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
    shqlBoth('true XOR null is true', 'x := null; TRUE XOR x', true, [
        'push_const(null)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'push_const(true)',
        'push_const(true)',
        'log_and',
        'load_var(X)',
        'push_const(true)',
        'log_and',
        'cmp_neq',
        'ret',
      ]);
  });

  // The actual Giants bug: (null > avg + 2 * stdev) AND (stdev > 0)
  // should be false, not true.
  group('Giants predicate scenario — null height in boolean context', () {
    shqlBoth('null height with positive stdev should not match',
        'height := null; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', false, [
        'push_const(null)',
        'store_var(HEIGHT)',
        'load_var(HEIGHT)',
        'pop',
        'push_const(1.78)',
        'store_var(AVG)',
        'load_var(AVG)',
        'pop',
        'push_const(0.2)',
        'store_var(STDEV)',
        'load_var(STDEV)',
        'pop',
        'load_var(HEIGHT)',
        'jump_null(35)',
        'load_var(AVG)',
        'jump_null(29)',
        'push_const(2)',
        'jump_null(23)',
        'load_var(STDEV)',
        'jump_null(22)',
        'mul',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(28)',
        'add',
        'jump(31)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(34)',
        'cmp_gt',
        'jump(37)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(STDEV)',
        'jump_null(44)',
        'push_const(0)',
        'jump_null(43)',
        'cmp_gt',
        'jump(46)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    shqlBoth('tall height with positive stdev should match',
        'height := 2.5; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', true, [
        'push_const(2.5)',
        'store_var(HEIGHT)',
        'load_var(HEIGHT)',
        'pop',
        'push_const(1.78)',
        'store_var(AVG)',
        'load_var(AVG)',
        'pop',
        'push_const(0.2)',
        'store_var(STDEV)',
        'load_var(STDEV)',
        'pop',
        'load_var(HEIGHT)',
        'jump_null(35)',
        'load_var(AVG)',
        'jump_null(29)',
        'push_const(2)',
        'jump_null(23)',
        'load_var(STDEV)',
        'jump_null(22)',
        'mul',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(28)',
        'add',
        'jump(31)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(34)',
        'cmp_gt',
        'jump(37)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(STDEV)',
        'jump_null(44)',
        'push_const(0)',
        'jump_null(43)',
        'cmp_gt',
        'jump(46)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    shqlBoth('short height with positive stdev should not match',
        'height := 1.7; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', false, [
        'push_const(1.7)',
        'store_var(HEIGHT)',
        'load_var(HEIGHT)',
        'pop',
        'push_const(1.78)',
        'store_var(AVG)',
        'load_var(AVG)',
        'pop',
        'push_const(0.2)',
        'store_var(STDEV)',
        'load_var(STDEV)',
        'pop',
        'load_var(HEIGHT)',
        'jump_null(35)',
        'load_var(AVG)',
        'jump_null(29)',
        'push_const(2)',
        'jump_null(23)',
        'load_var(STDEV)',
        'jump_null(22)',
        'mul',
        'jump(25)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(28)',
        'add',
        'jump(31)',
        'pop',
        'pop',
        'push_const(null)',
        'jump_null(34)',
        'cmp_gt',
        'jump(37)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(STDEV)',
        'jump_null(44)',
        'push_const(0)',
        'jump_null(43)',
        'cmp_gt',
        'jump(46)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
  });

  group('STATS() stdlib function', () {
    shqlBothStdlib('returns zero object for empty list', r'''
      __s := STATS([], x => x);
      __s.COUNT = 0 AND __s.AVG = 0 AND __s.STDEV = 0 AND __s.SUM = 0
    ''', true, [
        'load_var(STATS)',
        'make_list(0)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'store_var(__S)',
        'load_var(__S)',
        'pop',
        'load_var(__S)',
        'get_member(COUNT)',
        'push_const(0)',
        'cmp_eq',
        'load_var(__S)',
        'get_member(AVG)',
        'push_const(0)',
        'cmp_eq',
        'log_and',
        'load_var(__S)',
        'get_member(STDEV)',
        'push_const(0)',
        'cmp_eq',
        'log_and',
        'load_var(__S)',
        'get_member(SUM)',
        'push_const(0)',
        'cmp_eq',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('avg of single value equals that value',
        'STATS([42], x => x).AVG', 42, [
        'load_var(STATS)',
        'push_const(42)',
        'make_list(1)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'get_member(AVG)',
        'ret',
      ]);
    shqlBothStdlib('stdev of single value is zero',
        'STATS([42], x => x).STDEV', 0, [
        'load_var(STATS)',
        'push_const(42)',
        'make_list(1)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'get_member(STDEV)',
        'ret',
      ]);
    shqlBothStdlib('avg, sum, count of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      __s.AVG > 3.999 AND __s.AVG < 4.001 AND
             __s.SUM > 11.999 AND __s.SUM < 12.001 AND
             __s.COUNT = 3
    ''', true, [
        'load_var(STATS)',
        'push_const(2)',
        'push_const(4)',
        'push_const(6)',
        'make_list(3)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'store_var(__S)',
        'load_var(__S)',
        'pop',
        'load_var(__S)',
        'get_member(AVG)',
        'jump_null(18)',
        'push_const(3.999)',
        'jump_null(17)',
        'cmp_gt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(__S)',
        'get_member(AVG)',
        'jump_null(28)',
        'push_const(4.001)',
        'jump_null(27)',
        'cmp_lt',
        'jump(30)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(SUM)',
        'jump_null(39)',
        'push_const(11.999)',
        'jump_null(38)',
        'cmp_gt',
        'jump(41)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(SUM)',
        'jump_null(50)',
        'push_const(12.001)',
        'jump_null(49)',
        'cmp_lt',
        'jump(52)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(COUNT)',
        'push_const(3)',
        'cmp_eq',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('min and max of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      __s.MIN > 1.999 AND __s.MIN < 2.001 AND
             __s.MAX > 5.999 AND __s.MAX < 6.001
    ''', true, [
        'load_var(STATS)',
        'push_const(2)',
        'push_const(4)',
        'push_const(6)',
        'make_list(3)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'store_var(__S)',
        'load_var(__S)',
        'pop',
        'load_var(__S)',
        'get_member(MIN)',
        'jump_null(18)',
        'push_const(1.999)',
        'jump_null(17)',
        'cmp_gt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(__S)',
        'get_member(MIN)',
        'jump_null(28)',
        'push_const(2.001)',
        'jump_null(27)',
        'cmp_lt',
        'jump(30)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(MAX)',
        'jump_null(39)',
        'push_const(5.999)',
        'jump_null(38)',
        'cmp_gt',
        'jump(41)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(MAX)',
        'jump_null(50)',
        'push_const(6.001)',
        'jump_null(49)',
        'cmp_lt',
        'jump(52)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('population stdev of [2, 4, 6] is sqrt(8/3)', r'''
      __v := STATS([2, 4, 6], x => x).STDEV;
      __v > 1.63298 AND __v < 1.63301
    ''', true, [
        'load_var(STATS)',
        'push_const(2)',
        'push_const(4)',
        'push_const(6)',
        'make_list(3)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'get_member(STDEV)',
        'store_var(__V)',
        'load_var(__V)',
        'pop',
        'load_var(__V)',
        'jump_null(18)',
        'push_const(1.63298)',
        'jump_null(17)',
        'cmp_gt',
        'jump(20)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(__V)',
        'jump_null(27)',
        'push_const(1.63301)',
        'jump_null(26)',
        'cmp_lt',
        'jump(29)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('nulls are excluded from all calculations', r'''
      __items := [OBJECT{v: 10}, OBJECT{v: null}, OBJECT{v: 20}];
      __s := STATS(__items, x => x.V);
      __s.AVG > 14.999 AND __s.AVG < 15.001 AND __s.COUNT = 2
    ''', true, [
        'push_scope',
        'push_const("V")',
        'push_const(10)',
        'make_object_here(1)',
        'pop_scope',
        'push_scope',
        'push_const("V")',
        'push_const(null)',
        'make_object_here(1)',
        'pop_scope',
        'push_scope',
        'push_const("V")',
        'push_const(20)',
        'make_object_here(1)',
        'pop_scope',
        'make_list(3)',
        'store_var(__ITEMS)',
        'load_var(__ITEMS)',
        'pop',
        'load_var(STATS)',
        'load_var(__ITEMS)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'store_var(__S)',
        'load_var(__S)',
        'pop',
        'load_var(__S)',
        'get_member(AVG)',
        'jump_null(34)',
        'push_const(14.999)',
        'jump_null(33)',
        'cmp_gt',
        'jump(36)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(__S)',
        'get_member(AVG)',
        'jump_null(44)',
        'push_const(15.001)',
        'jump_null(43)',
        'cmp_lt',
        'jump(46)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'load_var(__S)',
        'get_member(COUNT)',
        'push_const(2)',
        'cmp_eq',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('stdev of identical values is zero',
        'STATS([5, 5, 5, 5], x => x).STDEV', 0, [
        'load_var(STATS)',
        'push_const(5)',
        'push_const(5)',
        'push_const(5)',
        'push_const(5)',
        'make_list(4)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'get_member(STDEV)',
        'ret',
      ]);
    shqlBothStdlib('accessor lambda extracts nested field', r'''
      __people := [OBJECT{height: 1.6}, OBJECT{height: 1.8}, OBJECT{height: 2.0}];
      __v := STATS(__people, p => p.HEIGHT).AVG;
      __v > 1.7999 AND __v < 1.8001
    ''', true, [
        'push_scope',
        'push_const("HEIGHT")',
        'push_const(1.6)',
        'make_object_here(1)',
        'pop_scope',
        'push_scope',
        'push_const("HEIGHT")',
        'push_const(1.8)',
        'make_object_here(1)',
        'pop_scope',
        'push_scope',
        'push_const("HEIGHT")',
        'push_const(2.0)',
        'make_object_here(1)',
        'pop_scope',
        'make_list(3)',
        'store_var(__PEOPLE)',
        'load_var(__PEOPLE)',
        'pop',
        'load_var(STATS)',
        'load_var(__PEOPLE)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'get_member(AVG)',
        'store_var(__V)',
        'load_var(__V)',
        'pop',
        'load_var(__V)',
        'jump_null(34)',
        'push_const(1.7999)',
        'jump_null(33)',
        'cmp_gt',
        'jump(36)',
        'pop',
        'pop',
        'push_const(null)',
        'load_var(__V)',
        'jump_null(43)',
        'push_const(1.8001)',
        'jump_null(42)',
        'cmp_lt',
        'jump(45)',
        'pop',
        'pop',
        'push_const(null)',
        'log_and',
        'ret',
      ]);
    shqlBothStdlib('all-null list returns zero count and zero avg', r'''
      __items := [OBJECT{v: null}, OBJECT{v: null}];
      __s := STATS(__items, x => x.V);
      __s.COUNT = 0 AND __s.AVG = 0
    ''', true, [
        'push_scope',
        'push_const("V")',
        'push_const(null)',
        'make_object_here(1)',
        'pop_scope',
        'push_scope',
        'push_const("V")',
        'push_const(null)',
        'make_object_here(1)',
        'pop_scope',
        'make_list(2)',
        'store_var(__ITEMS)',
        'load_var(__ITEMS)',
        'pop',
        'load_var(STATS)',
        'load_var(__ITEMS)',
        'make_closure(.__lambda_0)',
        'call(2)',
        'store_var(__S)',
        'load_var(__S)',
        'pop',
        'load_var(__S)',
        'get_member(COUNT)',
        'push_const(0)',
        'cmp_eq',
        'load_var(__S)',
        'get_member(AVG)',
        'push_const(0)',
        'cmp_eq',
        'log_and',
        'ret',
      ]);
  });

  shqlBoth('"Super Man" ~ r"Super\s*Man"', '"Super Man" ~ r"Supers*Man"', false, [
      'push_const("Super Man")',
      'jump_null(7)',
      'push_const("Supers*Man")',
      'jump_null(6)',
      'op_match',
      'jump(9)',
      'pop',
      'pop',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('"Batman" in ["Batman","Robin"]', '"Batman" in ["Batman","Robin"]', true, [
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
  shqlBoth('"Superman" in ["Batman","Robin"]', '"Superman" in ["Batman","Robin"]', false, [
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
  shqlBoth('"Batman" finns_i ["Batman","Robin"]', '"Batman" finns_i ["Batman","Robin"]', true, [
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
  shqlBoth('my_global := 10; ADD(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD(5)', 'my_global := 10; ADD(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD(5)', 15, [
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
  shqlBothStdlib('LOWERCASE("Robin") in ["batman","robin"]', 'LOWERCASE("Robin") in ["batman","robin"]', true, [
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
  shqlBoth('my_array := [1, 2, 3]; PUSH(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH(4)', 'my_array := [1, 2, 3]; PUSH(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH(4)', [1, 2, 3, 4], [
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
  shqlBoth('IF TRUE THEN 42', 'IF TRUE THEN 42', 42, [
      'push_const(true)',
      'jump_false(4)',
      'push_const(42)',
      'jump(5)',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('IF FALSE THEN 42', 'IF FALSE THEN 42', null, [
      'push_const(false)',
      'jump_false(4)',
      'push_const(42)',
      'jump(5)',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('x:=[10,20,30]; x[1]:=99; x[1]', 'x:=[10,20,30]; x[1]:=99; x[1]', 99, [
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
  shqlBoth('{\'a\':1,\'b\':2}', r'''
{'a':1,'b':2}
''', {'a': 1, 'b': 2}, [
      'push_const("a")',
      'push_const(1)',
      'push_const("b")',
      'push_const(2)',
      'make_map(2)',
      'ret',
    ]);
  shqlBoth('x:={\'a\':1,\'b\':2}; x[\'a\']', r'''
x:={'a':1,'b':2}; x['a']
''', 1, [
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
  shqlBoth('k:=\'name\'; {k:\'Alice\'}', r'''
k:='name'; {k:'Alice'}
''', {'name': 'Alice'}, [
      'push_const("name")',
      'store_var(K)',
      'load_var(K)',
      'pop',
      'load_var(K)',
      'push_const("Alice")',
      'make_map(1)',
      'ret',
    ]);
  shqlBoth('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.n', 'obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.n', 1, [
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
  shqlBoth('obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.inc(); obj.inc(); obj.n', 'obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.inc(); obj.inc(); obj.n', 3, [
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
  shqlBoth('first IF RETURN with map', r'''


f():=BEGIN

  IF 1=0 THEN RETURN [{"type":"A","data":"empty"}];

  IF 1=1 THEN RETURN [{"type":"B","data":"match"}];

  RETURN [];

END;

f()


''', [{'type': 'B', 'data': 'match'}], [
      'make_closure(.__F_0)',
      'store_var(F)',
      'load_var(F)',
      'pop',
      'load_var(F)',
      'call(0)',
      'ret',
    ]);
  shqlBoth('IF TRUE THEN "FOO"', 'IF TRUE THEN "FOO"', 'FOO', [
      'push_const(true)',
      'jump_false(4)',
      'push_const("FOO")',
      'jump(5)',
      'push_const(null)',
      'ret',
    ]);
  shqlBoth('obj:=OBJECT{acc:(x)=>x+1}; obj.acc(5)', 'obj:=OBJECT{acc:(x)=>x+1}; obj.acc(5)', 6, [
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
  shqlBoth('obj:=OBJECT{acc:x=>x+1}; obj.acc(5)', 'obj:=OBJECT{acc:x=>x+1}; obj.acc(5)', 6, [
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
  shqlBoth('f0:=OBJECT{accessor:(v)=>v+1}; f1:=OBJECT{accessor:(v)=>v*2}; f0.accessor(10)+f1.accessor(10)', 'f0:=OBJECT{accessor:(v)=>v+1}; f1:=OBJECT{accessor:(v)=>v*2}; f0.accessor(10)+f1.accessor(10)', 31, [
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
  shqlBoth('{"a":1}', '{"a":1}', {'a': 1}, [
      'push_const("a")',
      'push_const(1)',
      'make_map(1)',
      'ret',
    ]);

  shqlBoth('OBJECT{name:"Alice",age:30}', 'OBJECT{name:"Alice",age:30}', isA<Object>(), [
      'push_scope',
      'push_const("NAME")',
      'push_const("Alice")',
      'push_const("AGE")',
      'push_const(30)',
      'make_object_here(2)',
      'pop_scope',
      'ret',
    ]);
  shqlBoth('OBJECT{x:1}', 'OBJECT{x:1}', isA<Object>(), [
      'push_scope',
      'push_const("X")',
      'push_const(1)',
      'make_object_here(1)',
      'pop_scope',
      'ret',
    ]);
  shqlBoth('OBJECT{x:10}', 'OBJECT{x:10}', isA<Object>(), [
      'push_scope',
      'push_const("X")',
      'push_const(10)',
      'make_object_here(1)',
      'pop_scope',
      'ret',
    ]);
}
