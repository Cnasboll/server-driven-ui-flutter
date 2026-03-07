import 'dart:io';

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

/// Thin wrapper over [Engine.execute] — exact current semantics, no change.
Future<dynamic> evalEngine(
  String src, {
  Runtime? runtime,
  ConstantsSet? constantsSet,
  Map<String, dynamic>? boundValues,
}) => Engine.execute(
  src,
  runtime: runtime,
  constantsSet: constantsSet,
  boundValues: boundValues,
);

/// Compile [src] to bytecode, binary-round-trip it, then execute on the VM.
///
/// Runtime-registered functions (LENGTH, POW, SQRT, etc.) are bridged
/// automatically by [BytecodeInterpreter]'s constructor.
Future<dynamic> evalBytecode(String src, {Runtime? runtime, ConstantsSet? cs}) {
  cs ??= Runtime.prepareConstantsSet();
  runtime ??= Runtime.prepareRuntime(cs);
  final tree = Parser.parse(src, cs, sourceCode: src);
  final program = BytecodeCompiler.compile(tree, cs);
  final decoded = BytecodeDecoder.decode(BytecodeEncoder.encode(program));
  return BytecodeInterpreter(decoded, runtime).execute('main');
}

/// Like [evalBytecode] but prepends stdlib.shql source before compiling.
///
/// Both stdlib and user code are compiled to bytecode together so that
/// SHQL-defined stdlib functions (NVL, STATS, SORT, etc.) are available
/// as [BytecodeCallable]s rather than tree-walking [UserFunction]s.
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

Future<(Runtime, ConstantsSet)> _loadStdLib() async {
  var constantsSet = Runtime.prepareConstantsSet();
  var runtime = Runtime.prepareRuntime(constantsSet);
  // Load stdlib
  final stdlibCode = await File('assets/stdlib.shql').readAsString();

  await evalEngine(
    stdlibCode,
    runtime: runtime,
    constantsSet: constantsSet,
  );
  return (runtime, constantsSet);
}

void main() {
  // ---- Parameterised helpers — run the assertion in both modes ---------------

  // Simple expression: eval in engine mode, then bytecode mode.
  void shqlTest(String name, String src, dynamic expected) {
    test('$name [engine]', () async => expect(await evalEngine(src), expected));
    test('$name [bytecode]', () async => expect(await evalBytecode(src), expected));
  }

  // Expression that requires stdlib (NVL, STATS, SORT, etc.).
  // Engine mode uses _loadStdLib(); bytecode mode uses evalBytecodeWithStdlib().
  void shqlTestStdlib(String name, String src, dynamic expected) {
    test('$name [engine]', () async {
      final (runtime, cs) = await _loadStdLib();
      expect(await evalEngine(src, runtime: runtime, constantsSet: cs), expected);
    });
    test('$name [bytecode]', () async =>
        expect(await evalBytecodeWithStdlib(src), expected));
  }

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

  shqlTest('Execute addition', '10+2', 12);
  shqlTest('Execute addition and multiplication', '10+13*37+1', 492);

  // engine-only: implicit multiplication (bytecode doesn't support implicit multiplication)
  test('Execute implicit constant multiplication with parenthesis', () async {
    expect(await evalEngine('ANSWER(2)'), 84);
  });

  // engine-only: implicit multiplication
  test(
    'Execute implicit constant multiplication with parenthesis first',
    () async {
      expect(await evalEngine('(2)ANSWER'), 84);
    },
  );

  // engine-only: implicit multiplication
  test(
    'Execute implicit constant multiplication with constant within parenthesis first',
    () async {
      expect(await evalEngine('(ANSWER)2'), 84);
    },
  );

  // engine-only: implicit multiplication
  test('Execute implicit multiplication with parenthesis', () async {
    expect(await evalEngine('2(3)'), 6);
  });

  shqlTest('Execute addition and multiplication with parenthesis', '10+13*(37+1)', 504);

  // engine-only: implicit multiplication
  test(
    'Execute addition and implicit multiplication with parenthesis',
    () async {
      expect(await evalEngine('10+13(37+1)'), 504);
    },
  );

  shqlTest('Execute addition, multiplication and subtraction', '10+13*37-1', 490);

  // engine-only: implicit multiplication
  test('Execute addition, implicit multiplication and subtraction', () async {
    expect(await evalEngine('10+13(37)-1'), 490);
  });

  shqlTest('Execute addition, multiplication, subtraction and division', '10+13*37/2-1', 249.5);

  // engine-only: implicit multiplication
  test(
    'Execute addition, implicit multiplication, subtraction and division',
    () async {
      expect(await evalEngine('10+13(37)/2-1'), 249.5);
    },
  );

  shqlTest('Execute modulus', '9%2', 1);
  shqlTest('Execute equality true', '5*2 = 2+8', true);
  shqlTest('Execute equality false', '5*2 = 1+8', false);
  shqlTest('Execute not equal true', '5*2 <> 1+8', true);
  shqlTest('Execute not equal true with exclamation equals', '5*2 != 1+8', true);

  // engine-only: multiple unrelated expects
  test('Evaluate match true', () async {
    expect(await evalEngine('"Super Man" ~  r"Super\\s*Man"'), true);
    expect(await evalEngine('"Superman" ~  r"Super\\s*Man"'), true);
    expect(await evalEngine('"Batman" ~  "batman"'), true);
  });

  // engine-only: multiple unrelated expects
  test('Evaluate match false', () async {
    expect(await evalEngine('"Bat Man" ~  r"Super\\s*Man"'), false);
    expect(await evalEngine('"Batman" ~  r"Super\\s*Man"'), false);
  });

  // engine-only: multiple unrelated expects
  test('Evaluate mismatch true', () async {
    expect(await evalEngine('"Bat Man" !~  r"Super\\s*Man"'), true);
    expect(await evalEngine('"Batman" !~  r"Super\\s*Man"'), true);
  });

  // engine-only: multiple unrelated expects
  test('Evaluate mismatch false', () async {
    expect(await evalEngine('"Super Man" !~  r"Super\\s*Man"'), false);
    expect(await evalEngine('"Superman" !~  r"Super\\s*Man"'), false);
  });

  // engine-only: multiple unrelated expects
  test('Evaluate in list true', () async {
    expect(
      await evalEngine('"Super Man" in ["Super Man", "Batman"]'),
      true,
    );
    expect(
      await evalEngine('"Super Man" finns_i ["Super Man", "Batman"]'),
      true,
    );
    expect(await evalEngine('"Batman" in  ["Super Man", "Batman"]'), true);
    expect(
      await evalEngine('"Batman" finns_i  ["Super Man", "Batman"]'),
      true,
    );
  });

  // engine-only: multiple expects with shared runtime
  test('Evaluate lower case in list true', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await evalEngine(
        'lowercase("Robin") in  ["batman", "robin"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      true,
    );
    expect(
      await evalEngine(
        'lowercase("Batman") in  ["batman", "robin"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      true,
    );
  });

  // engine-only: multiple unrelated expects
  test('Evaluate in list false', () async {
    expect(await evalEngine('"Robin" in  ["Super Man", "Batman"]'), false);
    expect(
      await evalEngine('"Superman" in ["Super Man", "Batman"]'),
      false,
    );
  });

  // engine-only: multiple expects with shared runtime
  test('Evaluate lower case in list false', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await evalEngine(
        'lowercase("robin") in  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await evalEngine(
        'lowercase("robin") finns_i  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await evalEngine(
        'lowercase("superman") in  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await evalEngine(
        'lowercase("superman") finns_i  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
  });

  shqlTest('Execute not equal false', '5*2 <> 2+8', false);
  shqlTest('Execute not equal false with exclamation equals', '5*2 != 2+8', false);
  shqlTest('Execute less than false', '10<1', false);
  shqlTest('Execute less than true', '1<10', true);
  shqlTest('Execute less than or equal false', '10<=1', false);
  shqlTest('Execute less than or equal true', '1<=10', true);
  shqlTest('Execute greater than false', '1>10', false);
  shqlTest('Execute greater than true', '10>1', true);
  shqlTest('Execute greater than or equal false', '1>=10', false);
  shqlTest('Execute greater than or equal true', '10>=1', true);

  // engine-only: multiple unrelated expects
  test('Execute some boolean algebra and true', () async {
    expect(await evalEngine('1<10 AND 2<9'), true);
    expect(await evalEngine('1<10 OCH 2<9'), true);
  });

  // engine-only: multiple unrelated expects
  test('Execute some boolean algebra and false', () async {
    expect(await evalEngine('1>10 AND 2<9'), false);
    expect(await evalEngine('1>10 OCH 2<9'), false);
  });

  // engine-only: multiple unrelated expects
  test('Execute some boolean algebra or true', () async {
    expect(await evalEngine('1>10 OR 2<9'), true);
    expect(await evalEngine('1>10 ELLER 2<9'), true);
  });

  // engine-only: multiple unrelated expects
  test('Execute some boolean algebra xor true', () async {
    expect(await evalEngine('1>10 XOR 2<9'), true);
    expect(await evalEngine('1>10 ANTINGEN_ELLER 2<9'), true);
  });

  // engine-only: multiple unrelated expects
  test('calculate_some_bool_algebra_xor_false', () async {
    expect(await evalEngine('10>1 XOR 2<9'), false);
    expect(await evalEngine('10>1 ANTINGEN_ELLER 2<9'), false);
  });

  // engine-only: multiple unrelated expects
  test('calculate_negation', () async {
    expect(await evalEngine('NOT 11'), false);
    expect(await evalEngine('INTE 11'), false);
  });

  shqlTest('calculate_negation with exclamation', '!11', false);
  shqlTest('Execute unary minus', '-5+11', 6);
  shqlTest('Execute unary plus', '+5+11', 16);
  shqlTest('Execute with constants', 'PI * 2', 3.1415926535897932 * 2);
  shqlTest('Execute with lowercase constants', 'pi * 2', 3.1415926535897932 * 2);

  // POW and SQRT are native Dart functions: engine mode needs stdlib loaded,
  // bytecode mode uses evalBytecode directly (natives are auto-bridged).
  test('Execute with functions [engine]', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(await evalEngine('POW(2,2)', runtime: runtime, constantsSet: constantsSet), 4);
  });
  test('Execute with functions [bytecode]', () async => expect(await evalBytecode('POW(2,2)'), 4.0));

  test('Execute with two functions [engine]', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(await evalEngine('POW(2,2)+SQRT(4)', runtime: runtime, constantsSet: constantsSet), 6);
  });
  test('Execute with two functions [bytecode]', () async => expect(await evalBytecode('POW(2,2)+SQRT(4)'), 6.0));

  // engine-only: uses Engine.evalExpr (not evalEngine)
  test('Calculate library function', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.evalExpr(
        'SQRT(4)',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      2,
    );
  });

  test('Execute nested function call [engine]', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(await evalEngine('SQRT(POW(2,2))', runtime: runtime, constantsSet: constantsSet), 2);
  });
  test('Execute nested function call [bytecode]', () async => expect(await evalBytecode('SQRT(POW(2,2))'), 2.0));

  test('Execute nested function call with expression [engine]', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(await evalEngine('SQRT(POW(2,2)+10)', runtime: runtime, constantsSet: constantsSet), 3.7416573867739413);
  });
  test('Execute nested function call with expression [bytecode]', () async => expect(await evalBytecode('SQRT(POW(2,2)+10)'), 3.7416573867739413));

  shqlTest('Execute two expressions', '10;11', 11);
  shqlTest('Execute two expressions with final semicolon', '10;11;', 11);
  shqlTest('Test assignment', 'i:=42', 42);
  shqlTest('Test increment', 'i:=41;i:=i+1', 42);

  // engine-only: checks is UserFunction (bytecode produces BytecodeCallable)
  test('Test function definition', () async {
    expect((await evalEngine('f(x):=x*2')).runtimeType, UserFunction);
  });

  shqlTest('Test user function', 'f(x):=x*2;f(2)', 4);
  shqlTest('Test two argument user function', 'f(a,b):=a-b;f(10,2)', 8);
  shqlTest('Test recursion', 'fac(x) := IF x <= 1 THEN 1 ELSE x * fac(x-1);fac(3)', 6);
  shqlTest('Test while loop', 'x := 0; WHILE x < 10 DO x := x + 1;x', 10);
  shqlTest('Test lambda function', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 1,2,3)', 6);
  shqlTest('Test lambda function with user function argument', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 10,20,5)', 35);
  shqlTest('Test lambda expression', 'f:= x => x^2;f(3)', 9);
  shqlTest('Test anonymous lambda expression', '(x => x^2)(3)', 9);
  shqlTest('Test nullary anonymous lambda expression', '(() => 9)()', 9);
  shqlTest('Test return', 'f(x) := IF x % 2 = 0 THEN RETURN x+1 ELSE RETURN x; f(2)', 3);
  shqlTest('Test block return', 'f(x) := BEGIN IF x % 2 = 0 THEN RETURN x+1; RETURN x; END; f(2)', 3);
  shqlTest('Test factorial with return', 'f(x) := BEGIN IF x <= 1 THEN RETURN 1; RETURN x * f(x-1); END; f(5)', 120);
  shqlTest('Test break', 'x := 0; WHILE TRUE DO BEGIN x := x + 1; IF x = 10 THEN BREAK; END; x', 10);
  shqlTest('Test continue', 'x := 0; y := 0; WHILE x < 10 DO BEGIN x := x + 1; IF x % 2 = 0 THEN CONTINUE; y := y + 1; END; y', 5);

  shqlTest('FOR CONTINUE with IF', r'''
        __test() := BEGIN
          __result := [];
          FOR __i := 0 TO 2 DO BEGIN
            IF __i = 1 THEN CONTINUE;
            __result := __result + [__i];
          END;
          RETURN __result;
        END;
        __test()
      ''', [0, 2]);

  shqlTest('FOR CONTINUE with nested IF-ELSE IF', r'''
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
      ''', ['zero', 'after', 'skip', 'two', 'after']);

  shqlTest('FOR CONTINUE inside nested IF-THEN-BEGIN-END', r'''
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
      ''', [0, 'skip', 2]);

  shqlTestStdlib('FOR CONTINUE with nested ELSE IF BREAK pattern', r'''
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
      ''', ['skipped', 'skipped', 'skipped']);

  shqlTest('Test repeat until', 'x := 0; REPEAT x := x + 1 UNTIL x = 10; x', 10);
  shqlTest('Test for loop', 'sum := 0; FOR i := 1 TO 10 DO sum := sum + i; sum', 55);

  // engine-only: complex multi-step test with multiple evalEngine calls and is-Map checks
  test("Test list utils", () async {
    var (runtime, constantsSet) = await _loadStdLib();

    var listUtilsCodde = """
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
    await evalEngine(
      listUtilsCodde,
      runtime: runtime,
      constantsSet: constantsSet,
    );
    await evalEngine(
      "list := [_GEN_LIST_ITEM_TEMPLATE(1)];",
      runtime: runtime,
      constantsSet: constantsSet,
    );
    expect(
      (await evalEngine(
            "list[0]",
            runtime: runtime,
            constantsSet: constantsSet,
          )
          is Map),
      true,
    );
    expect(
      (await evalEngine(
            "list[0]['props']",
            runtime: runtime,
            constantsSet: constantsSet,
          )
          is Map),
      true,
    );
  });

  shqlTest('Test for loop with step', 'sum := 0; FOR i := 1 TO 10 STEP 2 DO sum := sum + i; sum', 25);
  shqlTest('Test for loop counting down', 'sum := 0; FOR i := 10 TO 1 STEP -1 DO sum := sum + i; sum', 55);

  shqlTest('Can assign to list variable', 'x := [1,2,3];x[0]', 1);
  shqlTest('Can assign to list member', 'x := [1,2,3];x[1]:=4;x[1]', 4);

  // engine-only: checks is Thread type (bytecode produces a different thread representation)
  test("Can create thread", () async {
    expect((await evalEngine("THREAD( () => 9 )")) is Thread, true);
  });

  shqlTest('Can assign to map variable', "x := {'a':1,'b':2,'c':3};x['a']", 1);
  shqlTest('Can assign to map member', "x := {'a':1,'b':2,'c':3};x['b']:=4;x['b']", 4);

  shqlTest("Can start thread", "x := 0; t := THREAD( () => BEGIN FOR i := 1 TO 1000 DO x := x + 1; END ); JOIN(t); x", 1000);

  // engine-only: global variable tests use a shared runtime object across multiple evalEngine calls
  test("Global variable accessed in function", () async {
    var constantsSet = Runtime.prepareConstantsSet();
    var runtime = Runtime.prepareRuntime(constantsSet);
    final code = """
      my_global := 42;
      GET_GLOBAL() := my_global;
      GET_GLOBAL()
    """;
    expect(
      await evalEngine(code, runtime: runtime, constantsSet: constantsSet),
      42,
    );
  });

  // engine-only: global variable tests use a shared runtime
  test("Global variable modified in function", () async {
    var constantsSet = Runtime.prepareConstantsSet();
    var runtime = Runtime.prepareRuntime(constantsSet);
    final code = """
      my_global := 10;
      ADD_TO_GLOBAL(x) := BEGIN
        my_global := my_global + x;
        RETURN my_global;
      END;
      ADD_TO_GLOBAL(5)
    """;
    expect(
      await evalEngine(code, runtime: runtime, constantsSet: constantsSet),
      15,
    );
  });

  // engine-only: complex multi-expect with shared runtime
  test("Global array accessed in function", () async {
    var (runtime, constantsSet) = await _loadStdLib();
    final code = """
      my_array := [1, 2, 3];
      GET_LENGTH() := LENGTH(my_array);
      GET_LENGTH()
    """;
    expect(
      await evalEngine(code, runtime: runtime, constantsSet: constantsSet),
      3,
    );
  });

  // engine-only: complex multi-expect with shared runtime
  test("Global array modified in function", () async {
    var (runtime, constantsSet) = await _loadStdLib();
    final code = """
      my_array := [1, 2, 3];
      PUSH_TO_ARRAY(x) := BEGIN
        my_array := my_array + [x];
        RETURN my_array;
      END;
      PUSH_TO_ARRAY(4)
    """;
    final result = await evalEngine(
      code,
      runtime: runtime,
      constantsSet: constantsSet,
    );
    expect(result is List, true);
    expect((result as List).length, 4);
    expect(result[3], 4);
  });

  // engine-only: complex navigation pattern with shared runtime
  test("Navigation stack push/pop pattern", () async {
    var (runtime, constantsSet) = await _loadStdLib();
    final code = """
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
      result := POP_ROUTE();
      result
    """;
    expect(
      await evalEngine(code, runtime: runtime, constantsSet: constantsSet),
      'screen2',
    );
  });

  shqlTest('User function can access constants like TRUE', 'test() := TRUE; test()', true);

  group('Error reporting tests', () {
    test('Should show correct line numbers in error messages', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      try {
        // Define a function that calls an undefined function
        await evalEngine(
          "test() := undefinedFunction();",
          constantsSet: constantsSet,
          runtime: runtime,
        );

        // Try to call it - this should fail because undefinedFunction doesn't exist
        await evalEngine(
          "test()",
          constantsSet: constantsSet,
          runtime: runtime,
        );

        fail('Expected RuntimeException to be thrown');
      } catch (e) {
        final errorMessage = e.toString();
        // Should contain correct line number
        expect(errorMessage, contains('Line 1:'));
        // Should contain the actual code
        expect(errorMessage, contains('undefinedFunction'));
      }
    });
  });

  group('List utility functions', () {
    // engine-only: multiple unrelated expects in one test
    test('LENGTH should return list length', () async {
      final (runtime, constantsSet) = await _loadStdLib();
      expect(
        await evalEngine(
          'LENGTH([1, 2, 3])',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        3,
      );
      expect(
        await evalEngine(
          'LENGTH([])',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        0,
      );
    });
  });

  group('Object member access with dot operator', () {
    // engine-only: uses Dart Object manipulation to set up test state
    test('Should access Object members using dot notation', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      // Create an Object explicitly and add members
      final testObject = Object();
      final nameId = runtime.identifiers.include('NAME');
      final ageId = runtime.identifiers.include('AGE');
      testObject.setVariable(nameId, 'Alice');
      testObject.setVariable(ageId, 30);

      // Add the object to the scope
      final personId = runtime.identifiers.include('PERSON');
      runtime.globalScope.setVariable(personId, testObject);

      // Access member using dot notation
      expect(
        await evalEngine(
          'person.name',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'Alice',
      );

      expect(
        await evalEngine(
          'person.age',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        30,
      );
    });

    // engine-only: uses Dart Object manipulation to set up test state
    test('Should wrap Object in Scope for member access', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      // Create an Object with members
      final configObject = Object();
      final hostId = runtime.identifiers.include('HOST');
      final portId = runtime.identifiers.include('PORT');
      configObject.setVariable(hostId, 'localhost');
      configObject.setVariable(portId, 8080);

      final configId = runtime.identifiers.include('CONFIG');
      runtime.globalScope.setVariable(configId, configObject);

      // Access members
      expect(
        await evalEngine(
          'config.host',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'localhost',
      );

      expect(
        await evalEngine(
          'config.port',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        8080,
      );
    });

    // engine-only: uses Dart Object manipulation to set up nested test state
    test('Should support nested object access (a.b.c.d)', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      // Create nested object structure: app.server.database.host
      final databaseObject = Object();
      final hostId = runtime.identifiers.include('HOST');
      final portId = runtime.identifiers.include('PORT');
      databaseObject.setVariable(hostId, 'db.example.com');
      databaseObject.setVariable(portId, 5432);

      final serverObject = Object();
      final databaseId = runtime.identifiers.include('DATABASE');
      final nameId = runtime.identifiers.include('NAME');
      serverObject.setVariable(databaseId, databaseObject);
      serverObject.setVariable(nameId, 'prod-server');

      final appObject = Object();
      final serverId = runtime.identifiers.include('SERVER');
      final versionId = runtime.identifiers.include('VERSION');
      appObject.setVariable(serverId, serverObject);
      appObject.setVariable(versionId, '1.0.0');

      final appId = runtime.identifiers.include('APP');
      runtime.globalScope.setVariable(appId, appObject);

      // Test nested access: app.server.database.host
      expect(
        await evalEngine(
          'app.server.database.host',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'db.example.com',
      );

      // Test nested access: app.server.database.port
      expect(
        await evalEngine(
          'app.server.database.port',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        5432,
      );

      // Test partial access: app.server.name
      expect(
        await evalEngine(
          'app.server.name',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'prod-server',
      );

      // Test shallow access: app.version
      expect(
        await evalEngine(
          'app.version',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        '1.0.0',
      );
    });
  });

  group('Object literal with OBJECT keyword', () {
    // engine-only: checks isA<Object>() and then inspects Dart-level Object fields
    test('Should create Object with bare identifier keys', () async {
      final result = await evalEngine('OBJECT{name: "Alice", age: 30}');
      expect(result, isA<Object>());

      final obj = result as Object;
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);
      final nameId = runtime.identifiers.include('NAME');
      final ageId = runtime.identifiers.include('AGE');

      final nameVar = obj.resolveIdentifier(nameId) as Variable;
      final ageVar = obj.resolveIdentifier(ageId) as Variable;
      expect(nameVar.value, 'Alice');
      expect(ageVar.value, 30);
    });

    // engine-only: multiple unrelated expects in one test
    test('Should access Object literal members with dot notation', () async {
      expect(await evalEngine('obj := OBJECT{x: 10, y: 20}; obj.x'), 10);

      expect(await evalEngine('obj := OBJECT{x: 10, y: 20}; obj.y'), 20);
    });

    // engine-only: multiple unrelated expects in one test
    test('Should create nested Objects', () async {
      expect(
        await evalEngine(
          'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.name',
        ),
        'Bob',
      );

      expect(
        await evalEngine(
          'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.age',
        ),
        25,
      );
    });

    // engine-only: multiple expects checking different types (Object vs Map)
    test('Should distinguish Objects from Maps', () async {
      // Object with bare identifier keys
      final obj = await evalEngine('OBJECT{name: "Alice"}');
      expect(obj, isA<Object>());

      // Map with evaluated expression keys
      final map = await evalEngine('x := "name"; {x: "Alice"}');
      expect(map, isA<Map>());

      // Map with literal number keys
      final map2 = await evalEngine('{42: "answer"}');
      expect(map2, isA<Map>());
    });

    // engine-only: multiple unrelated expects in one test
    test('Should create Object with complex values', () async {
      expect(
        await evalEngine(
          'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; list := obj.list; list[1]',
        ),
        2,
      );

      expect(
        await evalEngine(
          'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; obj.sum',
        ),
        3,
      );
    });

    // engine-only: multiple unrelated expects in one test
    test('Should assign to Object members', () async {
      expect(
        await evalEngine(
          'obj := OBJECT{x: 10, y: 20}; obj.x := 100; obj.x',
        ),
        100,
      );

      expect(
        await evalEngine(
          'obj := OBJECT{x: 10, y: 20}; obj.y := 200; obj.y',
        ),
        200,
      );
    });

    shqlTest('Should assign to nested Object members', 'obj := OBJECT{inner: OBJECT{value: 5}}; obj.inner.value := 42; obj.inner.value', 42);
    shqlTest('Should modify Object member and read it back', 'obj := OBJECT{counter: 0}; obj.counter := obj.counter + 1; obj.counter', 1);
  });

  group('Object methods with proper scope', () {
    shqlTest('Should access object members from method', 'obj := OBJECT{x: 10, getX: () => x}; obj.getX()', 10);
    shqlTest('Should access multiple object members from method', 'obj := OBJECT{x: 10, y: 20, sum: () => x + y}; obj.sum()', 30);
    shqlTest('Should modify object members from method', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.counter', 1);
    shqlTest('Should call method multiple times and modify state', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.increment(); obj.increment(); obj.counter', 3);
    shqlTest('Should access method parameters and object members', 'obj := OBJECT{x: 10, add: (delta) => x + delta}; obj.add(5)', 15);
    shqlTest('Should modify object member with parameter', 'obj := OBJECT{x: 10, setX: (newX) => x := newX}; obj.setX(42); obj.x', 42);
    shqlTest('Should access nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, getInnerValue: () => inner.value}; obj.getInnerValue()', 5);
    shqlTest('Should modify nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, incrementInner: () => inner.value := inner.value + 1}; obj.incrementInner(); obj.inner.value', 6);
    shqlTest('Method should have access to closure variables', 'outerVar := 100; obj := OBJECT{x: 10, addOuter: () => x + outerVar}; obj.addOuter()', 110);
    shqlTest('Method parameters should shadow object members', 'obj := OBJECT{x: 10, useParam: (x) => x}; obj.useParam(42)', 42);
    shqlTest('Should support method calling another method', 'obj := OBJECT{x: 10, getX: () => x, doubleX: () => getX() * 2}; obj.doubleX()', 20);

    shqlTest('Should create object with counter and multiple methods', '''
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
          ''', 1);
  });

  group('THIS self-reference in OBJECT', () {
    shqlTest('THIS resolves to the object itself', '''
          obj := OBJECT{x: 10, getThis: () => THIS};
          obj.getThis().x
        ''', 10);

    shqlTest('THIS.field works for dot access', '''
          obj := OBJECT{x: 42, getX: () => THIS.x};
          obj.getX()
        ''', 42);

    shqlTest('THIS enables fluent/builder pattern', '''
          builder := OBJECT{
            value: 0,
            setValue: (v) => BEGIN value := v; RETURN THIS; END
          };
          builder.setValue(99).value
        ''', 99);

    // engine-only: multiple unrelated expects in one test
    test('Nested objects have independent THIS', () async {
      expect(
        await evalEngine('''
          outer := OBJECT{
            name: "outer",
            inner: OBJECT{
              name: "inner",
              getName: () => THIS.name
            },
            getName: () => THIS.name
          };
          outer.inner.getName()
        '''),
        'inner',
      );

      expect(
        await evalEngine('''
          outer := OBJECT{
            name: "outer",
            inner: OBJECT{
              name: "inner",
              getName: () => THIS.name
            },
            getName: () => THIS.name
          };
          outer.getName()
        '''),
        'outer',
      );
    });

    shqlTest('THIS is mutable (can be reassigned)', '''
          obj := OBJECT{x: 10, getX: () => THIS.x};
          obj.getX()
        ''', 10);
  });

  group('Cross-object member access', () {
    shqlTest('Object B method can access Object A members via global', '''
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
        ''', 15);

    shqlTest('Field name colliding with global name (case-insensitive) from external scope', '''
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
        ''', []);
  });

  group('Null value handling', () {
    shqlTest('Should distinguish between undefined and null variables', 'x := null; x', null);
    shqlTest('Should allow null in expressions', 'x := null; y := 5; x = null', true);
    shqlTest('Should allow calling functions with null arguments', 'f(x) := x; f(null)', null);
    shqlTest('Should access object members that are null', 'obj := OBJECT{title: null}; obj.title', null);
    shqlTest('Should call object methods that return null', 'obj := OBJECT{getNull: () => null}; obj.getNull()', null);
    shqlTest('Should allow assigning null from map/list access', 'posts := [{"title": null}]; title := posts[0]["title"]; title', null);
    shqlTest('Should distinguish null value from missing key in map', 'm := {"a": null}; m["a"]', null);
  });

  group('Object literal with standalone lambda values', () {
    // These tests verify that lambda values stored in an OBJECT can be
    // retrieved and called from outside the object, with parameters binding
    // correctly (not referencing object members).

    shqlTest('Parenthesized param — simple value', 'obj := OBJECT{accessor: (x) => x + 1}; obj.accessor(5)', 6);
    shqlTest('Unparenthesized param — simple value', 'obj := OBJECT{accessor: x => x + 1}; obj.accessor(5)', 6);

    shqlTest('Parenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: (p) => p.name}; '
        'meta.getName(person)',
        'Alice');

    shqlTest('Unparenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: p => p.name}; '
        'meta.getName(person)',
        'Alice');

    // engine-only: uses manual stdlib loading with evalEngine calls + NVL
    test('Lambda calling another function with its parameter', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(
        stdlibCode,
        runtime: runtime,
        constantsSet: constantsSet,
      );

      expect(
        await evalEngine(
          'GET(hero, f, default) := NVL(hero, f, default); '
          'meta := OBJECT{accessor: (hero) => GET(hero, h => h.name, "none")}; '
          'person := OBJECT{name: "Bob"}; '
          'meta.accessor(person)',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'Bob',
      );
    });

    shqlTest('Lambda stored in list of OBJECTs',
        'fields := [OBJECT{prop: "x", accessor: (v) => v + 10}]; '
        'fields[0].accessor(5)',
        15);

    shqlTest('Iterating OBJECT list and calling stored lambdas',
        'fields := ['
        '  OBJECT{prop: "a", accessor: (v) => v + 1},'
        '  OBJECT{prop: "b", accessor: (v) => v * 2}'
        ']; '
        'f0 := fields[0]; f1 := fields[1]; '
        'f0.accessor(10) + f1.accessor(10)',
        31);

    // TRIM and IS_NULL_OR_WHITESPACE are native Dart functions: work with evalBytecode directly.
    test('TRIM strips whitespace [engine]', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
      expect(await evalEngine('TRIM("  hello  ")', runtime: runtime, constantsSet: constantsSet), 'hello');
    });
    test('TRIM strips whitespace [bytecode]', () async => expect(await evalBytecode('TRIM("  hello  ")'), 'hello'));

    // engine-only: IS_NULL_OR_WHITESPACE is a SHQL-defined stdlib function,
    // not a native Dart function, so it requires stdlib to be loaded.
    test('IS_NULL_OR_WHITESPACE returns true for null', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
      expect(await evalEngine('IS_NULL_OR_WHITESPACE(null)', runtime: runtime, constantsSet: constantsSet), true);
    });

    test('IS_NULL_OR_WHITESPACE returns true for whitespace-only', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
      expect(await evalEngine('IS_NULL_OR_WHITESPACE("   ")', runtime: runtime, constantsSet: constantsSet), true);
    });

    test('IS_NULL_OR_WHITESPACE returns false for non-blank string', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
      expect(await evalEngine('IS_NULL_OR_WHITESPACE("batman")', runtime: runtime, constantsSet: constantsSet), false);
    });

    shqlTest('Parenthesised IF-THEN-ELSE as value in map literal',
        'x := 1; '
        'obj := {"label": (IF x = 1 THEN "one" ELSE "other"), "score": 42}; '
        'obj["label"]',
        'one');

    shqlTest('Parenthesised IF-THEN-ELSE as value in list of maps',
        'q := "batman"; '
        r'''result := [{"type": "Text", "data": (IF q <> "" THEN "no match: " + q ELSE "No match")}]; '''
        'result[0]["data"]',
        'no match: batman');
  });

  // Regression tests: two sequential IF statements where the first IF's THEN
  // body is RETURN with a deeply nested JSON structure (like herodex.shql
  // GENERATE_SAVED_HEROES_CARDS). Caused "Expected THEN after IF condition".
  group('Two sequential IFs — first RETURN with nested JSON', () {
    shqlTest('Two simple IFs in BEGIN — baseline',
        'f() := BEGIN '
        '    IF 1 = 0 THEN RETURN "first"; '
        '    IF 1 = 1 THEN RETURN "second"; '
        '    RETURN "third"; '
        'END; '
        'f()',
        'second');

    shqlTest('First IF RETURN with one-level map, second IF fires',
        'heroes := []; '
        'f() := BEGIN '
        '    IF 1 = 0 THEN '
        '        RETURN [{"type": "A", "data": "empty"}]; '
        '    IF 1 = 1 THEN '
        '        RETURN [{"type": "B", "data": "match"}]; '
        '    RETURN []; '
        'END; '
        'f()',
        isA<List>());

    shqlTest('First IF RETURN with two-level nesting, second IF parses',
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
        'f()',
        isA<List>());

    shqlTest('First IF RETURN with three-level nesting, second IF parses',
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
        'f()',
        isA<List>());

    // engine-only: uses stdlib (IS_NULL_OR_WHITESPACE) with manual loading pattern
    test('Exact herodex.shql GENERATE_SAVED_HEROES_CARDS structure', () async {
      // This mirrors the exact failing structure: first IF with 4-level nested JSON,
      // second IF with AND/OR/NOT condition, both inside a function BEGIN block.
      final (runtime, constantsSet) = await _loadStdLib();
      final code = '''
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
''';
      expect(
        await evalEngine(code, runtime: runtime, constantsSet: constantsSet),
        isA<List>(),
      );
    });
  });

  group('IF condition ending with parenthesised sub-expression', () {
    // Regression: the implicit-multiplication check consumed THEN as an
    // identifier after a single-element tuple, e.g. `AND (expr) THEN` would
    // swallow THEN, causing "Expected THEN after IF condition".
    shqlTest('IF x AND (y) THEN evaluates correctly', 'IF 1 = 1 AND (2 = 2) THEN "yes" ELSE "no"', 'yes');
    shqlTest('IF x AND (y) THEN — false branch', 'IF 1 = 1 AND (2 = 3) THEN "yes" ELSE "no"', 'no');
  });

  group('Implicit multiplication with value-expression keywords', () {
    // engine-only: implicit multiplication
    test('(3)IF FALSE THEN 2 ELSE 3 = 9', () async {
      expect(await evalEngine('(3)IF FALSE THEN 2 ELSE 3'), 9);
    });

    // engine-only: implicit multiplication
    test('(3)IF TRUE THEN 2 ELSE 0 = 6', () async {
      expect(await evalEngine('(3)IF TRUE THEN 2 ELSE 0'), 6);
    });
  });

  group('(expr) followed by infix operator is NOT implicit multiplication', () {
    // (5)-3 must be subtraction (= 2), not 5 * (-3) = -15.
    // (5)+3 must be addition  (= 8), not 5 * (+3) =  15.
    shqlTest('(5)-3 = 2', '(5)-3', 2);
    shqlTest('(5)+3 = 8', '(5)+3', 8);
  });

  // Null-aware relational operators (>, <, >=, <=) return null when either
  // operand is null. Boolean operators (AND, OR, XOR) must treat null as
  // falsy — Dart's `null != 0` is `true`, but logically null means
  // "unknown / not applicable" and must not satisfy a condition.
  group('Null-aware relational operators return null', () {
    // engine-only: uses boundValues parameter (not supported in shqlTest)
    test('null > number returns null', () async {
      expect(await evalEngine('x > 5', boundValues: {'x': null}), isNull);
    });

    test('null < number returns null', () async {
      expect(await evalEngine('x < 5', boundValues: {'x': null}), isNull);
    });

    test('null >= number returns null', () async {
      expect(await evalEngine('x >= 5', boundValues: {'x': null}), isNull);
    });

    test('null <= number returns null', () async {
      expect(await evalEngine('x <= 5', boundValues: {'x': null}), isNull);
    });

    test('number > null returns null', () async {
      expect(await evalEngine('5 > x', boundValues: {'x': null}), isNull);
    });
  });

  group('AND treats null as falsy', () {
    // engine-only: uses boundValues parameter
    test('null AND true is false', () async {
      expect(await evalEngine('x AND TRUE', boundValues: {'x': null}), false);
    });

    test('true AND null is false', () async {
      expect(await evalEngine('TRUE AND x', boundValues: {'x': null}), false);
    });

    test('null AND false is false', () async {
      expect(await evalEngine('x AND FALSE', boundValues: {'x': null}), false);
    });

    test('(null > 5) AND true is false', () async {
      expect(await evalEngine('(x > 5) AND TRUE', boundValues: {'x': null}), false);
    });

    test('(null > 5) AND (3 > 0) is false', () async {
      expect(await evalEngine('(x > 5) AND (3 > 0)', boundValues: {'x': null}), false);
    });
  });

  group('OR treats null as falsy', () {
    // engine-only: uses boundValues parameter
    test('null OR true is true', () async {
      expect(await evalEngine('x OR TRUE', boundValues: {'x': null}), true);
    });

    test('null OR false is false', () async {
      expect(await evalEngine('x OR FALSE', boundValues: {'x': null}), false);
    });

    test('true OR null is true', () async {
      expect(await evalEngine('TRUE OR x', boundValues: {'x': null}), true);
    });

    test('false OR null is false', () async {
      expect(await evalEngine('FALSE OR x', boundValues: {'x': null}), false);
    });
  });

  group('NOT with null', () {
    // engine-only: uses boundValues parameter
    test('NOT null returns null (null-aware unary)', () async {
      expect(await evalEngine('NOT x', boundValues: {'x': null}), isNull);
    });
  });

  group('XOR treats null as falsy', () {
    // engine-only: uses boundValues parameter
    test('null XOR true is true', () async {
      expect(await evalEngine('x XOR TRUE', boundValues: {'x': null}), true);
    });

    test('null XOR false is false', () async {
      expect(await evalEngine('x XOR FALSE', boundValues: {'x': null}), false);
    });

    test('true XOR null is true', () async {
      expect(await evalEngine('TRUE XOR x', boundValues: {'x': null}), true);
    });
  });

  // The actual Giants bug: (null > avg + 2 * stdev) AND (stdev > 0)
  // should be false, not true.
  group('Giants predicate scenario — null height in boolean context', () {
    // engine-only: uses boundValues parameter
    test('null height with positive stdev should not match', () async {
      expect(
        await evalEngine(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': null, 'avg': 1.78, 'stdev': 0.2},
        ),
        false,
      );
    });

    test('tall height with positive stdev should match', () async {
      expect(
        await evalEngine(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': 2.5, 'avg': 1.78, 'stdev': 0.2},
        ),
        true,
      );
    });

    test('short height with positive stdev should not match', () async {
      expect(
        await evalEngine(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': 1.7, 'avg': 1.78, 'stdev': 0.2},
        ),
        false,
      );
    });
  });

  group('STATS() stdlib function', () {
    late Runtime runtime;
    late ConstantsSet constantsSet;

    setUp(() async {
      constantsSet = Runtime.prepareConstantsSet();
      runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
    });

    Future<dynamic> eval(String code) =>
        evalEngine(code, runtime: runtime, constantsSet: constantsSet);

    // engine-only: STATS is a SHQL stdlib function that internally calls SQRT
    // (a native Dart function requiring ExecutionContext), which is not yet
    // supported by evalBytecodeWithStdlib.
    test('returns zero object for empty list', () async {
      final ok = await eval(r'''
        __s := STATS([], x => x);
        __s.COUNT = 0 AND __s.AVG = 0 AND __s.STDEV = 0 AND __s.SUM = 0
      ''');
      expect(ok, true);
    });

    test('avg of single value equals that value', () async {
      expect(await eval('STATS([42], x => x).AVG'), 42);
    });

    test('stdev of single value is zero', () async {
      expect(await eval('STATS([42], x => x).STDEV'), 0);
    });

    test('avg, sum, count of [2, 4, 6]', () async {
      final ok = await eval(r'''
        __s := STATS([2, 4, 6], x => x);
        __s.AVG > 3.999 AND __s.AVG < 4.001 AND
        __s.SUM > 11.999 AND __s.SUM < 12.001 AND
        __s.COUNT = 3
      ''');
      expect(ok, true);
    });

    test('min and max of [2, 4, 6]', () async {
      final ok = await eval(r'''
        __s := STATS([2, 4, 6], x => x);
        __s.MIN > 1.999 AND __s.MIN < 2.001 AND
        __s.MAX > 5.999 AND __s.MAX < 6.001
      ''');
      expect(ok, true);
    });

    test('population stdev of [2, 4, 6] is sqrt(8/3)', () async {
      final stdev = await eval('STATS([2, 4, 6], x => x).STDEV');
      expect(stdev, closeTo(1.6329931618554521, 0.00001));
    });

    test('nulls are excluded from all calculations', () async {
      final ok = await eval(r'''
        __items := [OBJECT{v: 10}, OBJECT{v: null}, OBJECT{v: 20}];
        __s := STATS(__items, x => x.V);
        __s.AVG > 14.999 AND __s.AVG < 15.001 AND __s.COUNT = 2
      ''');
      expect(ok, true);
    });

    test('stdev of identical values is zero', () async {
      expect(await eval('STATS([5, 5, 5, 5], x => x).STDEV'), 0);
    });

    test('accessor lambda extracts nested field', () async {
      final avg = await eval(r'''
        __people := [OBJECT{height: 1.6}, OBJECT{height: 1.8}, OBJECT{height: 2.0}];
        STATS(__people, p => p.HEIGHT).AVG
      ''');
      expect(avg, closeTo(1.8, 0.0001));
    });

    test('all-null list returns zero count and zero avg', () async {
      final ok = await eval(r'''
        __items := [OBJECT{v: null}, OBJECT{v: null}];
        __s := STATS(__items, x => x.V);
        __s.COUNT = 0 AND __s.AVG = 0
      ''');
      expect(ok, true);
    });
  });
}
