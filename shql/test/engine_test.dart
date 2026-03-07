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

  // Expression tested via Engine.evalExpr / BytecodeInterpreter.evalExpr —
  // stops at the first backward jump (loop) instead of running forever.
  // No stdlib dimension needed yet (only one such test exists).
  void shqlTestExprStdlib(String name, String src, dynamic expected) {
    test('$name [engine]', () async {
      final (runtime, cs) = await _loadStdLib();
      expect(await Engine.evalExpr(src, runtime: runtime, constantsSet: cs), expected);
    });
    test('$name [bytecode]', () async =>
        expect(await BytecodeInterpreter.evalExpr(src), expected));
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
  shqlTest('Execute implicit constant multiplication with parenthesis', 'ANSWER(2)', 84);
  shqlTest('Execute implicit constant multiplication with parenthesis first', '(2)ANSWER', 84);
  shqlTest('Execute implicit constant multiplication with constant within parenthesis first', '(ANSWER)2', 84);
  shqlTest('Execute implicit multiplication with parenthesis', '2(3)', 6);
  shqlTest('Execute addition and multiplication with parenthesis', '10+13*(37+1)', 504);
  shqlTest('Execute addition and implicit multiplication with parenthesis', '10+13(37+1)', 504);
  shqlTest('Execute addition, multiplication and subtraction', '10+13*37-1', 490);
  shqlTest('Execute addition, implicit multiplication and subtraction', '10+13(37)-1', 490);
  shqlTest('Execute addition, multiplication, subtraction and division', '10+13*37/2-1', 249.5);
  shqlTest('Execute addition, implicit multiplication, subtraction and division', '10+13(37)/2-1', 249.5);

  shqlTest('Execute modulus', '9%2', 1);
  shqlTest('Execute equality true', '5*2 = 2+8', true);
  shqlTest('Execute equality false', '5*2 = 1+8', false);
  shqlTest('Execute not equal true', '5*2 <> 1+8', true);
  shqlTest('Execute not equal true with exclamation equals', '5*2 != 1+8', true);

  shqlTest('Evaluate match — Superman regex', '"Super Man" ~  r"Super\\s*Man"', true);
  shqlTest('Evaluate match — Superman plain', '"Superman" ~  r"Super\\s*Man"', true);
  shqlTest('Evaluate match — Batman case-insensitive', '"Batman" ~  "batman"', true);
  shqlTest('Evaluate match false — Bat Man', '"Bat Man" ~  r"Super\\s*Man"', false);
  shqlTest('Evaluate match false — Batman', '"Batman" ~  r"Super\\s*Man"', false);
  shqlTest('Evaluate mismatch true — Bat Man', '"Bat Man" !~  r"Super\\s*Man"', true);
  shqlTest('Evaluate mismatch true — Batman', '"Batman" !~  r"Super\\s*Man"', true);
  shqlTest('Evaluate mismatch false — Superman', '"Super Man" !~  r"Super\\s*Man"', false);
  shqlTest('Evaluate mismatch false — Superman2', '"Superman" !~  r"Super\\s*Man"', false);

  shqlTest('in list — Super Man found', '"Super Man" in ["Super Man", "Batman"]', true);
  shqlTest('in list — Super Man found (finns_i)', '"Super Man" finns_i ["Super Man", "Batman"]', true);
  shqlTest('in list — Batman found', '"Batman" in  ["Super Man", "Batman"]', true);
  shqlTest('in list — Batman found (finns_i)', '"Batman" finns_i  ["Super Man", "Batman"]', true);
  shqlTest('in list — Robin not found', '"Robin" in  ["Super Man", "Batman"]', false);
  shqlTest('in list — Superman not found', '"Superman" in ["Super Man", "Batman"]', false);
  shqlTestStdlib('in list — lowercase Robin found', 'lowercase("Robin") in  ["batman", "robin"]', true);
  shqlTestStdlib('in list — lowercase Batman found', 'lowercase("Batman") in  ["batman", "robin"]', true);
  shqlTestStdlib('in list — lowercase robin not found', 'lowercase("robin") in  ["super man", "batman"]', false);
  shqlTestStdlib('in list — lowercase robin not found (finns_i)', 'lowercase("robin") finns_i  ["super man", "batman"]', false);
  shqlTestStdlib('in list — lowercase superman not found', 'lowercase("superman") in  ["super man", "batman"]', false);
  shqlTestStdlib('in list — lowercase superman not found (finns_i)', 'lowercase("superman") finns_i  ["super man", "batman"]', false);

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

  shqlTest('AND true', '1<10 AND 2<9', true);
  shqlTest('AND true (OCH)', '1<10 OCH 2<9', true);
  shqlTest('AND false', '1>10 AND 2<9', false);
  shqlTest('AND false (OCH)', '1>10 OCH 2<9', false);
  shqlTest('OR true', '1>10 OR 2<9', true);
  shqlTest('OR true (ELLER)', '1>10 ELLER 2<9', true);
  shqlTest('XOR true', '1>10 XOR 2<9', true);
  shqlTest('XOR true (ANTINGEN_ELLER)', '1>10 ANTINGEN_ELLER 2<9', true);
  shqlTest('XOR false', '10>1 XOR 2<9', false);
  shqlTest('XOR false (ANTINGEN_ELLER)', '10>1 ANTINGEN_ELLER 2<9', false);
  shqlTest('NOT true number', 'NOT 11', false);
  shqlTest('NOT true number (INTE)', 'INTE 11', false);

  shqlTest('calculate_negation with exclamation', '!11', false);
  shqlTest('Execute unary minus', '-5+11', 6);
  shqlTest('Execute unary plus', '+5+11', 16);
  shqlTest('Execute with constants', 'PI * 2', 3.1415926535897932 * 2);
  shqlTest('Execute with lowercase constants', 'pi * 2', 3.1415926535897932 * 2);

  shqlTestStdlib('Execute with functions', 'POW(2,2)', 4);
  shqlTestStdlib('Execute with two functions', 'POW(2,2)+SQRT(4)', 6);
  shqlTestExprStdlib('Calculate library function', 'SQRT(4)', 2);
  shqlTestStdlib('Execute nested function call', 'SQRT(POW(2,2))', 2);
  shqlTestStdlib('Execute nested function call with expression', 'SQRT(POW(2,2)+10)', 3.7416573867739413);

  shqlTest('Execute two expressions', '10;11', 11);
  shqlTest('Execute two expressions with final semicolon', '10;11;', 11);
  shqlTest('Test assignment', 'i:=42', 42);
  shqlTest('Test increment', 'i:=41;i:=i+1', 42);

  test('Test function definition', () async {
    const src = 'f(x):=x*2';
    expect(await evalEngine(src), isA<UserFunction>());
    expect(await evalBytecode(src), isNotNull);
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

  test("Test list utils", () async {
    const setup = '$_listUtilsCode\nlist := [_GEN_LIST_ITEM_TEMPLATE(1)];';
    const q1 = 'list[0]';
    const q2 = "list[0]['props']";

    final (runtime, constantsSet) = await _loadStdLib();
    await evalEngine(setup, runtime: runtime, constantsSet: constantsSet);
    expect((await evalEngine(q1, runtime: runtime, constantsSet: constantsSet)) is Map, true);
    expect((await evalEngine(q2, runtime: runtime, constantsSet: constantsSet)) is Map, true);

    expect(await evalBytecodeWithStdlib('$setup $q1'), isA<Map>());
    expect(await evalBytecodeWithStdlib('$setup $q2'), isA<Map>());
  });

  shqlTest('Test for loop with step', 'sum := 0; FOR i := 1 TO 10 STEP 2 DO sum := sum + i; sum', 25);
  shqlTest('Test for loop counting down', 'sum := 0; FOR i := 10 TO 1 STEP -1 DO sum := sum + i; sum', 55);

  shqlTest('Can assign to list variable', 'x := [1,2,3];x[0]', 1);
  shqlTest('Can assign to list member', 'x := [1,2,3];x[1]:=4;x[1]', 4);

  test("Can create thread", () async {
    const src = "THREAD( () => 9 )";
    expect((await evalEngine(src)) is Thread, true);
    expect((await evalBytecode(src)) is Thread, true);
  });

  shqlTest('Can assign to map variable', "x := {'a':1,'b':2,'c':3};x['a']", 1);
  shqlTest('Can assign to map member', "x := {'a':1,'b':2,'c':3};x['b']:=4;x['b']", 4);

  shqlTest("Can start thread", "x := 0; t := THREAD( () => BEGIN FOR i := 1 TO 1000 DO x := x + 1; END ); JOIN(t); x", 1000);

  shqlTest('Global variable accessed in function',
      'my_global := 42; GET_GLOBAL() := my_global; GET_GLOBAL()', 42);
  shqlTest('Global variable modified in function',
      'my_global := 10; ADD_TO_GLOBAL(x) := BEGIN my_global := my_global + x; RETURN my_global; END; ADD_TO_GLOBAL(5)', 15);
  shqlTestStdlib('Global array accessed in function',
      'my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); GET_LENGTH()', 3);
  shqlTestStdlib('Global array modified in function — element at 3',
      'my_array := [1, 2, 3]; PUSH_TO_ARRAY(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; PUSH_TO_ARRAY(4)[3]', 4);
  shqlTestStdlib('Navigation stack push/pop pattern', r'''
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
''', 'screen2');

  shqlTest('User function can access constants like TRUE', 'test() := TRUE; test()', true);

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
        await evalBytecode(src);
        fail('Expected bytecode to throw');
      } catch (e) {
        if (e is TestFailure) rethrow;
      }
    });
  });

  group('List utility functions', () {
    shqlTestStdlib('LENGTH of 3-element list', 'LENGTH([1, 2, 3])', 3);
    shqlTestStdlib('LENGTH of empty list', 'LENGTH([])', 0);
  });

  group('Object member access with dot operator', () {
    // Dart-injected Object: same runtime is shared with evalBytecode so both modes
    // see the same pre-populated scope.
    test('Should access Object members using dot notation', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      final testObject = Object();
      final nameId = runtime.identifiers.include('NAME');
      final ageId = runtime.identifiers.include('AGE');
      testObject.setVariable(nameId, 'Alice');
      testObject.setVariable(ageId, 30);
      final personId = runtime.identifiers.include('PERSON');
      runtime.globalScope.setVariable(personId, testObject);

      expect(await evalEngine('person.name', runtime: runtime, constantsSet: constantsSet), 'Alice');
      expect(await evalEngine('person.age', runtime: runtime, constantsSet: constantsSet), 30);
      expect(await evalBytecode('person.name', runtime: runtime, cs: constantsSet), 'Alice');
      expect(await evalBytecode('person.age', runtime: runtime, cs: constantsSet), 30);
    });

    test('Should wrap Object in Scope for member access', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      final configObject = Object();
      final hostId = runtime.identifiers.include('HOST');
      final portId = runtime.identifiers.include('PORT');
      configObject.setVariable(hostId, 'localhost');
      configObject.setVariable(portId, 8080);
      final configId = runtime.identifiers.include('CONFIG');
      runtime.globalScope.setVariable(configId, configObject);

      expect(await evalEngine('config.host', runtime: runtime, constantsSet: constantsSet), 'localhost');
      expect(await evalEngine('config.port', runtime: runtime, constantsSet: constantsSet), 8080);
      expect(await evalBytecode('config.host', runtime: runtime, cs: constantsSet), 'localhost');
      expect(await evalBytecode('config.port', runtime: runtime, cs: constantsSet), 8080);
    });

    test('Should support nested object access (a.b.c.d)', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

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

      for (final eval in [
        (String src) => evalEngine(src, runtime: runtime, constantsSet: constantsSet),
        (String src) => evalBytecode(src, runtime: runtime, cs: constantsSet),
      ]) {
        expect(await eval('app.server.database.host'), 'db.example.com');
        expect(await eval('app.server.database.port'), 5432);
        expect(await eval('app.server.name'), 'prod-server');
        expect(await eval('app.version'), '1.0.0');
      }
    });
  });

  group('Object literal with OBJECT keyword', () {
    // Inspects Dart-level Object fields via resolveIdentifier — engine only for introspection,
    // bytecode verified separately via dot access which is already covered by shqlTest.
    test('Should create Object with bare identifier keys', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final nameId = rt.identifiers.include('NAME');
      final ageId = rt.identifiers.include('AGE');

      for (final result in [
        await evalEngine('OBJECT{name: "Alice", age: 30}'),
        await evalBytecode('OBJECT{name: "Alice", age: 30}', cs: cs),
      ]) {
        expect(result, isA<Object>());
        final obj = result as Object;
        expect((obj.resolveIdentifier(nameId) as Variable).value, 'Alice');
        expect((obj.resolveIdentifier(ageId) as Variable).value, 30);
      }
    });

    shqlTest('Object literal dot — x', 'obj := OBJECT{x: 10, y: 20}; obj.x', 10);
    shqlTest('Object literal dot — y', 'obj := OBJECT{x: 10, y: 20}; obj.y', 20);
    shqlTest('Nested Objects — person.name', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.name', 'Bob');
    shqlTest('Nested Objects — person.age', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.age', 25);
    shqlTest('Object complex value — list element', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; list := obj.list; list[1]', 2);
    shqlTest('Object complex value — sum', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; obj.sum', 3);
    shqlTest('Object member assignment — x', 'obj := OBJECT{x: 10, y: 20}; obj.x := 100; obj.x', 100);
    shqlTest('Object member assignment — y', 'obj := OBJECT{x: 10, y: 20}; obj.y := 200; obj.y', 200);

    test('Should distinguish Objects from Maps', () async {
      for (final eval in [evalEngine, evalBytecode]) {
        expect(await eval('OBJECT{name: "Alice"}'), isA<Object>());
        expect(await eval('x := "name"; {x: "Alice"}'), isA<Map>());
        expect(await eval('{42: "answer"}'), isA<Map>());
      }
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

    shqlTest('Nested objects have independent THIS — inner', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  outer.inner.getName()
''', 'inner');
    shqlTest('Nested objects have independent THIS — outer', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  outer.getName()
''', 'outer');

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

    shqlTestStdlib('Lambda calling NVL with parameter',
        'GET(hero, f, default) := NVL(hero, f, default); '
        'meta := OBJECT{accessor: (hero) => GET(hero, h => h.name, "none")}; '
        'person := OBJECT{name: "Bob"}; '
        'meta.accessor(person)', 'Bob');

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

    shqlTestStdlib('TRIM strips whitespace', 'TRIM("  hello  ")', 'hello');

    shqlTestStdlib('IS_NULL_OR_WHITESPACE returns true for null', 'IS_NULL_OR_WHITESPACE(null)', true);
    shqlTestStdlib('IS_NULL_OR_WHITESPACE returns true for whitespace-only', 'IS_NULL_OR_WHITESPACE("   ")', true);
    shqlTestStdlib('IS_NULL_OR_WHITESPACE returns false for non-blank string', 'IS_NULL_OR_WHITESPACE("batman")', false);

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

    shqlTestStdlib('GENERATE_SAVED_HEROES_CARDS with no conditions', r'''
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
''', []);
  });

  group('IF condition ending with parenthesised sub-expression', () {
    // Regression: the implicit-multiplication check consumed THEN as an
    // identifier after a single-element tuple, e.g. `AND (expr) THEN` would
    // swallow THEN, causing "Expected THEN after IF condition".
    shqlTest('IF x AND (y) THEN evaluates correctly', 'IF 1 = 1 AND (2 = 2) THEN "yes" ELSE "no"', 'yes');
    shqlTest('IF x AND (y) THEN — false branch', 'IF 1 = 1 AND (2 = 3) THEN "yes" ELSE "no"', 'no');
  });

  group('Implicit multiplication with value-expression keywords', () {
    shqlTest('(3)IF FALSE THEN 2 ELSE 3 = 9', '(3)IF FALSE THEN 2 ELSE 3', 9);
    shqlTest('(3)IF TRUE THEN 2 ELSE 0 = 6', '(3)IF TRUE THEN 2 ELSE 0', 6);
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
    shqlTest('null > number returns null', 'x := null; x > 5', null);
    shqlTest('null < number returns null', 'x := null; x < 5', null);
    shqlTest('null >= number returns null', 'x := null; x >= 5', null);
    shqlTest('null <= number returns null', 'x := null; x <= 5', null);
    shqlTest('number > null returns null', 'x := null; 5 > x', null);
  });

  group('AND treats null as falsy', () {
    shqlTest('null AND true is false', 'x := null; x AND TRUE', false);
    shqlTest('true AND null is false', 'x := null; TRUE AND x', false);
    shqlTest('null AND false is false', 'x := null; x AND FALSE', false);
    shqlTest('(null > 5) AND true is false', 'x := null; (x > 5) AND TRUE', false);
    shqlTest('(null > 5) AND (3 > 0) is false', 'x := null; (x > 5) AND (3 > 0)', false);
  });

  group('OR treats null as falsy', () {
    shqlTest('null OR true is true', 'x := null; x OR TRUE', true);
    shqlTest('null OR false is false', 'x := null; x OR FALSE', false);
    shqlTest('true OR null is true', 'x := null; TRUE OR x', true);
    shqlTest('false OR null is false', 'x := null; FALSE OR x', false);
  });

  group('NOT with null', () {
    shqlTest('NOT null returns null (null-aware unary)', 'x := null; NOT x', null);
  });

  group('XOR treats null as falsy', () {
    shqlTest('null XOR true is true', 'x := null; x XOR TRUE', true);
    shqlTest('null XOR false is false', 'x := null; x XOR FALSE', false);
    shqlTest('true XOR null is true', 'x := null; TRUE XOR x', true);
  });

  // The actual Giants bug: (null > avg + 2 * stdev) AND (stdev > 0)
  // should be false, not true.
  group('Giants predicate scenario — null height in boolean context', () {
    shqlTest('null height with positive stdev should not match',
        'height := null; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', false);
    shqlTest('tall height with positive stdev should match',
        'height := 2.5; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', true);
    shqlTest('short height with positive stdev should not match',
        'height := 1.7; avg := 1.78; stdev := 0.2; (height > avg + 2 * stdev) AND (stdev > 0)', false);
  });

  group('STATS() stdlib function', () {
    late Runtime runtime;
    late ConstantsSet constantsSet;
    late String stdlibCode;

    setUp(() async {
      constantsSet = Runtime.prepareConstantsSet();
      runtime = Runtime.prepareRuntime(constantsSet);
      stdlibCode = await File('assets/stdlib.shql').readAsString();
      await evalEngine(stdlibCode, runtime: runtime, constantsSet: constantsSet);
    });

    Future<dynamic> eval(String code) =>
        evalEngine(code, runtime: runtime, constantsSet: constantsSet);

    Future<dynamic> evalBc(String code) async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final combined = '$stdlibCode\n$code';
      final tree = Parser.parse(combined, cs, sourceCode: combined);
      final program = BytecodeCompiler.compile(tree, cs);
      return BytecodeInterpreter(program, rt).execute('main');
    }

    // Local equivalent of shqlTest using the group's stdlib-loaded eval/evalBc.
    void shqlBoth(String name, String code, dynamic expected) {
      test('$name [engine]', () async => expect(await eval(code), expected));
      test('$name [bytecode]', () async => expect(await evalBc(code), expected));
    }

    shqlBoth('returns zero object for empty list', r'''
      __s := STATS([], x => x);
      __s.COUNT = 0 AND __s.AVG = 0 AND __s.STDEV = 0 AND __s.SUM = 0
    ''', true);
    shqlBoth('avg of single value equals that value', 'STATS([42], x => x).AVG', 42);
    shqlBoth('stdev of single value is zero', 'STATS([42], x => x).STDEV', 0);
    shqlBoth('avg, sum, count of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      __s.AVG > 3.999 AND __s.AVG < 4.001 AND
      __s.SUM > 11.999 AND __s.SUM < 12.001 AND
      __s.COUNT = 3
    ''', true);
    shqlBoth('min and max of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      __s.MIN > 1.999 AND __s.MIN < 2.001 AND
      __s.MAX > 5.999 AND __s.MAX < 6.001
    ''', true);

    shqlBoth('population stdev of [2, 4, 6] is sqrt(8/3)',
        'STATS([2, 4, 6], x => x).STDEV', closeTo(1.6329931618554521, 0.00001));

    shqlBoth('nulls are excluded from all calculations', r'''
      __items := [OBJECT{v: 10}, OBJECT{v: null}, OBJECT{v: 20}];
      __s := STATS(__items, x => x.V);
      __s.AVG > 14.999 AND __s.AVG < 15.001 AND __s.COUNT = 2
    ''', true);
    shqlBoth('stdev of identical values is zero', 'STATS([5, 5, 5, 5], x => x).STDEV', 0);

    shqlBoth('accessor lambda extracts nested field', r'''
        __people := [OBJECT{height: 1.6}, OBJECT{height: 1.8}, OBJECT{height: 2.0}];
        STATS(__people, p => p.HEIGHT).AVG
      ''', closeTo(1.8, 0.0001));

    shqlBoth('all-null list returns zero count and zero avg', r'''
      __items := [OBJECT{v: null}, OBJECT{v: null}];
      __s := STATS(__items, x => x.V);
      __s.COUNT = 0 AND __s.AVG = 0
    ''', true);
  });
}
