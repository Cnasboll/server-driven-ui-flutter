/// Compiler correctness and bytecode snapshot tests.
///
/// Every test group mirrors the corresponding section of [engine_test.dart].
/// Two kinds of assertion are used:
///
///   1. **Correctness** — the compiled+executed result must equal the
///      tree-walking engine's output.
///   2. **Bytecode snapshots** — the exact instruction sequence for selected
///      programs is compared against a golden list.  When the compiler changes
///      intentionally (new optimisation, instruction reordering, etc.) update
///      the golden values here deliberately; any *unintentional* drift is then
///      caught automatically.
///
/// Not all engine tests are mirrored here:
///   - Implicit-multiplication tests (`ANSWER(2)`, `2(3)`) — the bytecode VM
///     only handles explicit `call` and cannot fall back to multiplication.
///   - `UserFunction` runtime-type check — functions compiled to bytecode are
///     [BytecodeCallable], not [UserFunction].
library;

import 'package:shql/bytecode/bytecode.dart';
import 'dart:io' show File;

import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/parser.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Compile [src], binary-round-trip the program, and execute on the VM.
///
/// Native functions (LENGTH, POW, SQRT, etc.) are bridged automatically by
/// [BytecodeInterpreter]'s constructor, so tests can call them without loading
/// stdlib.shql through the tree-walking engine.
Future<dynamic> evalBytecode(
  String src, {
  Runtime? runtime,
  ConstantsSet? cs,
  Map<String, dynamic>? boundValues,
}) {
  cs ??= Runtime.prepareConstantsSet();
  runtime ??= Runtime.prepareRuntime(cs);

  if (boundValues != null) {
    for (final e in boundValues.entries) {
      final id = runtime.identifiers.include(e.key.toUpperCase());
      runtime.globalScope.setVariable(id, e.value);
    }
  }

  final tree = Parser.parse(src, cs, sourceCode: src);
  final program = BytecodeCompiler.compile(tree, cs);
  final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
  return BytecodeInterpreter(decoded, runtime).execute('main');
}

/// Like [evalBytecode] but prepends stdlib.shql source before compiling.
///
/// Both stdlib and user code compile to bytecode in one pass so that
/// SHQL-defined stdlib functions (NVL, STATS, SORT, etc.) are available as
/// [BytecodeCallable]s rather than tree-walking [UserFunction]s.
Future<dynamic> evalBytecodeWithStdlib(String src) async {
  final cs = Runtime.prepareConstantsSet();
  final runtime = Runtime.prepareRuntime(cs);
  final stdlibCode = await File('assets/stdlib.shql').readAsString();
  final combined = '$stdlibCode\n$src';
  final tree = Parser.parse(combined, cs, sourceCode: combined);
  final program = BytecodeCompiler.compile(tree, cs);
  final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
  return BytecodeInterpreter(decoded, runtime).execute('main');
}

/// Compile [src] and return the compiled program without executing it.
BytecodeProgram compileProgram(String src) {
  final cs = Runtime.prepareConstantsSet();
  final tree = Parser.parse(src, cs, sourceCode: src);
  return BytecodeCompiler.compile(tree, cs);
}

/// Compile [src] and return the 'main' chunk for inspection.
BytecodeChunk compileMain(String src) => compileProgram(src)['main'];

// ---- Disassembler -----------------------------------------------------------

/// Set of opcodes whose operand is a constant-pool index that holds a
/// *string identifier name* (shown unquoted).
const _nameOps = {
  Opcode.loadVar,
  Opcode.storeVar,
  Opcode.getMember,
  Opcode.setMember,
};

/// Set of opcodes whose operand is a constant-pool index that holds an
/// arbitrary constant value (shown with type-appropriate formatting).
const _constOps = {Opcode.pushConst, Opcode.makeClosure};

String _fmtConst(dynamic c) {
  if (c == null) return 'null';
  if (c is String) return '"$c"';
  if (c is ChunkRef) return '.${c.name}';
  return '$c';
}

/// Return a human-readable list of instructions for [chunk].
///
/// - Name-pool ops (`load_var`, `store_var`, etc.) show the bare identifier.
/// - Const-pool ops (`push_const`, `make_closure`) show the formatted value.
/// - Jump ops show the raw target address.
/// - Count / register ops show the raw operand.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---- Arithmetic ----------------------------------------------------------

  group('Arithmetic', () {
    test('addition', () async => expect(await evalBytecode('10+2'), 12));
    test('addition and multiplication', () async =>
        expect(await evalBytecode('10+13*37+1'), 492));
    test('parenthesised multiplication', () async =>
        expect(await evalBytecode('10+13*(37+1)'), 504));
    test('subtraction', () async =>
        expect(await evalBytecode('10+13*37-1'), 490));
    test('division', () async =>
        expect(await evalBytecode('10+13*37/2-1'), 249.5));
    test('modulus', () async => expect(await evalBytecode('9%2'), 1));
    test('unary minus', () async => expect(await evalBytecode('-5+11'), 6));
    test('unary plus', () async => expect(await evalBytecode('+5+11'), 16));
    test('exponentiation', () async =>
        expect(await evalBytecode('2^10'), 1024));
    test('exponentiation in expression', () async =>
        expect(await evalBytecode('f:=x=>x^2;f(3)'), 9));
  });

  // ---- Constants -----------------------------------------------------------

  group('Constants', () {
    test('PI', () async =>
        expect(await evalBytecode('PI*2'), 3.1415926535897932 * 2));
    test('ANSWER', () async => expect(await evalBytecode('ANSWER'), 42));
    test('TRUE', () async => expect(await evalBytecode('TRUE'), true));
    test('FALSE', () async => expect(await evalBytecode('FALSE'), false));
  });

  // ---- Comparison ----------------------------------------------------------

  group('Comparison', () {
    test('equality true', () async =>
        expect(await evalBytecode('5*2 = 2+8'), true));
    test('equality false', () async =>
        expect(await evalBytecode('5*2 = 1+8'), false));
    test('not equal true (<>)', () async =>
        expect(await evalBytecode('5*2 <> 1+8'), true));
    test('not equal true (!=)', () async =>
        expect(await evalBytecode('5*2 != 1+8'), true));
    test('not equal false (<>)', () async =>
        expect(await evalBytecode('5*2 <> 2+8'), false));
    test('not equal false (!=)', () async =>
        expect(await evalBytecode('5*2 != 2+8'), false));
    test('less than true', () async =>
        expect(await evalBytecode('1<10'), true));
    test('less than false', () async =>
        expect(await evalBytecode('10<1'), false));
    test('less than or equal true', () async =>
        expect(await evalBytecode('1<=10'), true));
    test('less than or equal false', () async =>
        expect(await evalBytecode('10<=1'), false));
    test('greater than true', () async =>
        expect(await evalBytecode('10>1'), true));
    test('greater than false', () async =>
        expect(await evalBytecode('1>10'), false));
    test('greater than or equal true', () async =>
        expect(await evalBytecode('10>=1'), true));
    test('greater than or equal false', () async =>
        expect(await evalBytecode('1>=10'), false));
  });

  // ---- Logic ---------------------------------------------------------------

  group('Logic', () {
    test('AND true', () async =>
        expect(await evalBytecode('1<10 AND 2<9'), true));
    test('AND false', () async =>
        expect(await evalBytecode('1>10 AND 2<9'), false));
    test('Swedish AND (OCH)', () async =>
        expect(await evalBytecode('1<10 OCH 2<9'), true));
    test('OR true', () async =>
        expect(await evalBytecode('1>10 OR 2<9'), true));
    test('Swedish OR (ELLER)', () async =>
        expect(await evalBytecode('1>10 ELLER 2<9'), true));
    test('XOR true', () async =>
        expect(await evalBytecode('1>10 XOR 2<9'), true));
    test('XOR false', () async =>
        expect(await evalBytecode('10>1 XOR 2<9'), false));
    test('Swedish XOR (ANTINGEN_ELLER) true', () async =>
        expect(await evalBytecode('1>10 ANTINGEN_ELLER 2<9'), true));
    test('NOT truthy', () async =>
        expect(await evalBytecode('NOT 11'), false));
    test('Swedish NOT (INTE)', () async =>
        expect(await evalBytecode('INTE 11'), false));
    test('NOT with ! prefix', () async =>
        expect(await evalBytecode('!11'), false));
  });

  // ---- Pattern / membership ------------------------------------------------

  group('Pattern / membership', () {
    test('MATCH case-insensitive true', () async =>
        expect(await evalBytecode('"Batman" ~ "batman"'), true));
    test('MATCH regex true', () async =>
        expect(await evalBytecode('"Batman" ~ "bat.*"'), true));
    test('MATCH regex false', () async =>
        expect(await evalBytecode('"Robin" ~ "bat.*"'), false));
    test('MATCH with r-string', () async =>
        expect(await evalBytecode('"Super Man" ~ r"Super\\s*Man"'), true));
    test('NOT MATCH true', () async =>
        expect(await evalBytecode('"Robin" !~ "bat.*"'), true));
    test('NOT MATCH false', () async =>
        expect(await evalBytecode('"Batman" !~ "bat.*"'), false));
    test('IN list true', () async =>
        expect(await evalBytecode('"Batman" in ["Batman","Robin"]'), true));
    test('IN list false', () async =>
        expect(await evalBytecode('"Superman" in ["Batman","Robin"]'), false));
    test('Swedish IN (FINNS_I)', () async =>
        expect(await evalBytecode('"Batman" finns_i ["Batman","Robin"]'), true));
    test('IN string substring true', () async =>
        expect(await evalBytecode('"Bat" in "Batman"'), true));
    test('IN string substring false', () async =>
        expect(await evalBytecode('"bat" in "Batman"'), false));
  });

  // ---- Variables -----------------------------------------------------------

  group('Variables', () {
    test('assignment returns value', () async =>
        expect(await evalBytecode('i:=42'), 42));
    test('increment', () async =>
        expect(await evalBytecode('i:=41;i:=i+1'), 42));
    test('sequence of two expressions', () async =>
        expect(await evalBytecode('10;11'), 11));
    test('sequence with trailing semicolon', () async =>
        expect(await evalBytecode('10;11;'), 11));
    test('global variable accessed in function', () async {
      final cs = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(cs);
      expect(
        await evalBytecode(
          'my_global := 42; GET_GLOBAL() := my_global; GET_GLOBAL()',
          runtime: runtime,
          cs: cs,
        ),
        42,
      );
    });
    test('global variable modified in function', () async {
      final cs = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(cs);
      expect(
        await evalBytecode(
          'my_global := 10; ADD(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD(5)',
          runtime: runtime,
          cs: cs,
        ),
        15,
      );
    });
  });

  // ---- Native functions ---------------------------------------------------

  group('Native functions', () {
    test('SQRT(4)', () async =>
        expect(await evalBytecode('SQRT(4)'), 2.0));
    test('POW(2,2)', () async =>
        expect(await evalBytecode('POW(2,2)'), 4.0));
    test('POW(2,2)+SQRT(4)', () async =>
        expect(await evalBytecode('POW(2,2)+SQRT(4)'), 6.0));
    test('SQRT(POW(2,2))', () async =>
        expect(await evalBytecode('SQRT(POW(2,2))'), 2.0));
    test('SQRT(POW(2,2)+10)', () async =>
        expect(await evalBytecode('SQRT(POW(2,2)+10)'), 3.7416573867739413));
    test('LOWERCASE', () async =>
        expect(await evalBytecode('LOWERCASE("Hello")'), 'hello'));
    test('UPPERCASE', () async =>
        expect(await evalBytecode('UPPERCASE("hello")'), 'HELLO'));
    test('TRIM', () async =>
        expect(await evalBytecode('TRIM("  hello  ")'), 'hello'));
    test('STRING', () async =>
        expect(await evalBytecode('STRING(42)'), '42'));
    test('INT', () async =>
        expect(await evalBytecode('INT(3.9)'), 3));
    test('ROUND', () async =>
        expect(await evalBytecode('ROUND(3.6)'), 4));
    test('MIN', () async =>
        expect(await evalBytecode('MIN(3, 7)'), 3));
    test('MAX', () async =>
        expect(await evalBytecode('MAX(3, 7)'), 7));
    test('SUBSTRING', () async =>
        expect(await evalBytecode('SUBSTRING("hello world", 0, 5)'), 'hello'));
    test('LENGTH string', () async =>
        expect(await evalBytecode('LENGTH("hello")'), 5));
    test('LENGTH list', () async =>
        expect(await evalBytecode('LENGTH([1,2,3])'), 3));
    test('LENGTH list — stdlib-style call', () async =>
        expect(await evalBytecode('LENGTH([])'), 0));
    test('LOWERCASE IN list', () async =>
        expect(
          await evalBytecode('LOWERCASE("Robin") in ["batman","robin"]'),
          true,
        ));
    test('global array accessed in function', () async {
      expect(
        await evalBytecode(
          'my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); GET_LENGTH()',
        ),
        3,
      );
    });
    test('global array modified in function', () async {
      final result = await evalBytecode(
        'my_array := [1, 2, 3]; PUSH(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH(4)',
      );
      expect(result is List, true);
      expect((result as List).length, 4);
      expect(result[3], 4);
    });
  });

  // ---- User functions ------------------------------------------------------

  group('User functions', () {
    test('single argument', () async =>
        expect(await evalBytecode('f(x):=x*2;f(2)'), 4));
    test('two arguments', () async =>
        expect(await evalBytecode('f(a,b):=a-b;f(10,2)'), 8));
    test('recursion (factorial)', () async => expect(
        await evalBytecode(
            'fac(x):=IF x<=1 THEN 1 ELSE x*fac(x-1);fac(3)'),
        6));
    test('higher-order function', () async => expect(
        await evalBytecode(
            'sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,1,2,3)'),
        6));
    test('higher-order function 2', () async => expect(
        await evalBytecode(
            'sum(a,b):=a+b; f1(f,a,b,c):=f(a,b)+c; f1(sum,10,20,5)'),
        35));
    test('user function can access TRUE constant', () async =>
        expect(await evalBytecode('test():=TRUE;test()'), true));
  });

  // ---- Lambda expressions --------------------------------------------------

  group('Lambda expressions', () {
    test('stored lambda', () async =>
        expect(await evalBytecode('f:=x=>x^2;f(3)'), 9));
    test('anonymous lambda', () async =>
        expect(await evalBytecode('(x=>x^2)(3)'), 9));
    test('nullary anonymous lambda', () async =>
        expect(await evalBytecode('(()=>9)()'), 9));
  });

  // ---- Return statement ----------------------------------------------------

  group('Return statement', () {
    test('return in conditional', () async => expect(
        await evalBytecode(
            'f(x):=IF x%2=0 THEN RETURN x+1 ELSE RETURN x;f(2)'),
        3));
    test('block return', () async => expect(
        await evalBytecode(
            'f(x):=BEGIN IF x%2=0 THEN RETURN x+1; RETURN x; END;f(2)'),
        3));
    test('factorial with block return', () async => expect(
        await evalBytecode(
            'f(x):=BEGIN IF x<=1 THEN RETURN 1; RETURN x*f(x-1); END;f(5)'),
        120));
  });

  // ---- IF statement --------------------------------------------------------

  group('IF statement', () {
    test('if true branch', () async =>
        expect(await evalBytecode('IF 1<10 THEN 42 ELSE 0'), 42));
    test('if false branch', () async =>
        expect(await evalBytecode('IF 10<1 THEN 42 ELSE 0'), 0));
    test('if without else — true', () async =>
        expect(await evalBytecode('IF TRUE THEN 42'), 42));
    test('if without else — false (null)', () async =>
        expect(await evalBytecode('IF FALSE THEN 42'), null));
    test('IF x AND (y) THEN', () async =>
        expect(await evalBytecode('IF 1=1 AND (2=2) THEN "yes" ELSE "no"'), 'yes'));
    test('(5)-3 = 2 (not implicit mul)', () async =>
        expect(await evalBytecode('(5)-3'), 2));
    test('(5)+3 = 8 (not implicit mul)', () async =>
        expect(await evalBytecode('(5)+3'), 8));
  });

  // ---- WHILE loop ----------------------------------------------------------

  group('WHILE loop', () {
    test('basic while', () async => expect(
        await evalBytecode('x:=0; WHILE x<10 DO x:=x+1; x'), 10));
    test('break', () async => expect(
        await evalBytecode(
            'x:=0; WHILE TRUE DO BEGIN x:=x+1; IF x=10 THEN BREAK; END; x'),
        10));
    test('continue', () async => expect(
        await evalBytecode(
            'x:=0; y:=0; WHILE x<10 DO BEGIN x:=x+1; IF x%2=0 THEN CONTINUE; y:=y+1; END; y'),
        5));
  });

  // ---- FOR loop ------------------------------------------------------------

  group('FOR loop', () {
    test('basic sum 1 to 10', () async => expect(
        await evalBytecode('sum:=0; FOR i:=1 TO 10 DO sum:=sum+i; sum'), 55));
    test('step 2', () async => expect(
        await evalBytecode(
            'sum:=0; FOR i:=1 TO 10 STEP 2 DO sum:=sum+i; sum'),
        25));
    test('countdown with step -1', () async => expect(
        await evalBytecode(
            'sum:=0; FOR i:=10 TO 1 STEP -1 DO sum:=sum+i; sum'),
        55));
    test('FOR 0 TO 0 iterates once', () async => expect(
        await evalBytecode('sum:=0; FOR i:=0 TO 0 DO sum:=sum+1; sum'), 1));
    test('CONTINUE skips odd iterations', () async => expect(
        await evalBytecode(r'''
          __test():=BEGIN
            __result:=[];
            FOR __i:=0 TO 2 DO BEGIN
              IF __i=1 THEN CONTINUE;
              __result:=__result+[__i];
            END;
            RETURN __result;
          END;
          __test()
        '''),
        [0, 2]));
    test('CONTINUE with nested IF-ELSE IF', () async => expect(
        await evalBytecode(r'''
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
        '''),
        ['zero', 'after', 'skip', 'two', 'after']));
    test('CONTINUE inside nested IF-THEN-BEGIN-END', () async => expect(
        await evalBytecode(r'''
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
        '''),
        [0, 'skip', 2]));
    test('CONTINUE with ELSE IF BREAK pattern', () async => expect(
        await evalBytecode(r'''
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
        '''),
        ['skipped', 'skipped', 'skipped']));
  });

  // ---- REPEAT/UNTIL --------------------------------------------------------

  group('REPEAT/UNTIL', () {
    test('basic repeat until', () async => expect(
        await evalBytecode('x:=0; REPEAT x:=x+1 UNTIL x=10; x'), 10));
  });

  // ---- Lists ---------------------------------------------------------------

  group('Lists', () {
    test('list literal', () async =>
        expect(await evalBytecode('[1,2,3]'), [1, 2, 3]));
    test('empty list', () async =>
        expect(await evalBytecode('[]'), []));
    test('list concatenation via add', () async =>
        expect(await evalBytecode('[1,2]+[3,4]'), [1, 2, 3, 4]));
    test('index read', () async =>
        expect(await evalBytecode('x:=[10,20,30]; x[1]'), 20));
    test('index write', () async =>
        expect(await evalBytecode('x:=[10,20,30]; x[1]:=99; x[1]'), 99));
  });

  // ---- Maps ----------------------------------------------------------------

  group('Maps', () {
    test('map literal is Map', () async =>
        expect(await evalBytecode("{'a':1,'b':2}"), isA<Map>()));
    test('map index read', () async =>
        expect(await evalBytecode("x:={'a':1,'b':2}; x['a']"), 1));
    test('map index write', () async =>
        expect(
            await evalBytecode("x:={'a':1,'b':2}; x['b']:=99; x['b']"), 99));
    test('map with computed key', () async =>
        expect(await evalBytecode("k:='name'; {k:'Alice'}"), isA<Map>()));
    test('OBJECT vs map distinction', () async {
      expect(await evalBytecode('OBJECT{x:1}'), isA<Object>());
      expect(await evalBytecode("{'x':1}"), isA<Map>());
    });
    test('parenthesised IF as map value', () async =>
        expect(
          await evalBytecode(
              'x:=1; obj:={"label":(IF x=1 THEN "one" ELSE "other"),"score":42}; obj["label"]'),
          'one'));
  });

  // ---- SHQL Objects --------------------------------------------------------

  group('SHQL Objects', () {
    test('object literal is Object', () async =>
        expect(await evalBytecode('OBJECT{name:"Alice",age:30}'), isA<Object>()));
    test('member read via dot', () async =>
        expect(await evalBytecode('obj:=OBJECT{x:10,y:20}; obj.x'), 10));
    test('member write', () async =>
        expect(
            await evalBytecode('obj:=OBJECT{x:10,y:20}; obj.x:=100; obj.x'),
            100));
    test('nested object access', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{person:OBJECT{name:"Bob",age:25}}; obj.person.name'),
            'Bob'));
    test('nested member write', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{inner:OBJECT{value:5}}; obj.inner.value:=42; obj.inner.value'),
            42));
    test('counter increment', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{counter:0}; obj.counter:=obj.counter+1; obj.counter'),
            1));
    test('complex values in object', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{list:[1,2,3],sum:1+2}; obj.sum'),
            3));
    test('null member', () async =>
        expect(await evalBytecode('obj:=OBJECT{title:null}; obj.title'), null));
  });

  // ---- Object methods ------------------------------------------------------

  group('Object methods', () {
    test('read sibling field from method', () async =>
        expect(
            await evalBytecode('obj:=OBJECT{x:10,getX:()=>x}; obj.getX()'),
            10));
    test('sum two sibling fields', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,y:20,sum:()=>x+y}; obj.sum()'),
            30));
    test('mutate sibling field', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.n'),
            1));
    test('mutate multiple times', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{n:0,inc:()=>n:=n+1}; obj.inc(); obj.inc(); obj.inc(); obj.n'),
            3));
    test('method with parameter', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,add:(delta)=>x+delta}; obj.add(5)'),
            15));
    test('method with parameter mutates field', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,setX:(newX)=>x:=newX}; obj.setX(42); obj.x'),
            42));
    test('nested object from method', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{inner:OBJECT{value:5},getInnerValue:()=>inner.value}; obj.getInnerValue()'),
            5));
    test('parameter shadows sibling field', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,useParam:(x)=>x}; obj.useParam(42)'),
            42));
    test('method calling another method', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,getX:()=>x,doubleX:()=>getX()*2}; obj.doubleX()'),
            20));
    test('multiple methods: increment, decrement, get', () async =>
        expect(
            await evalBytecode('''
              obj:=OBJECT{
                count:0,
                increment:()=>count:=count+1,
                decrement:()=>count:=count-1,
                getCount:()=>count
              };
              obj.increment();
              obj.increment();
              obj.decrement();
              obj.getCount()
            '''),
            1));
    test('closure variable access from method', () async =>
        expect(
            await evalBytecode(
                'outerVar:=100; obj:=OBJECT{x:10,addOuter:()=>x+outerVar}; obj.addOuter()'),
            110));
    test('standalone lambda in object (parenthesised)', () async =>
        expect(
            await evalBytecode('obj:=OBJECT{acc:(x)=>x+1}; obj.acc(5)'),
            6));
    test('standalone lambda in object (unparenthesised)', () async =>
        expect(
            await evalBytecode('obj:=OBJECT{acc:x=>x+1}; obj.acc(5)'),
            6));
    test('lambda stored in list of objects', () async =>
        expect(
            await evalBytecode(
                'fields:=[OBJECT{prop:"x",accessor:(v)=>v+10}]; fields[0].accessor(5)'),
            15));
    test('iterating list of objects with lambdas', () async =>
        expect(
            await evalBytecode(
                'f0:=OBJECT{accessor:(v)=>v+1}; f1:=OBJECT{accessor:(v)=>v*2}; f0.accessor(10)+f1.accessor(10)'),
            31));
  });

  // ---- THIS self-reference -------------------------------------------------

  group('THIS self-reference', () {
    test('THIS resolves to the object', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:10,getThis:()=>THIS}; obj.getThis().x'),
            10));
    test('THIS.field works', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{x:42,getX:()=>THIS.x}; obj.getX()'),
            42));
    test('fluent builder pattern via THIS', () async =>
        expect(
            await evalBytecode('''
              builder:=OBJECT{
                value:0,
                setValue:(v)=>BEGIN value:=v; RETURN THIS; END
              };
              builder.setValue(99).value
            '''),
            99));
    test('nested objects have independent THIS', () async {
      expect(
        await evalBytecode('''
          outer:=OBJECT{
            name:"outer",
            inner:OBJECT{name:"inner",getName:()=>THIS.name},
            getName:()=>THIS.name
          };
          outer.inner.getName()
        '''),
        'inner',
      );
      expect(
        await evalBytecode('''
          outer:=OBJECT{
            name:"outer",
            inner:OBJECT{name:"inner",getName:()=>THIS.name},
            getName:()=>THIS.name
          };
          outer.getName()
        '''),
        'outer',
      );
    });
  });

  // ---- Cross-object member access ------------------------------------------

  group('Cross-object member access', () {
    test('Object B method modifies Object A via global', () async =>
        expect(
            await evalBytecode('''
              A:=OBJECT{x:10,count:0,SET_COUNT:(v)=>BEGIN count:=v; END};
              B:=OBJECT{notify:()=>BEGIN A.SET_COUNT(A.x+5); END};
              B.notify();
              A.count
            '''),
            15));
  });

  // ---- Null value handling -------------------------------------------------

  group('Null value handling', () {
    test('null assignment', () async =>
        expect(await evalBytecode('x:=null; x'), null));
    test('null equality', () async =>
        expect(await evalBytecode('x:=null; y:=5; x=null'), true));
    test('function with null arg', () async =>
        expect(await evalBytecode('f(x):=x; f(null)'), null));
    test('object member that is null', () async =>
        expect(
            await evalBytecode('obj:=OBJECT{title:null}; obj.title'), null));
    test('object method returning null', () async =>
        expect(
            await evalBytecode(
                'obj:=OBJECT{getNull:()=>null}; obj.getNull()'),
            null));
    test('null from map list access', () async =>
        expect(
            await evalBytecode(
                'posts:=[{"title":null}]; title:=posts[0]["title"]; title'),
            null));
    test('null value in map by key', () async =>
        expect(await evalBytecode('m:={"a":null}; m["a"]'), null));
  });

  // ---- Null-aware operators ------------------------------------------------

  group('Null-aware arithmetic', () {
    test('null+number is null', () async =>
        expect(await evalBytecode('NULL+5'), null));
    test('number+null is null', () async =>
        expect(await evalBytecode('5+NULL'), null));
    test('null-number is null', () async =>
        expect(await evalBytecode('NULL-5'), null));
    test('null*number is null', () async =>
        expect(await evalBytecode('NULL*5'), null));
    test('null/number is null', () async =>
        expect(await evalBytecode('NULL/5'), null));
    test('null^number is null', () async =>
        expect(await evalBytecode('NULL^2'), null));
    test('null < number returns null', () async =>
        expect(await evalBytecode('NULL < 5'), null));
    test('null > number returns null (boundValues)', () async =>
        expect(await evalBytecode('x > 5', boundValues: {'x': null}), null));
    test('NOT null is null', () async =>
        expect(await evalBytecode('NOT NULL'), null));
  });

  group('Null-aware relational (boundValues)', () {
    test('null > number', () async =>
        expect(await evalBytecode('x > 5', boundValues: {'x': null}), null));
    test('null < number', () async =>
        expect(await evalBytecode('x < 5', boundValues: {'x': null}), null));
    test('null >= number', () async =>
        expect(await evalBytecode('x >= 5', boundValues: {'x': null}), null));
    test('null <= number', () async =>
        expect(await evalBytecode('x <= 5', boundValues: {'x': null}), null));
    test('number > null', () async =>
        expect(await evalBytecode('5 > x', boundValues: {'x': null}), null));
  });

  group('AND/OR/XOR treat null as falsy', () {
    test('null AND true is false', () async =>
        expect(await evalBytecode('x AND TRUE', boundValues: {'x': null}), false));
    test('true AND null is false', () async =>
        expect(await evalBytecode('TRUE AND x', boundValues: {'x': null}), false));
    test('null AND false is false', () async =>
        expect(await evalBytecode('x AND FALSE', boundValues: {'x': null}), false));
    test('(null>5) AND true is false', () async =>
        expect(
            await evalBytecode('(x>5) AND TRUE', boundValues: {'x': null}),
            false));
    test('null OR true is true', () async =>
        expect(await evalBytecode('x OR TRUE', boundValues: {'x': null}), true));
    test('null OR false is false', () async =>
        expect(
            await evalBytecode('x OR FALSE', boundValues: {'x': null}), false));
    test('null XOR true is true', () async =>
        expect(await evalBytecode('x XOR TRUE', boundValues: {'x': null}), true));
    test('null XOR false is false', () async =>
        expect(
            await evalBytecode('x XOR FALSE', boundValues: {'x': null}), false));
  });

  group('NOT with null', () {
    test('NOT null returns null', () async =>
        expect(await evalBytecode('NOT x', boundValues: {'x': null}), null));
  });

  group('Giants predicate scenario', () {
    test('null height with positive stdev should not match', () async =>
        expect(
            await evalBytecode(
              '(height > avg + 2 * stdev) AND (stdev > 0)',
              boundValues: {'height': null, 'avg': 1.78, 'stdev': 0.2},
            ),
            false));
    test('tall height matches', () async =>
        expect(
            await evalBytecode(
              '(height > avg + 2 * stdev) AND (stdev > 0)',
              boundValues: {'height': 2.5, 'avg': 1.78, 'stdev': 0.2},
            ),
            true));
    test('short height does not match', () async =>
        expect(
            await evalBytecode(
              '(height > avg + 2 * stdev) AND (stdev > 0)',
              boundValues: {'height': 1.7, 'avg': 1.78, 'stdev': 0.2},
            ),
            false));
  });

  // ---- Two-sequential-IF regression ---------------------------------------

  group('Two sequential IFs — first RETURN with nested JSON', () {
    test('two simple IFs in BEGIN — baseline', () async =>
        expect(
            await evalBytecode(
              'f():=BEGIN '
              '  IF 1=0 THEN RETURN "first"; '
              '  IF 1=1 THEN RETURN "second"; '
              '  RETURN "third"; '
              'END; '
              'f()',
            ),
            'second'));
    test('first IF RETURN with one-level map, second IF fires', () async =>
        expect(
            await evalBytecode(
              'f():=BEGIN '
              '  IF 1=0 THEN RETURN [{"type":"A","data":"empty"}]; '
              '  IF 1=1 THEN RETURN [{"type":"B","data":"match"}]; '
              '  RETURN []; '
              'END; '
              'f()',
            ),
            isA<List>()));
  });

  // ---- Navigation stack pattern -------------------------------------------

  group('Navigation stack push/pop pattern', () {
    test('push twice then pop returns last', () async =>
        expect(
            await evalBytecode('''
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
            '''),
            'screen2'));
  });

  // =========================================================================
  // Bytecode snapshots (drift detection)
  //
  // These golden lists document what the compiler currently emits for a
  // selection of programs.  If you intentionally change the compiler's output,
  // update the lists below; unintentional drift will be caught automatically.
  // =========================================================================

  group('Bytecode snapshots (drift detection)', () {
    // ---- Literal -----------------------------------------------------------

    test('integer literal 42', () {
      expect(disasm(compileMain('42')), [
        'push_const(42)',
        'ret',
      ]);
    });

    test('null literal', () {
      expect(disasm(compileMain('null')), [
        'push_const(null)',
        'ret',
      ]);
    });

    // ---- Plain binary (eq/neq — not null-aware) ----------------------------

    test('1=1 (plain cmp_eq, no null checks)', () {
      expect(disasm(compileMain('1=1')), [
        'push_const(1)',
        'push_const(1)',
        'cmp_eq',
        'ret',
      ]);
    });

    test('1<>2 (plain cmp_neq)', () {
      expect(disasm(compileMain('1<>2')), [
        'push_const(1)',
        'push_const(2)',
        'cmp_neq',
        'ret',
      ]);
    });

    // ---- Null-aware binary -------------------------------------------------

    test('1+2 (null-aware add)', () {
      // _nullAwareBinary emits: lhs, null-check, rhs, null-check, op, jump,
      // pop-rhs, pop-lhs, push null; then ret.
      expect(disasm(compileMain('1+2')), [
        'push_const(1)',   // lhs
        'dup',             // null-check lhs
        'push_const(null)',
        'cmp_eq',
        'jump_true(13)',   // → .lhsNull (addr 13)
        'push_const(2)',   // rhs
        'dup',             // null-check rhs
        'push_const(null)',
        'cmp_eq',
        'jump_true(12)',   // → .rhsNull (addr 12)
        'add',
        'jump(15)',        // → .done (addr 15)
        'pop',             // .rhsNull: pop rhs
        'pop',             // .lhsNull: pop lhs
        'push_const(null)',
        'ret',             // .done
      ]);
    });

    test('2^3 (null-aware pow opcode)', () {
      expect(disasm(compileMain('2^3')), [
        'push_const(2)',
        'dup',
        'push_const(null)',
        'cmp_eq',
        'jump_true(13)',
        'push_const(3)',
        'dup',
        'push_const(null)',
        'cmp_eq',
        'jump_true(12)',
        'pow',
        'jump(15)',
        'pop',
        'pop',
        'push_const(null)',
        'ret',
      ]);
    });

    // ---- Sequence ----------------------------------------------------------

    test('sequence: 10;11', () {
      expect(disasm(compileMain('10;11')), [
        'push_const(10)',
        'pop',
        'push_const(11)',
        'ret',
      ]);
    });

    // ---- Assignment --------------------------------------------------------

    test('assignment i:=42', () {
      // compile rhs, store, reload (assignment is an expression)
      expect(disasm(compileMain('i:=42')), [
        'push_const(42)',
        'store_var(I)',
        'load_var(I)',
        'ret',
      ]);
    });

    test('variable load: x:=5;x', () {
      expect(disasm(compileMain('x:=5;x')), [
        'push_const(5)',
        'store_var(X)',
        'load_var(X)',
        'pop',
        'load_var(X)',
        'ret',
      ]);
    });

    // ---- IF-THEN-ELSE structure ---------------------------------------------

    test('IF TRUE THEN 1 ELSE 2 — structure', () {
      final instrs = disasm(compileMain('IF TRUE THEN 1 ELSE 2'));
      // condition → jump_false → then → jump → else → (done)
      expect(instrs.first, 'push_const(true)');
      expect(instrs.contains('jump_false(4)'), isTrue);
      expect(instrs.contains('push_const(1)'), isTrue);
      expect(instrs.contains('push_const(2)'), isTrue);
      expect(instrs.last, 'ret');
    });

    // ---- Function definition -----------------------------------------------

    test('function def produces two chunks', () {
      final prog = compileProgram('f(x):=x*2');
      expect(prog.chunks.length, 2);
      expect(prog.chunks.containsKey('main'), isTrue);
      // One lambda chunk named __F_0 (or similar), with param X
      final lambdaChunk = prog.chunks.values
          .firstWhere((c) => c.name != 'main');
      expect(lambdaChunk.params, ['X']);
    });

    test('lambda expression produces two chunks', () {
      final prog = compileProgram('x=>x+1');
      expect(prog.chunks.length, 2);
    });

    // ---- List literal -------------------------------------------------------

    test('list [1,2,3] structure', () {
      final instrs = disasm(compileMain('[1,2,3]'));
      expect(instrs, [
        'push_const(1)',
        'push_const(2)',
        'push_const(3)',
        'make_list(3)',
        'ret',
      ]);
    });

    test('empty list', () {
      expect(disasm(compileMain('[]')), [
        'make_list(0)',
        'ret',
      ]);
    });

    // ---- Map literal -------------------------------------------------------

    test('map {"a":1} structure', () {
      final instrs = disasm(compileMain('{"a":1}'));
      // string key evaluated as expression, then value, then make_map(1)
      expect(instrs.last, 'ret');
      expect(instrs[instrs.length - 2], 'make_map(1)');
    });

    // ---- Object literal ----------------------------------------------------

    test('OBJECT{x:10} structure', () {
      final instrs = disasm(compileMain('OBJECT{x:10}'));
      // push_scope, key "X", value 10, make_object_here(1), pop_scope
      expect(instrs.last, 'ret');
      expect(instrs[instrs.length - 2], 'pop_scope');
      expect(instrs[instrs.length - 3], 'make_object_here(1)');
      expect(instrs[0], 'push_scope');
    });

    // ---- Member access -----------------------------------------------------

    test('obj.x member access', () {
      // load_var(OBJ), get_member(X)
      final instrs = disasm(compileMain('obj.x'));
      expect(instrs, ['load_var(OBJ)', 'get_member(X)', 'ret']);
    });

    // ---- Index access ------------------------------------------------------

    test('x[0] index access', () {
      final instrs = disasm(compileMain('x[0]'));
      expect(instrs, ['load_var(X)', 'push_const(0)', 'get_index', 'ret']);
    });
  });
}
