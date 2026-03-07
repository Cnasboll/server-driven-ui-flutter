import 'dart:math';

import 'package:shql/bytecode/bytecode.dart';
import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_execution_context.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/bytecode/bytecode_parser.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/tokenizer/token.dart';
import 'package:test/test.dart';

void main() {
  // A shared Runtime — same as what the existing SHQL engine uses.
  late Runtime rt;
  setUp(() => rt = Runtime.prepareRuntime());

  // -------------------------------------------------------------------------
  // Tokeniser
  // -------------------------------------------------------------------------
  group('tokenizeBytecode', () {
    test('merges dot + identifier into directive', () {
      final tokens = tokenizeBytecode('.chunk');
      expect(tokens, hasLength(1));
      expect(tokens.first.isDirective, isTrue);
      expect(tokens.first.lexeme, '.chunk');
    });

    test('float literal does not produce a directive', () {
      final tokens = tokenizeBytecode('3.14');
      expect(tokens, hasLength(1));
      expect(tokens.first.isDirective, isFalse);
      expect(tokens.first.type, TokenTypes.floatLiteral);
    });

    test('multiple directives in one line', () {
      final tokens = tokenizeBytecode('.chunk main .constants .code');
      expect(
        tokens
            .where((t) => t.isDirective)
            .map((t) => t.lexeme)
            .toList(),
        ['.chunk', '.constants', '.code'],
      );
    });

    test('comment lines are skipped', () {
      final tokens = tokenizeBytecode('-- comment\n.chunk');
      expect(tokens, hasLength(1));
      expect(tokens.first.lexeme, '.chunk');
    });
  });

  // -------------------------------------------------------------------------
  // Parser
  // -------------------------------------------------------------------------
  group('BytecodeParser', () {
    test('parses a minimal chunk', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .constants:
    0: 42
  .code:
    push_const 0
    ret
''').parse();
      expect(prog.hasChunk('main'), isTrue);
      final chunk = prog['main'];
      expect(chunk.constants, [42]);
      expect(chunk.code[0].op, Opcode.pushConst);
      expect(chunk.code[1].op, Opcode.ret);
    });

    test('parses params', () {
      final prog = BytecodeParser.fromSource('''
.chunk square:
  .params:
    x
  .code:
    ret
''').parse();
      expect(prog['square'].params, ['x']);
    });

    test('parses negative constant', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .constants:
    0: -7
  .code:
    ret
''').parse();
      expect(prog['main'].constants[0], -7);
    });

    test('parses ChunkRef constant', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .constants:
    0: .helper
  .code:
    ret
''').parse();
      expect(prog['main'].constants[0], ChunkRef('helper'));
    });

    test('resolves forward jump label', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .constants:
    0: 1
  .code:
    push_const 0
    jump_false .done
    push_const 0
  .done:
    ret
''').parse();
      // jump_false at index 1 must resolve to index 3 (.done)
      expect(prog['main'].code[1].op, Opcode.jumpFalse);
      expect(prog['main'].code[1].operand, 3);
    });

    test('resolves backward jump (loop)', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .constants:
    0: 0
  .code:
  .loop:
    push_const 0
    jump .loop
    ret
''').parse();
      expect(prog['main'].code[1].op, Opcode.jump);
      expect(prog['main'].code[1].operand, 0);
    });

    test('parses multiple chunks', () {
      final prog = BytecodeParser.fromSource('''
.chunk main:
  .code:
    ret
.chunk helper:
  .code:
    ret
''').parse();
      expect(prog.hasChunk('main'), isTrue);
      expect(prog.hasChunk('helper'), isTrue);
    });

    test('throws on unknown opcode', () {
      expect(
        () => BytecodeParser.fromSource('''
.chunk main:
  .code:
    fly_to_moon
''').parse(),
        throwsA(isA<BytecodeParseError>()),
      );
    });

    test('throws on unresolved label', () {
      expect(
        () => BytecodeParser.fromSource('''
.chunk main:
  .code:
    jump .nowhere
''').parse(),
        throwsA(isA<BytecodeParseError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Interpreter helpers
  // -------------------------------------------------------------------------

  Future<dynamic> run(String src, [List<dynamic> args = const []]) {
    final prog = BytecodeParser.fromSource(src).parse();
    return BytecodeInterpreter(prog, rt).execute('main', args);
  }

  // -------------------------------------------------------------------------
  // Arithmetic
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — arithmetic', () {
    test('push constant and return', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 42
  .code:
    push_const 0
    ret
'''), 42);
    });

    test('addition 5 + 3 = 8', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 5
    1: 3
  .code:
    push_const 0
    push_const 1
    add
    ret
'''), 8);
    });

    test('subtraction 10 - 4 = 6', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 10
    1: 4
  .code:
    push_const 0
    push_const 1
    sub
    ret
'''), 6);
    });

    test('multiplication 6 * 7 = 42', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 6
    1: 7
  .code:
    push_const 0
    push_const 1
    mul
    ret
'''), 42);
    });

    test('negation', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 5
  .code:
    push_const 0
    neg
    ret
'''), -5);
    });

    test('(2 + 3) * 4 = 20', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 2
    1: 3
    2: 4
  .code:
    push_const 0
    push_const 1
    add
    push_const 2
    mul
    ret
'''), 20);
    });
  });

  // -------------------------------------------------------------------------
  // Variables — stored in SHQL Scope
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — variables (SHQL Scope)', () {
    test('store and load via SHQL scope', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 99
    1: x
  .code:
    push_const 0
    store_var 1
    load_var 1
    ret
'''), 99);
    });

    test('update variable', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 10
    1: x
    2: 5
  .code:
    push_const 0
    store_var 1
    load_var 1
    push_const 2
    add
    store_var 1
    load_var 1
    ret
'''), 15);
    });
  });

  // -------------------------------------------------------------------------
  // Control flow
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — control flow', () {
    test('jump_false takes else branch when condition is 0', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 0
    1: 99
    2: 42
  .code:
    push_const 0
    jump_false .else
    push_const 1
    jump .end
  .else:
    push_const 2
  .end:
    ret
'''), 42);
    });

    test('jump_false takes then branch when condition is 1', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 1
    1: 99
    2: 42
  .code:
    push_const 0
    jump_false .else
    push_const 1
    jump .end
  .else:
    push_const 2
  .end:
    ret
'''), 99);
    });

    test('loop: sum 1..5 = 15', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 0
    1: i
    2: total
    3: 1
    4: 5
  .code:
    push_const 0
    store_var 1
    push_const 0
    store_var 2
  .loop:
    load_var 1
    push_const 4
    cmp_lt
    jump_false .end
    load_var 1
    push_const 3
    add
    store_var 1
    load_var 2
    load_var 1
    add
    store_var 2
    jump .loop
  .end:
    load_var 2
    ret
'''), 15);
    });
  });

  // -------------------------------------------------------------------------
  // Scope (push_scope / pop_scope)
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — scope', () {
    test('push_scope / pop_scope: inner assignment updates outer binding', () async {
      // x is defined in outer scope; push_scope + store_var walks up and
      // updates the outer binding (same as SHQL setVariable semantics).
      expect(await run('''
.chunk main:
  .constants:
    0: 1
    1: x
    2: 2
  .code:
    push_const 0
    store_var 1
    push_scope
    push_const 2
    store_var 1
    pop_scope
    load_var 1
    ret
'''), 2);
    });
  });

  // -------------------------------------------------------------------------
  // Closures and function calls
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — closures', () {
    test('square(7) = 49', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: .square
    1: 7
  .code:
    push_const 0
    push_const 1
    call 1
    ret

.chunk square:
  .params:
    x
  .constants:
    0: x
  .code:
    load_var 0
    load_var 0
    mul
    ret
'''), 49);
    });

    test('closure captures outer scope variable', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 10
    1: base
    2: .adder
    3: 5
  .code:
    push_const 0
    store_var 1
    make_closure 2
    push_const 3
    call 1
    ret

.chunk adder:
  .params:
    n
  .constants:
    0: base
    1: n
  .code:
    load_var 0
    load_var 1
    add
    ret
'''), 15);
    });

    test('recursive GCD(48, 18) = 6', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: .gcd
    1: 48
    2: 18
  .code:
    push_const 0
    push_const 1
    push_const 2
    call 2
    ret

.chunk gcd:
  .params:
    a
    b
  .constants:
    0: b
    1: 0
    2: a
    3: .gcd
    4: a
    5: b
  .code:
    load_var 0
    push_const 1
    cmp_eq
    jump_false .recurse
    load_var 2
    ret
  .recurse:
    push_const 3
    load_var 5
    load_var 4
    load_var 5
    mod
    call 2
    ret
'''), 6);
    });
  });

  // -------------------------------------------------------------------------
  // Lists
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — lists', () {
    test('make_list builds a Dart List', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 1
    1: 2
    2: 3
  .code:
    push_const 0
    push_const 1
    push_const 2
    make_list 3
    ret
'''), [1, 2, 3]);
    });

    test('get_index retrieves element', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: 10
    1: 20
    2: 30
    3: 1
  .code:
    push_const 0
    push_const 1
    push_const 2
    make_list 3
    push_const 3
    get_index
    ret
'''), 20);
    });
  });

  // -------------------------------------------------------------------------
  // SHQL Objects
  // -------------------------------------------------------------------------
  group('BytecodeInterpreter — SHQL Objects', () {
    test('make_object produces a SHQL Object', () async {
      final result = await run('''
.chunk main:
  .constants:
    0: "name"
    1: "Alice"
  .code:
    push_const 0
    push_const 1
    make_object 1
    ret
''');
      expect(result, isA<Object>());
      // Verify via the identifier table the same way get_member does.
      final id = rt.identifiers.include('NAME');
      final raw = (result as Object).resolveIdentifier(id);
      expect(raw is Variable ? raw.value : raw, 'Alice');
    });

    test('get_member reads a SHQL Object field', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: "score"
    1: 42
    2: score
  .code:
    push_const 0
    push_const 1
    make_object 1
    get_member 2
    ret
'''), 42);
    });

    test('set_member mutates a SHQL Object field', () async {
      expect(await run('''
.chunk main:
  .constants:
    0: "x"
    1: 1
    2: obj
    3: x
    4: 99
  .code:
    push_const 0
    push_const 1
    make_object 1
    store_var 2
    load_var 2
    push_const 4
    set_member 3
    pop
    load_var 2
    get_member 3
    ret
'''), 99);
    });
  });

  // -------------------------------------------------------------------------
  // First-class functions via if-expression
  // -------------------------------------------------------------------------

  // SHQL source:
  //   f1(x) := POW(x, 2);
  //   f2(x) := x * 2;
  //   choice := INTEGER(READLINE);
  //   f := IF choice = 0 THEN f1 ELSE f2;
  //   result := f(42);
  const firstClassSrc = '''
.chunk main:
  .constants:
    0: readline
    1: integer
    2: choice
    3: 0
    4: .f1
    5: .f2
    6: f
    7: 42
    8: result
  .code:
    load_var 1
    load_var 0
    call 0
    call 1
    store_var 2
    load_var 2
    push_const 3
    cmp_eq
    jump_false .else
    make_closure 4
    jump .end
  .else:
    make_closure 5
  .end:
    store_var 6
    load_var 6
    push_const 7
    call 1
    store_var 8
    load_var 8
    ret

.chunk f1:
  .params:
    x
  .constants:
    0: pow
    1: x
    2: 2
  .code:
    load_var 0
    load_var 1
    push_const 2
    call 2
    ret

.chunk f2:
  .params:
    x
  .constants:
    0: x
    1: 2
  .code:
    load_var 0
    push_const 1
    mul
    ret
''';

  group('BytecodeInterpreter — first-class functions via if-expression', () {
    for (final (input, expected) in [('0', 1764), ('1', 84)]) {
      test('READLINE=$input → ${input == '0' ? 'f1' : 'f2'}(42) = $expected',
          () async {
        final prog = BytecodeParser.fromSource(firstClassSrc).parse();
        final interp = BytecodeInterpreter(prog, rt);
        interp.registerNative('readline', (_) => input);
        interp.registerNative('integer', (args) => int.parse(args[0] as String));
        interp.registerNative('pow', (args) => pow(args[0] as num, args[1] as num).toInt());
        expect(await interp.execute('main'), expected);
      });
    }
  });

  // -------------------------------------------------------------------------
  // Native functions
  // -------------------------------------------------------------------------

  /// Build an interpreter with [natives] pre-registered and run [src].
  Future<dynamic> runNative(
    String src,
    Map<String, dynamic Function(List<dynamic>)> natives, [
    List<dynamic> args = const [],
  ]) {
    final prog = BytecodeParser.fromSource(src).parse();
    final interp = BytecodeInterpreter(prog, rt);
    for (final e in natives.entries) {
      interp.registerNative(e.key, e.value);
    }
    return interp.execute('main', args);
  }

  group('BytecodeInterpreter — native functions', () {
    test('unary: sqrt(9) = 3.0', () async {
      expect(
        await runNative(
          '''
.chunk main:
  .constants:
    0: sqrt
    1: 9
  .code:
    load_var 0
    push_const 1
    call 1
    ret
''',
          {'sqrt': (args) => sqrt(args[0] as num)},
        ),
        3.0,
      );
    });

    test('binary: max(3, 7) = 7', () async {
      expect(
        await runNative(
          '''
.chunk main:
  .constants:
    0: maxFn
    1: 3
    2: 7
  .code:
    load_var 0
    push_const 1
    push_const 2
    call 2
    ret
''',
          {'maxFn': (args) => max(args[0] as num, args[1] as num)},
        ),
        7,
      );
    });

    test('ternary: substring("hello", 1, 4) = "ell"', () async {
      expect(
        await runNative(
          '''
.chunk main:
  .constants:
    0: substr
    1: "hello"
    2: 1
    3: 4
  .code:
    load_var 0
    push_const 1
    push_const 2
    push_const 3
    call 3
    ret
''',
          {'substr': (args) => (args[0] as String).substring(args[1] as int, args[2] as int)},
        ),
        'ell',
      );
    });

    test('native result used in arithmetic', () async {
      // sqrt(16) + 1 = 5.0
      expect(
        await runNative(
          '''
.chunk main:
  .constants:
    0: sqrt
    1: 16
    2: 1
  .code:
    load_var 0
    push_const 1
    call 1
    push_const 2
    add
    ret
''',
          {'sqrt': (args) => sqrt(args[0] as num)},
        ),
        5.0,
      );
    });

    test('throws when calling non-callable', () async {
      expect(
        () => run('''
.chunk main:
  .constants:
    0: 42
  .code:
    push_const 0
    call 0
    ret
'''),
        throwsA(isA<BytecodeRuntimeError>()),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Codec round-trips
  //
  // For each program: text → parse → encode → decode → disassemble → parse
  // → encode again.  The two byte arrays must be identical, proving a 1-1
  // mapping between the text format and the binary format (comments aside).
  // -------------------------------------------------------------------------

  /// Encode [src] to bytes, decode back, re-encode, assert both byte arrays
  /// are equal, then disassemble the decoded program, re-parse, re-encode and
  /// assert that third encoding also matches.
  void roundTrip(String description, String src) {
    test(description, () {
      final program = BytecodeParser.fromSource(src).parse();

      // binary round-trip
      final bytes1 = BytecodeEncoder.encode(program);
      final decoded = BytecodeDecoder.decode(bytes1);
      final bytes2 = BytecodeEncoder.encode(decoded);
      expect(bytes2, bytes1, reason: 'binary round-trip');

      // text round-trip (via disassembler → re-parse → re-encode)
      final text = BytecodeDisassembler.disassemble(decoded);
      final bytes3 = BytecodeEncoder.encode(BytecodeParser.fromSource(text).parse());
      expect(bytes3, bytes1, reason: 'text round-trip');
    });
  }

  group('Codec — round-trips', () {
    // SHQL: RESULT := 42
    roundTrip('minimal: push constant and return', '''
.chunk main:
  .constants:
    0: 42
  .code:
    push_const 0
    ret
''');

    // SHQL: RESULT := (2 + 3) * 4
    roundTrip('arithmetic with multiple constants', '''
.chunk main:
  .constants:
    0: 2
    1: 3
    2: 4
  .code:
    push_const 0
    push_const 1
    add
    push_const 2
    mul
    ret
''');

    // SHQL: negative constant and float
    roundTrip('negative integer and float constant', '''
.chunk main:
  .constants:
    0: -7
    1: 3.14
  .code:
    push_const 0
    push_const 1
    add
    ret
''');

    // SHQL: string constant and make_object / get_member
    roundTrip('string constants and SHQL Object', '''
.chunk main:
  .constants:
    0: "name"
    1: "Alice"
    2: name
  .code:
    push_const 0
    push_const 1
    make_object 1
    get_member 2
    ret
''');

    // SHQL: IF condition THEN ... ELSE ... (forward jumps)
    roundTrip('conditional with forward jumps', '''
.chunk main:
  .constants:
    0: 0
    1: 99
    2: 42
  .code:
    push_const 0
    jump_false 4
    push_const 1
    jump 5
    push_const 2
    ret
''');

    // SHQL: f1(x) := POW(x, 2)  /  f2(x) := x * 2  / first-class function
    roundTrip('first-class functions via if-expression', firstClassSrc);

    // SHQL: GCD recursive
    roundTrip('recursive GCD chunks', '''
.chunk main:
  .constants:
    0: .gcd
    1: 48
    2: 18
  .code:
    push_const 0
    push_const 1
    push_const 2
    call 2
    ret

.chunk gcd:
  .params:
    a
    b
  .constants:
    0: b
    1: 0
    2: a
    3: .gcd
    4: a
    5: b
  .code:
    load_var 0
    push_const 1
    cmp_eq
    jump_false 5
    load_var 2
    ret
    push_const 3
    load_var 5
    load_var 4
    load_var 5
    mod
    call 2
    ret
''');
  });

  // -------------------------------------------------------------------------
  // Cooperative threading via BytecodeExecutionContext
  // -------------------------------------------------------------------------

  /// Build a [BytecodeExecutionContext] from [src] using the shared runtime.
  BytecodeExecutionContext makeCtx(String src) {
    final prog = BytecodeParser.fromSource(src).parse();
    return BytecodeExecutionContext(BytecodeInterpreter(prog, rt));
  }

  group('BytecodeExecutionContext — cooperative threading', () {
    test('single thread runs to completion via context', () async {
      final ctx = makeCtx('''
.chunk main:
  .constants:
    0: 99
  .code:
    push_const 0
    ret
''');
      final t = ctx.spawn('main');
      await ctx.runToCompletion();
      expect(t.result, 99);
      expect(t.error, isNull);
      expect(ctx.hasRunningThreads, isFalse);
    });

    test('two threads interleave and both complete correctly (quantum=1)', () async {
      // chunk sumChunk: sum 1+2+3+4+5 = 15 via a loop (~25 instructions)
      // chunk mulChunk: 6 * 7 = 42 (immediate arithmetic)
      // quantum=1 forces one instruction per thread per round — maximum interleaving.
      final ctx = makeCtx('''
.chunk sumChunk:
  .constants:
    0: 0
    1: iVar
    2: totVar
    3: 1
    4: 5
  .code:
    push_const 0
    store_var 1
    push_const 0
    store_var 2
  .loop:
    load_var 1
    push_const 4
    cmp_lt
    jump_false .done
    load_var 1
    push_const 3
    add
    store_var 1
    load_var 2
    load_var 1
    add
    store_var 2
    jump .loop
  .done:
    load_var 2
    ret

.chunk mulChunk:
  .constants:
    0: 6
    1: 7
  .code:
    push_const 0
    push_const 1
    mul
    ret
''');
      final tA = ctx.spawn('sumChunk');
      final tB = ctx.spawn('mulChunk');
      await ctx.runToCompletion(1);
      expect(tA.result, 15, reason: 'sum 1..5');
      expect(tB.result, 42, reason: '6 * 7');
      expect(tA.error, isNull);
      expect(tB.error, isNull);
    });

    test('five threads each return a distinct constant (quantum=1)', () async {
      // One program with 5 independent chunks, each returning index * 10.
      final src = StringBuffer();
      for (var i = 0; i < 5; i++) {
        src.writeln('.chunk c$i:');
        src.writeln('  .constants:');
        src.writeln('    0: ${i * 10}');
        src.writeln('  .code:');
        src.writeln('    push_const 0');
        src.writeln('    ret');
      }
      final ctx = makeCtx(src.toString());
      final threads = [for (var i = 0; i < 5; i++) ctx.spawn('c$i')];
      await ctx.runToCompletion(1);
      for (var i = 0; i < 5; i++) {
        expect(threads[i].result, i * 10, reason: 'thread c$i');
        expect(threads[i].error, isNull);
      }
    });

    test('faulted thread is stopped; sibling thread completes normally', () async {
      // faultyChunk tries to call an integer — BytecodeRuntimeError is raised.
      // goodChunk just returns 7.
      // The error must not propagate to the sibling.
      final ctx = makeCtx('''
.chunk faultyChunk:
  .constants:
    0: 42
  .code:
    push_const 0
    call 0
    ret

.chunk goodChunk:
  .constants:
    0: 7
  .code:
    push_const 0
    ret
''');
      final bad = ctx.spawn('faultyChunk');
      final good = ctx.spawn('goodChunk');
      await ctx.runToCompletion();
      expect(bad.error, isA<BytecodeRuntimeError>());
      expect(bad.isRunning, isFalse);
      expect(good.result, 7);
      expect(good.error, isNull);
      expect(ctx.hasRunningThreads, isFalse);
    });

    test('recursive GCD runs concurrently with a loop (quantum=1)', () async {
      // Stress test: deeply recursive chunk (GCD) vs a tight loop (sum),
      // both interleaved one instruction at a time.
      final ctx = makeCtx('''
.chunk gcdMain:
  .constants:
    0: .gcd
    1: 48
    2: 18
  .code:
    push_const 0
    push_const 1
    push_const 2
    call 2
    ret

.chunk gcd:
  .params:
    a
    b
  .constants:
    0: b
    1: 0
    2: a
    3: .gcd
    4: a
    5: b
  .code:
    load_var 0
    push_const 1
    cmp_eq
    jump_false .recurse
    load_var 2
    ret
  .recurse:
    push_const 3
    load_var 5
    load_var 4
    load_var 5
    mod
    call 2
    ret

.chunk sumMain:
  .constants:
    0: 0
    1: iV
    2: totV
    3: 1
    4: 10
  .code:
    push_const 0
    store_var 1
    push_const 0
    store_var 2
  .loop:
    load_var 1
    push_const 4
    cmp_lte
    jump_false .done
    load_var 2
    load_var 1
    add
    store_var 2
    load_var 1
    push_const 3
    add
    store_var 1
    jump .loop
  .done:
    load_var 2
    ret
''');
      final tGcd = ctx.spawn('gcdMain');
      final tSum = ctx.spawn('sumMain');
      await ctx.runToCompletion(1);
      expect(tGcd.result, 6, reason: 'GCD(48,18)=6');
      expect(tSum.result, 55, reason: 'sum 1..10=55');
      expect(tGcd.error, isNull);
      expect(tSum.error, isNull);
    });
  });
}
