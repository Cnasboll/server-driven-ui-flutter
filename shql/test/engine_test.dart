import 'package:shql/bytecode/bytecode_codec.dart';
import 'package:shql/bytecode/bytecode_compiler.dart';
import 'package:shql/bytecode/bytecode_interpreter.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/lookahead_iterator.dart';
import 'package:shql/parser/parser.dart';
import 'package:shql/testing/shql_test_runner.dart';
import 'package:shql/tokenizer/token.dart';
import 'package:shql/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

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
/// Runtime-registered functions (LENGTH, POW, SQRT, etc.) are bridged
/// automatically by [BytecodeInterpreter]'s constructor.
Future<dynamic> evalBytecode(
  String src, {
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
  return BytecodeInterpreter(decoded, runtime).executeScoped(
    'main',
    boundValues: boundValues,
    startingScope: startingScope,
  );
}


void main() {
  // ---- Parameterised helpers — run the assertion in both modes ---------------

  void shqlBoth(String name, String shql) {
    test('$name [engine]', () async {
      final h = ShqlTestRunner.withExpect(expect);
      await h.setUpTestOnly();
      await h.test(shql);
    });
    test('$name [bytecode]', () async {
      final h = ShqlTestRunner.bytecodeWithExpect(expect);
      await h.setUpTestOnly();
      await h.test(shql);
    });
  }

  void evalBoth(String name, String src, dynamic expected) {
    test('$name [engine]', () async => expect(await evalEngine(src), expected));
    test('$name [bytecode]', () async => expect(await evalBytecode(src), expected));
  }

  void shqlBothStdlib(String name, String shql) {
    test('$name [engine]', () async {
      final h = ShqlTestRunner.withExpect(expect);
      await h.setUp();
      await h.test(shql);
    });
    test('$name [bytecode]', () async {
      final h = ShqlTestRunner.bytecodeWithExpect(expect);
      await h.setUp();
      await h.test(shql);
    });
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

  shqlBoth('Execute addition', 'EXPECT(10+2, 12)');
  shqlBoth('Execute addition and multiplication', 'EXPECT(10+13*37+1, 492)');
  shqlBoth('Execute implicit constant multiplication with parenthesis', 'EXPECT(ANSWER(2), 84)');
  shqlBoth('Execute implicit constant multiplication with parenthesis first', 'EXPECT((2)ANSWER, 84)');
  shqlBoth('Execute implicit constant multiplication with constant within parenthesis first', 'EXPECT((ANSWER)2, 84)');
  shqlBoth('Execute implicit multiplication with parenthesis', 'EXPECT(2(3), 6)');
  shqlBoth('Execute addition and multiplication with parenthesis', 'EXPECT(10+13*(37+1), 504)');
  shqlBoth('Execute addition and implicit multiplication with parenthesis', 'EXPECT(10+13(37+1), 504)');
  shqlBoth('Execute addition, multiplication and subtraction', 'EXPECT(10+13*37-1, 490)');
  shqlBoth('Execute addition, implicit multiplication and subtraction', 'EXPECT(10+13(37)-1, 490)');
  shqlBoth('Execute addition, multiplication, subtraction and division', 'EXPECT(10+13*37/2-1, 249.5)');
  shqlBoth('Execute addition, implicit multiplication, subtraction and division', 'EXPECT(10+13(37)/2-1, 249.5)');

  shqlBoth('Execute modulus', 'EXPECT(9%2, 1)');
  shqlBoth('Execute equality true', 'ASSERT(5*2 = 2+8)');
  shqlBoth('Execute equality false', 'ASSERT_FALSE(5*2 = 1+8)');
  shqlBoth('Execute not equal true', 'ASSERT(5*2 <> 1+8)');
  shqlBoth('Execute not equal true with exclamation equals', 'ASSERT(5*2 != 1+8)');

  shqlBoth('Evaluate match — Superman regex', r'ASSERT("Super Man" ~  r"Super\s*Man")');
  shqlBoth('Evaluate match — Superman plain', r'ASSERT("Superman" ~  r"Super\s*Man")');
  shqlBoth('Evaluate match — Batman case-insensitive', 'ASSERT("Batman" ~  "batman")');
  shqlBoth('Evaluate match false — Bat Man', r'ASSERT_FALSE("Bat Man" ~  r"Super\s*Man")');
  shqlBoth('Evaluate match false — Batman', r'ASSERT_FALSE("Batman" ~  r"Super\s*Man")');
  shqlBoth('Evaluate mismatch true — Bat Man', r'ASSERT("Bat Man" !~  r"Super\s*Man")');
  shqlBoth('Evaluate mismatch true — Batman', r'ASSERT("Batman" !~  r"Super\s*Man")');
  shqlBoth('Evaluate mismatch false — Superman', r'ASSERT_FALSE("Super Man" !~  r"Super\s*Man")');
  shqlBoth('Evaluate mismatch false — Superman2', r'ASSERT_FALSE("Superman" !~  r"Super\s*Man")');

  shqlBoth('in list — Super Man found', 'ASSERT("Super Man" in ["Super Man", "Batman"])');
  shqlBoth('in list — Super Man found (finns_i)', 'ASSERT("Super Man" finns_i ["Super Man", "Batman"])');
  shqlBoth('in list — Batman found', 'ASSERT("Batman" in  ["Super Man", "Batman"])');
  shqlBoth('in list — Batman found (finns_i)', 'ASSERT("Batman" finns_i  ["Super Man", "Batman"])');
  shqlBoth('in list — Robin not found', 'ASSERT_FALSE("Robin" in  ["Super Man", "Batman"])');
  shqlBoth('in list — Superman not found', 'ASSERT_FALSE("Superman" in ["Super Man", "Batman"])');
  shqlBothStdlib('in list — lowercase Robin found', 'ASSERT(lowercase("Robin") in  ["batman", "robin"])');
  shqlBothStdlib('in list — lowercase Batman found', 'ASSERT(lowercase("Batman") in  ["batman", "robin"])');
  shqlBothStdlib('in list — lowercase robin not found', 'ASSERT_FALSE(lowercase("robin") in  ["super man", "batman"])');
  shqlBothStdlib('in list — lowercase robin not found (finns_i)', 'ASSERT_FALSE(lowercase("robin") finns_i  ["super man", "batman"])');
  shqlBothStdlib('in list — lowercase superman not found', 'ASSERT_FALSE(lowercase("superman") in  ["super man", "batman"])');
  shqlBothStdlib('in list — lowercase superman not found (finns_i)', 'ASSERT_FALSE(lowercase("superman") finns_i  ["super man", "batman"])');

  shqlBoth('Execute not equal false', 'ASSERT_FALSE(5*2 <> 2+8)');
  shqlBoth('Execute not equal false with exclamation equals', 'ASSERT_FALSE(5*2 != 2+8)');
  shqlBoth('Execute less than false', 'ASSERT_FALSE(10<1)');
  shqlBoth('Execute less than true', 'ASSERT(1<10)');
  shqlBoth('Execute less than or equal false', 'ASSERT_FALSE(10<=1)');
  shqlBoth('Execute less than or equal true', 'ASSERT(1<=10)');
  shqlBoth('Execute greater than false', 'ASSERT_FALSE(1>10)');
  shqlBoth('Execute greater than true', 'ASSERT(10>1)');
  shqlBoth('Execute greater than or equal false', 'ASSERT_FALSE(1>=10)');
  shqlBoth('Execute greater than or equal true', 'ASSERT(10>=1)');

  shqlBoth('AND true', 'ASSERT(1<10 AND 2<9)');
  shqlBoth('AND true (OCH)', 'ASSERT(1<10 OCH 2<9)');
  shqlBoth('AND false', 'ASSERT_FALSE(1>10 AND 2<9)');
  shqlBoth('AND false (OCH)', 'ASSERT_FALSE(1>10 OCH 2<9)');
  shqlBoth('OR true', 'ASSERT(1>10 OR 2<9)');
  shqlBoth('OR true (ELLER)', 'ASSERT(1>10 ELLER 2<9)');
  shqlBoth('XOR true', 'ASSERT(1>10 XOR 2<9)');
  shqlBoth('XOR true (ANTINGEN_ELLER)', 'ASSERT(1>10 ANTINGEN_ELLER 2<9)');
  shqlBoth('XOR false', 'ASSERT_FALSE(10>1 XOR 2<9)');
  shqlBoth('XOR false (ANTINGEN_ELLER)', 'ASSERT_FALSE(10>1 ANTINGEN_ELLER 2<9)');
  shqlBoth('NOT true number', 'ASSERT_FALSE(NOT 11)');
  shqlBoth('NOT true number (INTE)', 'ASSERT_FALSE(INTE 11)');

  shqlBoth('calculate_negation with exclamation', 'ASSERT_FALSE(!11)');
  shqlBoth('Execute unary minus', 'EXPECT(-5+11, 6)');
  shqlBoth('Execute unary plus', 'EXPECT(+5+11, 16)');
  shqlBoth('Execute with constants', 'EXPECT(PI * 2, ${3.1415926535897932 * 2})');
  shqlBoth('Execute with lowercase constants', 'EXPECT(pi * 2, ${3.1415926535897932 * 2})');

  shqlBothStdlib('Execute with functions', 'EXPECT(POW(2,2), 4)');
  shqlBothStdlib('Execute with two functions', 'EXPECT(POW(2,2)+SQRT(4), 6)');
  shqlBothStdlib('Calculate library function', 'EXPECT(SQRT(4), 2)');
  shqlBothStdlib('Execute nested function call', 'EXPECT(SQRT(POW(2,2)), 2)');
  shqlBothStdlib('Execute nested function call with expression', 'EXPECT(SQRT(POW(2,2)+10), 3.7416573867739413)');

  evalBoth('Execute two expressions', '10;11', 11);
  evalBoth('Execute two expressions with final semicolon', '10;11;', 11);
  shqlBoth('Test assignment', 'EXPECT(i:=42, 42)');
  shqlBoth('Test increment', 'i:=41; EXPECT(i:=i+1, 42)');

  test('Test function definition', () async {
    const src = 'f(x):=x*2';
    expect(await evalEngine(src), isA<UserFunction>());
    expect(await evalBytecode(src), isNotNull);
  });

  shqlBoth('Test user function', 'f(x):=x*2; EXPECT(f(2), 4)');
  shqlBoth('Test two argument user function', 'f(a,b):=a-b; EXPECT(f(10,2), 8)');
  shqlBoth('Test recursion', 'fac(x) := IF x <= 1 THEN 1 ELSE x * fac(x-1); EXPECT(fac(3), 6)');
  shqlBoth('Test while loop', 'x := 0; WHILE x < 10 DO x := x + 1; EXPECT(x, 10)');
  shqlBoth('Test lambda function', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; EXPECT(f1(sum, 1,2,3), 6)');
  shqlBoth('Test lambda function with user function argument', 'sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; EXPECT(f1(sum, 10,20,5), 35)');
  shqlBoth('Test lambda expression', 'f:= x => x^2; EXPECT(f(3), 9)');
  shqlBoth('Test anonymous lambda expression', 'EXPECT((x => x^2)(3), 9)');
  shqlBoth('Test nullary anonymous lambda expression', 'EXPECT((() => 9)(), 9)');
  shqlBoth('Test return', 'f(x) := IF x % 2 = 0 THEN RETURN x+1 ELSE RETURN x; EXPECT(f(2), 3)');
  shqlBoth('Test block return', 'f(x) := BEGIN IF x % 2 = 0 THEN RETURN x+1; RETURN x; END; EXPECT(f(2), 3)');
  shqlBoth('Test factorial with return', 'f(x) := BEGIN IF x <= 1 THEN RETURN 1; RETURN x * f(x-1); END; EXPECT(f(5), 120)');
  shqlBoth('Test break', 'x := 0; WHILE TRUE DO BEGIN x := x + 1; IF x = 10 THEN BREAK; END; EXPECT(x, 10)');
  shqlBoth('Test continue', 'x := 0; y := 0; WHILE x < 10 DO BEGIN x := x + 1; IF x % 2 = 0 THEN CONTINUE; y := y + 1; END; EXPECT(y, 5)');

  shqlBoth('FOR CONTINUE with IF', r'''
      __test() := BEGIN
        __result := [];
        FOR __i := 0 TO 2 DO BEGIN
          IF __i = 1 THEN CONTINUE;
          __result := __result + [__i];
        END;
        RETURN __result;
      END;
      EXPECT(__test(), [0, 2])
    ''');

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
      EXPECT(__test(), ['zero', 'after', 'skip', 'two', 'after'])
    ''');

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
      EXPECT(__test(), [0, 'skip', 2])
    ''');

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
      EXPECT(__test(), ['skipped', 'skipped', 'skipped'])
    ''');

  shqlBoth('Test repeat until', 'x := 0; REPEAT x := x + 1 UNTIL x = 10; EXPECT(x, 10)');
  shqlBoth('Test for loop', 'sum := 0; FOR i := 1 TO 10 DO sum := sum + i; EXPECT(sum, 55)');

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

    final hEngine = ShqlTestRunner.withExpect(expect);
    await hEngine.setUp();
    expect((await hEngine.test('$setup $q1')) is Map, true);
    expect((await hEngine.test('$setup $q2')) is Map, true);

    final hBytecode = ShqlTestRunner.bytecodeWithExpect(expect);
    await hBytecode.setUp();
    expect(await hBytecode.test('$setup $q1'), isA<Map>());
    expect(await hBytecode.test('$setup $q2'), isA<Map>());
  });

  shqlBoth('Test for loop with step', 'sum := 0; FOR i := 1 TO 10 STEP 2 DO sum := sum + i; EXPECT(sum, 25)');
  shqlBoth('Test for loop counting down', 'sum := 0; FOR i := 10 TO 1 STEP -1 DO sum := sum + i; EXPECT(sum, 55)');

  shqlBoth('Can assign to list variable', 'x := [1,2,3]; EXPECT(x[0], 1)');
  shqlBoth('Can assign to list member', 'x := [1,2,3]; x[1]:=4; EXPECT(x[1], 4)');

  shqlBoth('Can create thread', 'ASSERT(THREAD( () => 9 ) <> null)');

  shqlBoth('Can assign to map variable', "x := {'a':1,'b':2,'c':3}; EXPECT(x['a'], 1)");
  shqlBoth('Can assign to map member', "x := {'a':1,'b':2,'c':3}; x['b']:=4; EXPECT(x['b'], 4)");

  shqlBoth('Can start thread', "x := 0; t := THREAD( () => BEGIN FOR i := 1 TO 1000 DO x := x + 1; END ); JOIN(t); EXPECT(x, 1000)");

  shqlBoth('Global variable accessed in function',
      'my_global := 42; GET_GLOBAL() := my_global; EXPECT(GET_GLOBAL(), 42)');
  shqlBoth('Global variable modified in function',
      'my_global := 10; ADD_TO_GLOBAL(x) := BEGIN my_global := my_global + x; RETURN my_global; END; EXPECT(ADD_TO_GLOBAL(5), 15)');
  shqlBothStdlib('Global array accessed in function',
      'my_array := [1, 2, 3]; GET_LENGTH() := LENGTH(my_array); EXPECT(GET_LENGTH(), 3)');
  shqlBothStdlib('Global array modified in function — element at 3',
      'my_array := [1, 2, 3]; PUSH_TO_ARRAY(x) := BEGIN my_array := my_array + [x]; RETURN my_array; END; EXPECT(PUSH_TO_ARRAY(4)[3], 4)');
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
EXPECT(POP_ROUTE(), 'screen2')
''');

  shqlBoth('User function can access constants like TRUE', 'test() := TRUE; ASSERT(test())');

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

  group('startingScope and boundValues injection', () {
    test('boundValues visible in engine', () async {
      expect(await evalEngine('x + 1', boundValues: {'x': 10}), 11);
    });
    test('boundValues visible in bytecode', () async {
      expect(await evalBytecode('x + 1', boundValues: {'x': 10}), 11);
    });
    test('boundValues shadow global in engine', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      rt.globalScope.setVariable(cs.identifiers.include('X'), 99);
      expect(await evalEngine('x', runtime: rt, constantsSet: cs, boundValues: {'x': 42}), 42);
    });
    test('boundValues shadow global in bytecode', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      rt.globalScope.setVariable(cs.identifiers.include('X'), 99);
      expect(await evalBytecode('x', runtime: rt, cs: cs, boundValues: {'x': 42}), 42);
    });
    test('startingScope variables visible in engine', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('LABEL'), 'hello');
      expect(await evalEngine('label', runtime: rt, constantsSet: cs, startingScope: scope), 'hello');
    });
    test('startingScope variables visible in bytecode', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('LABEL'), 'hello');
      expect(await evalBytecode('label', cs: cs, runtime: rt, startingScope: scope), 'hello');
    });
    test('boundValues shadow startingScope in engine', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('X'), 1);
      expect(await evalEngine('x', runtime: rt, constantsSet: cs, startingScope: scope, boundValues: {'x': 2}), 2);
    });
    test('boundValues shadow startingScope in bytecode', () async {
      final cs = Runtime.prepareConstantsSet();
      final rt = Runtime.prepareRuntime(cs);
      final scope = Scope(Object(), parent: rt.globalScope);
      scope.setVariable(cs.identifiers.include('X'), 1);
      expect(await evalBytecode('x', cs: cs, runtime: rt, startingScope: scope, boundValues: {'x': 2}), 2);
    });
  });

  group('List utility functions', () {
    shqlBothStdlib('LENGTH of 3-element list', 'EXPECT(LENGTH([1, 2, 3]), 3)');
    shqlBothStdlib('LENGTH of empty list', 'EXPECT(LENGTH([]), 0)');
  });

  group('Object member access with dot operator', () {
    shqlBoth('Should access Object members using dot notation',
        'person := OBJECT{name: "Alice", age: 30}; EXPECT(person.name, "Alice"); EXPECT(person.age, 30)');
    shqlBoth('Should wrap Object in Scope for member access',
        'config := OBJECT{host: "localhost", port: 8080}; EXPECT(config.host, "localhost"); EXPECT(config.port, 8080)');
    shqlBoth('Should support nested object access (a.b.c.d)', '''
        db := OBJECT{host: "db.example.com", port: 5432};
        server := OBJECT{database: db, name: "prod-server"};
        app := OBJECT{server: server, version: "1.0.0"};
        EXPECT(app.server.database.host, "db.example.com");
        EXPECT(app.server.database.port, 5432);
        EXPECT(app.server.name, "prod-server");
        EXPECT(app.version, "1.0.0")
    ''');
  });

  group('Object literal with OBJECT keyword', () {
    shqlBoth('OBJECT literal keys are unquoted identifiers',
        'obj := OBJECT{name: "Alice", age: 30}; EXPECT(obj.name, "Alice"); EXPECT(obj.age, 30)');

    shqlBoth('Object literal dot — x', 'obj := OBJECT{x: 10, y: 20}; EXPECT(obj.x, 10)');
    shqlBoth('Object literal dot — y', 'obj := OBJECT{x: 10, y: 20}; EXPECT(obj.y, 20)');
    shqlBoth('Nested Objects — person.name', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; EXPECT(obj.person.name, \'Bob\')');
    shqlBoth('Nested Objects — person.age', 'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; EXPECT(obj.person.age, 25)');
    shqlBoth('Object complex value — list element', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; list := obj.list; EXPECT(list[1], 2)');
    shqlBoth('Object complex value — sum', 'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; EXPECT(obj.sum, 3)');
    shqlBoth('Object member assignment — x', 'obj := OBJECT{x: 10, y: 20}; obj.x := 100; EXPECT(obj.x, 100)');
    shqlBoth('Object member assignment — y', 'obj := OBJECT{x: 10, y: 20}; obj.y := 200; EXPECT(obj.y, 200)');

    test('Should distinguish Objects from Maps', () async {
      for (final eval in [evalEngine, evalBytecode]) {
        expect(await eval('OBJECT{name: "Alice"}'), isA<Object>());
        expect(await eval('x := "name"; {x: "Alice"}'), isA<Map>());
        expect(await eval('{42: "answer"}'), isA<Map>());
      }
    });

    shqlBoth('Should assign to nested Object members', 'obj := OBJECT{inner: OBJECT{value: 5}}; obj.inner.value := 42; EXPECT(obj.inner.value, 42)');
    shqlBoth('Should modify Object member and read it back', 'obj := OBJECT{counter: 0}; obj.counter := obj.counter + 1; EXPECT(obj.counter, 1)');
  });

  group('Object methods with proper scope', () {
    shqlBoth('Should access object members from method', 'obj := OBJECT{x: 10, getX: () => x}; EXPECT(obj.getX(), 10)');
    shqlBoth('Should access multiple object members from method', 'obj := OBJECT{x: 10, y: 20, sum: () => x + y}; EXPECT(obj.sum(), 30)');
    shqlBoth('Should modify object members from method', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); EXPECT(obj.counter, 1)');
    shqlBoth('Should call method multiple times and modify state', 'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.increment(); obj.increment(); EXPECT(obj.counter, 3)');
    shqlBoth('Should access method parameters and object members', 'obj := OBJECT{x: 10, add: (delta) => x + delta}; EXPECT(obj.add(5), 15)');
    shqlBoth('Should modify object member with parameter', 'obj := OBJECT{x: 10, setX: (newX) => x := newX}; obj.setX(42); EXPECT(obj.x, 42)');
    shqlBoth('Should access nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, getInnerValue: () => inner.value}; EXPECT(obj.getInnerValue(), 5)');
    shqlBoth('Should modify nested object members from method', 'obj := OBJECT{inner: OBJECT{value: 5}, incrementInner: () => inner.value := inner.value + 1}; obj.incrementInner(); EXPECT(obj.inner.value, 6)');
    shqlBoth('Method should have access to closure variables', 'outerVar := 100; obj := OBJECT{x: 10, addOuter: () => x + outerVar}; EXPECT(obj.addOuter(), 110)');
    shqlBoth('Method parameters should shadow object members', 'obj := OBJECT{x: 10, useParam: (x) => x}; EXPECT(obj.useParam(42), 42)');
    shqlBoth('Should support method calling another method', 'obj := OBJECT{x: 10, getX: () => x, doubleX: () => getX() * 2}; EXPECT(obj.doubleX(), 20)');

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
          EXPECT(obj.getCount(), 1)
          ''');
  });

  group('THIS self-reference in OBJECT', () {
    shqlBoth('THIS resolves to the object itself', '''
          obj := OBJECT{x: 10, getThis: () => THIS};
          EXPECT(obj.getThis().x, 10)
        ''');

    shqlBoth('THIS.field works for dot access', '''
          obj := OBJECT{x: 42, getX: () => THIS.x};
          EXPECT(obj.getX(), 42)
        ''');

    shqlBoth('THIS enables fluent/builder pattern', '''
          builder := OBJECT{
            value: 0,
            setValue: (v) => BEGIN value := v; RETURN THIS; END
          };
          EXPECT(builder.setValue(99).value, 99)
        ''');

    shqlBoth('Nested objects have independent THIS — inner', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  EXPECT(outer.inner.getName(), 'inner')
''');
    shqlBoth('Nested objects have independent THIS — outer', '''
  outer := OBJECT{
    name: "outer",
    inner: OBJECT{
      name: "inner",
      getName: () => THIS.name
    },
    getName: () => THIS.name
  };
  EXPECT(outer.getName(), 'outer')
''');

    shqlBoth('THIS is mutable (can be reassigned)', '''
          obj := OBJECT{x: 10, getX: () => THIS.x};
          EXPECT(obj.getX(), 10)
        ''');
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
          EXPECT(A.count, 15)
        ''');

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
          EXPECT(Filters.filter_counts, [])
        ''');
  });

  group('Null value handling', () {
    shqlBoth('Should distinguish between undefined and null variables', 'x := null; EXPECT(x, null)');
    shqlBoth('Should allow null in expressions', 'x := null; y := 5; ASSERT(x = null)');
    shqlBoth('Should allow calling functions with null arguments', 'f(x) := x; EXPECT(f(null), null)');
    shqlBoth('Should access object members that are null', 'obj := OBJECT{title: null}; EXPECT(obj.title, null)');
    shqlBoth('Should call object methods that return null', 'obj := OBJECT{getNull: () => null}; EXPECT(obj.getNull(), null)');
    shqlBoth('Should allow assigning null from map/list access', 'posts := [{"title": null}]; title := posts[0]["title"]; EXPECT(title, null)');
    shqlBoth('Should distinguish null value from missing key in map', 'm := {"a": null}; EXPECT(m["a"], null)');
  });

  group('Object literal with standalone lambda values', () {
    // These tests verify that lambda values stored in an OBJECT can be
    // retrieved and called from outside the object, with parameters binding
    // correctly (not referencing object members).

    shqlBoth('Parenthesized param — simple value', 'obj := OBJECT{accessor: (x) => x + 1}; EXPECT(obj.accessor(5), 6)');
    shqlBoth('Unparenthesized param — simple value', 'obj := OBJECT{accessor: x => x + 1}; EXPECT(obj.accessor(5), 6)');

    shqlBoth('Parenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: (p) => p.name}; '
        "EXPECT(meta.getName(person), 'Alice')");

    shqlBoth('Unparenthesized param — member access on parameter',
        'person := OBJECT{name: "Alice"}; '
        'meta := OBJECT{getName: p => p.name}; '
        "EXPECT(meta.getName(person), 'Alice')");

    shqlBothStdlib('Lambda calling NVL with parameter',
        'GET(hero, f, default) := NVL(hero, f, default); '
        'meta := OBJECT{accessor: (hero) => GET(hero, h => h.name, "none")}; '
        "person := OBJECT{name: \"Bob\"}; "
        "EXPECT(meta.accessor(person), 'Bob')");

    shqlBoth('Lambda stored in list of OBJECTs',
        'fields := [OBJECT{prop: "x", accessor: (v) => v + 10}]; '
        'EXPECT(fields[0].accessor(5), 15)');

    shqlBoth('Iterating OBJECT list and calling stored lambdas',
        'fields := ['
        '  OBJECT{prop: "a", accessor: (v) => v + 1},'
        '  OBJECT{prop: "b", accessor: (v) => v * 2}'
        ']; '
        'f0 := fields[0]; f1 := fields[1]; '
        'EXPECT(f0.accessor(10) + f1.accessor(10), 31)');

    shqlBothStdlib('TRIM strips whitespace', "EXPECT(TRIM(\"  hello  \"), 'hello')");

    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns true for null', 'ASSERT(IS_NULL_OR_WHITESPACE(null))');
    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns true for whitespace-only', 'ASSERT(IS_NULL_OR_WHITESPACE("   "))');
    shqlBothStdlib('IS_NULL_OR_WHITESPACE returns false for non-blank string', 'ASSERT_FALSE(IS_NULL_OR_WHITESPACE("batman"))');

    shqlBoth('Parenthesised IF-THEN-ELSE as value in map literal',
        'x := 1; '
        'obj := {"label": (IF x = 1 THEN "one" ELSE "other"), "score": 42}; '
        "EXPECT(obj[\"label\"], 'one')");

    shqlBoth('Parenthesised IF-THEN-ELSE as value in list of maps',
        'q := "batman"; '
        r'''result := [{"type": "Text", "data": (IF q <> "" THEN "no match: " + q ELSE "No match")}]; '''
        "EXPECT(result[0][\"data\"], 'no match: batman')");
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
        "EXPECT(f(), 'second')");

    shqlBoth('First IF RETURN with one-level map, second IF fires',
        'heroes := []; '
        'f() := BEGIN '
        '    IF 1 = 0 THEN '
        '        RETURN [{"type": "A", "data": "empty"}]; '
        '    IF 1 = 1 THEN '
        '        RETURN [{"type": "B", "data": "match"}]; '
        '    RETURN []; '
        'END; '
        'f()');

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
        'f()');

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
        'f()');

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
EXPECT(GENERATE_SAVED_HEROES_CARDS(), [])
''');
  });

  group('IF without ELSE branch', () {
    shqlBoth('IF FALSE THEN returns false', 'ASSERT_FALSE(IF FALSE THEN "FOO")');
    shqlBoth('IF TRUE THEN returns value', "EXPECT(IF TRUE THEN 'FOO', 'FOO')");
  });

  group('WHILE loop result', () {
    shqlBoth('WHILE that never executes returns false', 'ASSERT_FALSE(WHILE FALSE DO TRUE)');
    shqlBoth('WHILE returns last body expression', 'x := 0; EXPECT(WHILE x < 3 DO BEGIN x := x + 1; x^2 END, 9)');
  });

  group('IF condition ending with parenthesised sub-expression', () {
    // Regression: the implicit-multiplication check consumed THEN as an
    // identifier after a single-element tuple, e.g. `AND (expr) THEN` would
    // swallow THEN, causing "Expected THEN after IF condition".
    shqlBoth('IF x AND (y) THEN evaluates correctly', "EXPECT(IF 1 = 1 AND (2 = 2) THEN \"yes\" ELSE \"no\", 'yes')");
    shqlBoth('IF x AND (y) THEN — false branch', "EXPECT(IF 1 = 1 AND (2 = 3) THEN \"yes\" ELSE \"no\", 'no')");
  });

  group('Implicit multiplication with value-expression keywords', () {
    shqlBoth('(3)IF FALSE THEN 2 ELSE 3 = 9', 'EXPECT((3)IF FALSE THEN 2 ELSE 3, 9)');
    shqlBoth('(3)IF TRUE THEN 2 ELSE 0 = 6', 'EXPECT((3)IF TRUE THEN 2 ELSE 0, 6)');
  });

  group('(expr) followed by infix operator is NOT implicit multiplication', () {
    // (5)-3 must be subtraction (= 2), not 5 * (-3) = -15.
    // (5)+3 must be addition  (= 8), not 5 * (+3) =  15.
    shqlBoth('(5)-3 = 2', 'EXPECT((5)-3, 2)');
    shqlBoth('(5)+3 = 8', 'EXPECT((5)+3, 8)');
  });

  // Null-aware relational operators (>, <, >=, <=) return null when either
  // operand is null. Boolean operators (AND, OR, XOR) must treat null as
  // falsy — Dart's `null != 0` is `true`, but logically null means
  // "unknown / not applicable" and must not satisfy a condition.
  group('Null-aware relational operators return null', () {
    shqlBoth('null > number returns null', 'x := null; EXPECT(x > 5, null)');
    shqlBoth('null < number returns null', 'x := null; EXPECT(x < 5, null)');
    shqlBoth('null >= number returns null', 'x := null; EXPECT(x >= 5, null)');
    shqlBoth('null <= number returns null', 'x := null; EXPECT(x <= 5, null)');
    shqlBoth('number > null returns null', 'x := null; EXPECT(5 > x, null)');
  });

  group('AND treats null as falsy', () {
    shqlBoth('null AND true is false', 'x := null; ASSERT_FALSE(x AND TRUE)');
    shqlBoth('true AND null is false', 'x := null; ASSERT_FALSE(TRUE AND x)');
    shqlBoth('null AND false is false', 'x := null; ASSERT_FALSE(x AND FALSE)');
    shqlBoth('(null > 5) AND true is false', 'x := null; ASSERT_FALSE((x > 5) AND TRUE)');
    shqlBoth('(null > 5) AND (3 > 0) is false', 'x := null; ASSERT_FALSE((x > 5) AND (3 > 0))');
  });

  group('OR treats null as falsy', () {
    shqlBoth('null OR true is true', 'x := null; ASSERT(x OR TRUE)');
    shqlBoth('null OR false is false', 'x := null; ASSERT_FALSE(x OR FALSE)');
    shqlBoth('true OR null is true', 'x := null; ASSERT(TRUE OR x)');
    shqlBoth('false OR null is false', 'x := null; ASSERT_FALSE(FALSE OR x)');
  });

  group('NOT with null', () {
    shqlBoth('NOT null returns null (null-aware unary)', 'x := null; EXPECT(NOT x, null)');
  });

  group('XOR treats null as falsy', () {
    shqlBoth('null XOR true is true', 'x := null; ASSERT(x XOR TRUE)');
    shqlBoth('null XOR false is false', 'x := null; ASSERT_FALSE(x XOR FALSE)');
    shqlBoth('true XOR null is true', 'x := null; ASSERT(TRUE XOR x)');
  });

  // The actual Giants bug: (null > avg + 2 * stdev) AND (stdev > 0)
  // should be false, not true.
  group('Giants predicate scenario — null height in boolean context', () {
    shqlBoth('null height with positive stdev should not match',
        'height := null; avg := 1.78; stdev := 0.2; ASSERT_FALSE((height > avg + 2 * stdev) AND (stdev > 0))');
    shqlBoth('tall height with positive stdev should match',
        'height := 2.5; avg := 1.78; stdev := 0.2; ASSERT((height > avg + 2 * stdev) AND (stdev > 0))');
    shqlBoth('short height with positive stdev should not match',
        'height := 1.7; avg := 1.78; stdev := 0.2; ASSERT_FALSE((height > avg + 2 * stdev) AND (stdev > 0))');
  });

  group('STATS() stdlib function', () {
    shqlBothStdlib('returns zero object for empty list', r'''
      __s := STATS([], x => x);
      ASSERT(__s.COUNT = 0 AND __s.AVG = 0 AND __s.STDEV = 0 AND __s.SUM = 0)
    ''');
    shqlBothStdlib('avg of single value equals that value',
        'EXPECT(STATS([42], x => x).AVG, 42)');
    shqlBothStdlib('stdev of single value is zero',
        'EXPECT(STATS([42], x => x).STDEV, 0)');
    shqlBothStdlib('avg, sum, count of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      ASSERT(__s.AVG > 3.999 AND __s.AVG < 4.001 AND
             __s.SUM > 11.999 AND __s.SUM < 12.001 AND
             __s.COUNT = 3)
    ''');
    shqlBothStdlib('min and max of [2, 4, 6]', r'''
      __s := STATS([2, 4, 6], x => x);
      ASSERT(__s.MIN > 1.999 AND __s.MIN < 2.001 AND
             __s.MAX > 5.999 AND __s.MAX < 6.001)
    ''');
    shqlBothStdlib('population stdev of [2, 4, 6] is sqrt(8/3)', r'''
      __v := STATS([2, 4, 6], x => x).STDEV;
      ASSERT(__v > 1.63298 AND __v < 1.63301)
    ''');
    shqlBothStdlib('nulls are excluded from all calculations', r'''
      __items := [OBJECT{v: 10}, OBJECT{v: null}, OBJECT{v: 20}];
      __s := STATS(__items, x => x.V);
      ASSERT(__s.AVG > 14.999 AND __s.AVG < 15.001 AND __s.COUNT = 2)
    ''');
    shqlBothStdlib('stdev of identical values is zero',
        'EXPECT(STATS([5, 5, 5, 5], x => x).STDEV, 0)');
    shqlBothStdlib('accessor lambda extracts nested field', r'''
      __people := [OBJECT{height: 1.6}, OBJECT{height: 1.8}, OBJECT{height: 2.0}];
      __v := STATS(__people, p => p.HEIGHT).AVG;
      ASSERT(__v > 1.7999 AND __v < 1.8001)
    ''');
    shqlBothStdlib('all-null list returns zero count and zero avg', r'''
      __items := [OBJECT{v: null}, OBJECT{v: null}];
      __s := STATS(__items, x => x.V);
      ASSERT(__s.COUNT = 0 AND __s.AVG = 0)
    ''');
  });
}
