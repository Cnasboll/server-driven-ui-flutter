import 'dart:io';

import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';
import 'package:shql/parser/lookahead_iterator.dart';
import 'package:shql/parser/parser.dart';
import 'package:shql/tokenizer/token.dart';
import 'package:shql/tokenizer/tokenizer.dart';
import 'package:test/test.dart';

Future<(Runtime, ConstantsSet)> _loadStdLib() async {
  var constantsSet = Runtime.prepareConstantsSet();
  var runtime = Runtime.prepareRuntime(constantsSet);
  // Load stdlib
  final stdlibCode = await File('assets/stdlib.shql').readAsString();

  await Engine.execute(
    stdlibCode,
    runtime: runtime,
    constantsSet: constantsSet,
  );
  return (runtime, constantsSet);
}

void main() {
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

  test('Execute addition', () async {
    expect(await Engine.execute('10+2'), 12);
  });
  test('Execute addition and multiplication', () async {
    expect(await Engine.execute('10+13*37+1'), 492);
  });

  test('Execute implicit constant multiplication with parenthesis', () async {
    expect(await Engine.execute('ANSWER(2)'), 84);
  });

  test(
    'Execute implicit constant multiplication with parenthesis first',
    () async {
      expect(await Engine.execute('(2)ANSWER'), 84);
    },
  );

  test(
    'Execute implicit constant multiplication with constant within parenthesis first',
    () async {
      expect(await Engine.execute('(ANSWER)2'), 84);
    },
  );

  test('Execute implicit multiplication with parenthesis', () async {
    expect(await Engine.execute('2(3)'), 6);
  });

  test('Execute addition and multiplication with parenthesis', () async {
    expect(await Engine.execute('10+13*(37+1)'), 504);
  });

  test(
    'Execute addition and implicit multiplication with parenthesis',
    () async {
      expect(await Engine.execute('10+13(37+1)'), 504);
    },
  );

  test('Execute addition, multiplication and subtraction', () async {
    expect(await Engine.execute('10+13*37-1'), 490);
  });

  test('Execute addition, implicit multiplication and subtraction', () async {
    expect(await Engine.execute('10+13(37)-1'), 490);
  });

  test('Execute addition, multiplication, subtraction and division', () async {
    expect(await Engine.execute('10+13*37/2-1'), 249.5);
  });

  test('Execute addition, multiplication, subtraction and division', () async {
    expect(await Engine.execute('10+13*37/2-1'), 249.5);
  });

  test(
    'Execute addition, implicit multiplication, subtraction and division',
    () async {
      expect(await Engine.execute('10+13(37)/2-1'), 249.5);
    },
  );

  test('Execute modulus', () async {
    expect(await Engine.execute('9%2'), 1);
  });

  test('Execute equality true', () async {
    expect(await Engine.execute('5*2 = 2+8'), true);
  });

  test('Execute equality false', () async {
    expect(await Engine.execute('5*2 = 1+8'), false);
  });

  test('Execute not equal true', () async {
    expect(await Engine.execute('5*2 <> 1+8'), true);
  });

  test('Execute not equal true with exclamation equals', () async {
    expect(await Engine.execute('5*2 != 1+8'), true);
  });

  test('Evaluate match true', () async {
    expect(await Engine.execute('"Super Man" ~  r"Super\\s*Man"'), true);
    expect(await Engine.execute('"Superman" ~  r"Super\\s*Man"'), true);
    expect(await Engine.execute('"Batman" ~  "batman"'), true);
  });

  test('Evaluate match false', () async {
    expect(await Engine.execute('"Bat Man" ~  r"Super\\s*Man"'), false);
    expect(await Engine.execute('"Batman" ~  r"Super\\s*Man"'), false);
  });

  test('Evaluate mismatch true', () async {
    expect(await Engine.execute('"Bat Man" !~  r"Super\\s*Man"'), true);
    expect(await Engine.execute('"Batman" !~  r"Super\\s*Man"'), true);
  });

  test('Evaluate mismatch false', () async {
    expect(await Engine.execute('"Super Man" !~  r"Super\\s*Man"'), false);
    expect(await Engine.execute('"Superman" !~  r"Super\\s*Man"'), false);
  });

  test('Evaluate in list true', () async {
    expect(
      await Engine.execute('"Super Man" in ["Super Man", "Batman"]'),
      true,
    );
    expect(
      await Engine.execute('"Super Man" finns_i ["Super Man", "Batman"]'),
      true,
    );
    expect(await Engine.execute('"Batman" in  ["Super Man", "Batman"]'), true);
    expect(
      await Engine.execute('"Batman" finns_i  ["Super Man", "Batman"]'),
      true,
    );
  });

  test('Evaluate lower case in list true', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'lowercase("Robin") in  ["batman", "robin"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      true,
    );
    expect(
      await Engine.execute(
        'lowercase("Batman") in  ["batman", "robin"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      true,
    );
  });

  test('Evaluate in list false', () async {
    expect(await Engine.execute('"Robin" in  ["Super Man", "Batman"]'), false);
    expect(
      await Engine.execute('"Superman" in ["Super Man", "Batman"]'),
      false,
    );
  });

  test('Evaluate lower case in list false', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'lowercase("robin") in  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await Engine.execute(
        'lowercase("robin") finns_i  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await Engine.execute(
        'lowercase("superman") in  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
    expect(
      await Engine.execute(
        'lowercase("superman") finns_i  ["super man", "batman"]',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      false,
    );
  });

  test('Execute not equal false', () async {
    expect(await Engine.execute('5*2 <> 2+8'), false);
  });

  test('Execute not equal false with exclamation equals', () async {
    expect(await Engine.execute('5*2 != 2+8'), false);
  });

  test('Execute less than false', () async {
    expect(await Engine.execute('10<1'), false);
  });

  test('Execute less than true', () async {
    expect(await Engine.execute('1<10'), true);
  });

  test('Execute less than or equal false', () async {
    expect(await Engine.execute('10<=1'), false);
  });

  test('Execute less than or equal true', () async {
    expect(await Engine.execute('1<=10'), true);
  });

  test('Execute greater than false', () async {
    expect(await Engine.execute('1>10'), false);
  });

  test('Execute greater than true', () async {
    expect(await Engine.execute('10>1'), true);
  });

  test('Execute greater than or equal false', () async {
    expect(await Engine.execute('1>=10'), false);
  });

  test('Execute greater than or equal true', () async {
    expect(await Engine.execute('10>=1'), true);
  });

  test('Execute some boolean algebra and true', () async {
    expect(await Engine.execute('1<10 AND 2<9'), true);
    expect(await Engine.execute('1<10 OCH 2<9'), true);
  });

  test('Execute some boolean algebra and false', () async {
    expect(await Engine.execute('1>10 AND 2<9'), false);
    expect(await Engine.execute('1>10 OCH 2<9'), false);
  });

  test('Execute some boolean algebra or true', () async {
    expect(await Engine.execute('1>10 OR 2<9'), true);
    expect(await Engine.execute('1>10 ELLER 2<9'), true);
  });

  test('Execute some boolean algebra xor true', () async {
    expect(await Engine.execute('1>10 XOR 2<9'), true);
    expect(await Engine.execute('1>10 ANTINGEN_ELLER 2<9'), true);
  });

  test('calculate_some_bool_algebra_xor_false', () async {
    expect(await Engine.execute('10>1 XOR 2<9'), false);
    expect(await Engine.execute('10>1 ANTINGEN_ELLER 2<9'), false);
  });

  test('calculate_negation', () async {
    expect(await Engine.execute('NOT 11'), false);
    expect(await Engine.execute('INTE 11'), false);
  });

  test('calculate_negation with exclamation', () async {
    expect(await Engine.execute('!11'), false);
  });

  test('Execute unary minus', () async {
    expect(await Engine.execute('-5+11'), 6);
  });

  test('Execute unary plus', () async {
    expect(await Engine.execute('+5+11'), 16);
  });

  test('Execute with constants', () async {
    expect(await Engine.execute('PI * 2'), 3.1415926535897932 * 2);
  });

  test('Execute with lowercase constants', () async {
    expect(await Engine.execute('pi * 2'), 3.1415926535897932 * 2);
  });

  test('Execute with functions', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'POW(2,2)',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      4,
    );
  });

  test('Execute with two functions', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'POW(2,2)+SQRT(4)',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      6,
    );
  });

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

  test('Execute nested function call', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'SQRT(POW(2,2))',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      2,
    );
  });

  test('Execute nested function call with expression', () async {
    var (runtime, constantsSet) = await _loadStdLib();
    expect(
      await Engine.execute(
        'SQRT(POW(2,2)+10)',
        runtime: runtime,
        constantsSet: constantsSet,
      ),
      3.7416573867739413,
    );
  });

  test('Execute two expressions', () async {
    expect(await Engine.execute('10;11'), 11);
  });
  test('Execute two expressions with final semicolon', () async {
    expect(await Engine.execute('10;11;'), 11);
  });

  test('Test assignment', () async {
    expect(await Engine.execute('i:=42'), 42);
  });

  test('Test increment', () async {
    expect(await Engine.execute('i:=41;i:=i+1'), 42);
  });

  test('Test function definition', () async {
    expect((await Engine.execute('f(x):=x*2')).runtimeType, UserFunction);
  });

  test('Test user function', () async {
    expect((await Engine.execute('f(x):=x*2;f(2)')), 4);
  });

  test('Test two argument user function', () async {
    expect((await Engine.execute('f(a,b):=a-b;f(10,2)')), 8);
  });

  test('Test recursion', () async {
    expect(
      (await Engine.execute(
        'fac(x) := IF x <= 1 THEN 1 ELSE x * fac(x-1);fac(3)',
      )),
      6,
    );
  });

  test('Test while loop', () async {
    expect((await Engine.execute('x := 0; WHILE x < 10 DO x := x + 1;x')), 10);
  });

  test('Test lambda function', () async {
    expect(
      (await Engine.execute(
        "sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 1,2,3)",
      )),
      6,
    );
  });

  test('Test lambda function with user function argument', () async {
    expect(
      (await Engine.execute(
        "sum(a,b) := a+b; f1(f,a,b,c) := f(a,b)+c; f1(sum, 10,20,5)",
      )),
      35,
    );
  });

  test('Test lambda expression', () async {
    expect((await Engine.execute("f:= x => x^2;f(3)")), 9);
  });

  test('Test anonymous lambda expression', () async {
    expect((await Engine.execute("(x => x^2)(3)")), 9);
  });

  test('Test nullary anonymous lambda expression', () async {
    expect((await Engine.execute("(() => 9)()")), 9);
  });

  test("Test return", () async {
    expect(
      (await Engine.execute(
        "f(x) := IF x % 2 = 0 THEN RETURN x+1 ELSE RETURN x; f(2)",
      )),
      3,
    );
  });

  test("Test block return", () async {
    expect(
      (await Engine.execute(
        "f(x) := BEGIN IF x % 2 = 0 THEN RETURN x+1; RETURN x; END; f(2)",
      )),
      3,
    );
  });

  test("Test factorial with return", () async {
    expect(
      (await Engine.execute(
        "f(x) := BEGIN IF x <= 1 THEN RETURN 1; RETURN x * f(x-1); END; f(5)",
      )),
      120,
    );
  });

  test("Test break", () async {
    expect(
      (await Engine.execute(
        "x := 0; WHILE TRUE DO BEGIN x := x + 1; IF x = 10 THEN BREAK; END; x",
      )),
      10,
    );
  });

  test("Test continue", () async {
    expect(
      (await Engine.execute(
        "x := 0; y := 0; WHILE x < 10 DO BEGIN x := x + 1; IF x % 2 = 0 THEN CONTINUE; y := y + 1; END; y",
      )),
      5,
    );
  });

  test("Test repeat until", () async {
    expect(
      (await Engine.execute("x := 0; REPEAT x := x + 1 UNTIL x = 10; x")),
      10,
    );
  });

  test("Test for loop", () async {
    expect(
      (await Engine.execute(
        "sum := 0; FOR i := 1 TO 10 DO sum := sum + i; sum",
      )),
      55,
    );
  });

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
    await Engine.execute(
      listUtilsCodde,
      runtime: runtime,
      constantsSet: constantsSet,
    );
    await Engine.execute(
      "list := [_GEN_LIST_ITEM_TEMPLATE(1)];",
      runtime: runtime,
      constantsSet: constantsSet,
    );
    expect(
      (await Engine.execute(
            "list[0]",
            runtime: runtime,
            constantsSet: constantsSet,
          )
          is Map),
      true,
    );
    expect(
      (await Engine.execute(
            "list[0]['props']",
            runtime: runtime,
            constantsSet: constantsSet,
          )
          is Map),
      true,
    );
  });

  test("Test for loop with step", () async {
    expect(
      (await Engine.execute(
        "sum := 0; FOR i := 1 TO 10 STEP 2 DO sum := sum + i; sum",
      )),
      25,
    );
  });

  test("Test for loop counting down", () async {
    expect(
      (await Engine.execute(
        "sum := 0; FOR i := 10 TO 1 STEP -1 DO sum := sum + i; sum",
      )),
      55,
    );
  });

  test("Can assign to list variable", () async {
    expect((await Engine.execute("x := [1,2,3];x[0]")), 1);
  });
  test("Can assign to list member", () async {
    expect((await Engine.execute("x := [1,2,3];x[1]:=4;x[1]")), 4);
  });

  test("Can create thread", () async {
    expect((await Engine.execute("THREAD( () => 9 )")) is Thread, true);
  });

  test("Can assign to map variable", () async {
    expect((await Engine.execute("x := {'a':1,'b':2,'c':3};x['a']")), 1);
  });
  test("Can assign to map member", () async {
    expect(
      (await Engine.execute("x := {'a':1,'b':2,'c':3};x['b']:=4;x['b']")),
      4,
    );
  });

  test("Can start thread", () async {
    expect(
      (await Engine.execute(
        "x := 0; t := THREAD( () => BEGIN FOR i := 1 TO 1000 DO x := x + 1; END ); JOIN(t); x",
      )),
      1000,
    );
  });

  // Global variable tests
  test("Global variable accessed in function", () async {
    var constantsSet = Runtime.prepareConstantsSet();
    var runtime = Runtime.prepareRuntime(constantsSet);
    final code = """
      my_global := 42;
      GET_GLOBAL() := my_global;
      GET_GLOBAL()
    """;
    expect(
      await Engine.execute(code, runtime: runtime, constantsSet: constantsSet),
      42,
    );
  });

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
      await Engine.execute(code, runtime: runtime, constantsSet: constantsSet),
      15,
    );
  });

  test("Global array accessed in function", () async {
    var (runtime, constantsSet) = await _loadStdLib();
    final code = """
      my_array := [1, 2, 3];
      GET_LENGTH() := LENGTH(my_array);
      GET_LENGTH()
    """;
    expect(
      await Engine.execute(code, runtime: runtime, constantsSet: constantsSet),
      3,
    );
  });

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
    final result = await Engine.execute(
      code,
      runtime: runtime,
      constantsSet: constantsSet,
    );
    expect(result is List, true);
    expect((result as List).length, 4);
    expect(result[3], 4);
  });

  // Navigation stack pattern test
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
      await Engine.execute(code, runtime: runtime, constantsSet: constantsSet),
      'screen2',
    );
  });

  test('User function can access constants like TRUE', () async {
    // Minimal test: define function that returns TRUE, then call it
    expect(await Engine.execute('test() := TRUE; test()'), true);
  });

  group('Error reporting tests', () {
    test('Should show correct line numbers in error messages', () async {
      final constantsSet = Runtime.prepareConstantsSet();
      final runtime = Runtime.prepareRuntime(constantsSet);

      try {
        // Define a function that calls an undefined function
        await Engine.execute(
          "test() := undefinedFunction();",
          constantsSet: constantsSet,
          runtime: runtime,
        );

        // Try to call it - this should fail because undefinedFunction doesn't exist
        await Engine.execute(
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
    test('LENGTH should return list length', () async {
      final (runtime, constantsSet) = await _loadStdLib();
      expect(
        await Engine.execute(
          'LENGTH([1, 2, 3])',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        3,
      );
      expect(
        await Engine.execute(
          'LENGTH([])',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        0,
      );
    });
  });

  group('Object member access with dot operator', () {
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
        await Engine.execute(
          'person.name',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'Alice',
      );

      expect(
        await Engine.execute(
          'person.age',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        30,
      );
    });

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
        await Engine.execute(
          'config.host',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'localhost',
      );

      expect(
        await Engine.execute(
          'config.port',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        8080,
      );
    });

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
        await Engine.execute(
          'app.server.database.host',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'db.example.com',
      );

      // Test nested access: app.server.database.port
      expect(
        await Engine.execute(
          'app.server.database.port',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        5432,
      );

      // Test partial access: app.server.name
      expect(
        await Engine.execute(
          'app.server.name',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        'prod-server',
      );

      // Test shallow access: app.version
      expect(
        await Engine.execute(
          'app.version',
          runtime: runtime,
          constantsSet: constantsSet,
        ),
        '1.0.0',
      );
    });
  });

  group('Object literal with OBJECT keyword', () {
    test('Should create Object with bare identifier keys', () async {
      final result = await Engine.execute('OBJECT{name: "Alice", age: 30}');
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

    test('Should access Object literal members with dot notation', () async {
      expect(await Engine.execute('obj := OBJECT{x: 10, y: 20}; obj.x'), 10);

      expect(await Engine.execute('obj := OBJECT{x: 10, y: 20}; obj.y'), 20);
    });

    test('Should create nested Objects', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.name',
        ),
        'Bob',
      );

      expect(
        await Engine.execute(
          'obj := OBJECT{person: OBJECT{name: "Bob", age: 25}}; obj.person.age',
        ),
        25,
      );
    });

    test('Should distinguish Objects from Maps', () async {
      // Object with bare identifier keys
      final obj = await Engine.execute('OBJECT{name: "Alice"}');
      expect(obj, isA<Object>());

      // Map with evaluated expression keys
      final map = await Engine.execute('x := "name"; {x: "Alice"}');
      expect(map, isA<Map>());

      // Map with literal number keys
      final map2 = await Engine.execute('{42: "answer"}');
      expect(map2, isA<Map>());
    });

    test('Should create Object with complex values', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; list := obj.list; list[1]',
        ),
        2,
      );

      expect(
        await Engine.execute(
          'obj := OBJECT{list: [1, 2, 3], sum: 1 + 2}; obj.sum',
        ),
        3,
      );
    });

    test('Should assign to Object members', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, y: 20}; obj.x := 100; obj.x',
        ),
        100,
      );

      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, y: 20}; obj.y := 200; obj.y',
        ),
        200,
      );
    });

    test('Should assign to nested Object members', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{inner: OBJECT{value: 5}}; obj.inner.value := 42; obj.inner.value',
        ),
        42,
      );
    });

    test('Should modify Object member and read it back', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{counter: 0}; obj.counter := obj.counter + 1; obj.counter',
        ),
        1,
      );
    });
  });

  group('Object methods with proper scope', () {
    test('Should access object members from method', () async {
      expect(
        await Engine.execute('obj := OBJECT{x: 10, getX: () => x}; obj.getX()'),
        10,
      );
    });

    test('Should access multiple object members from method', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, y: 20, sum: () => x + y}; obj.sum()',
        ),
        30,
      );
    });

    test('Should modify object members from method', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.counter',
        ),
        1,
      );
    });

    test('Should call method multiple times and modify state', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{counter: 0, increment: () => counter := counter + 1}; obj.increment(); obj.increment(); obj.increment(); obj.counter',
        ),
        3,
      );
    });

    test('Should access method parameters and object members', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, add: (delta) => x + delta}; obj.add(5)',
        ),
        15,
      );
    });

    test('Should modify object member with parameter', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, setX: (newX) => x := newX}; obj.setX(42); obj.x',
        ),
        42,
      );
    });

    test('Should access nested object members from method', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{inner: OBJECT{value: 5}, getInnerValue: () => inner.value}; obj.getInnerValue()',
        ),
        5,
      );
    });

    test('Should modify nested object members from method', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{inner: OBJECT{value: 5}, incrementInner: () => inner.value := inner.value + 1}; obj.incrementInner(); obj.inner.value',
        ),
        6,
      );
    });

    test('Method should have access to closure variables', () async {
      expect(
        await Engine.execute(
          'outerVar := 100; obj := OBJECT{x: 10, addOuter: () => x + outerVar}; obj.addOuter()',
        ),
        110,
      );
    });

    test('Method parameters should shadow object members', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, useParam: (x) => x}; obj.useParam(42)',
        ),
        42,
      );
    });

    test('Should support method calling another method', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{x: 10, getX: () => x, doubleX: () => getX() * 2}; obj.doubleX()',
        ),
        20,
      );
    });

    test('Should create object with counter and multiple methods', () async {
      expect(
        await Engine.execute('''
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
          '''),
        1,
      );
    });
  });

  group('THIS self-reference in OBJECT', () {
    test('THIS resolves to the object itself', () async {
      // getThis() returns THIS, and we verify it has the same field x
      expect(
        await Engine.execute('''
          obj := OBJECT{x: 10, getThis: () => THIS};
          obj.getThis().x
        '''),
        10,
      );
    });

    test('THIS.field works for dot access', () async {
      expect(
        await Engine.execute('''
          obj := OBJECT{x: 42, getX: () => THIS.x};
          obj.getX()
        '''),
        42,
      );
    });

    test('THIS enables fluent/builder pattern', () async {
      expect(
        await Engine.execute('''
          builder := OBJECT{
            value: 0,
            setValue: (v) => BEGIN value := v; RETURN THIS; END
          };
          builder.setValue(99).value
        '''),
        99,
      );
    });

    test('Nested objects have independent THIS', () async {
      expect(
        await Engine.execute('''
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
        await Engine.execute('''
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

    test('THIS is mutable (can be reassigned)', () async {
      // THIS is a variable, not a constant — users CAN reassign it
      // but that is their choice (like any other variable)
      expect(
        await Engine.execute('''
          obj := OBJECT{x: 10, getX: () => THIS.x};
          obj.getX()
        '''),
        10,
      );
    });
  });

  group('Cross-object member access', () {
    test('Object B method can access Object A members via global', () async {
      expect(
        await Engine.execute('''
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
        '''),
        15,
      );
    });

    test('Field name colliding with global name (case-insensitive) from external scope', () async {
      // Filters object has a field "filters" which uppercases to FILTERS
      // The global "Filters" also uppercases to FILTERS
      // From a DIFFERENT object's method, "Filters" should resolve to the global (the Object)
      expect(
        await Engine.execute('''
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
        '''),
        [],
      );
    });
  });

  group('Null value handling', () {
    test('Should distinguish between undefined and null variables', () async {
      expect(await Engine.execute('x := null; x'), null);
    });

    test('Should allow null in expressions', () async {
      expect(await Engine.execute('x := null; y := 5; x = null'), true);
    });

    test('Should allow calling functions with null arguments', () async {
      expect(await Engine.execute('f(x) := x; f(null)'), null);
    });

    test('Should access object members that are null', () async {
      expect(
        await Engine.execute('obj := OBJECT{title: null}; obj.title'),
        null,
      );
    });

    test('Should call object methods that return null', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{getNull: () => null}; obj.getNull()',
        ),
        null,
      );
    });

    test('Should allow assigning null from map/list access', () async {
      expect(
        await Engine.execute(
          'posts := [{"title": null}]; title := posts[0]["title"]; title',
        ),
        null,
      );
    });

    test('Should distinguish null value from missing key in map', () async {
      expect(await Engine.execute('m := {"a": null}; m["a"]'), null);
    });
  });

  group('Object literal with standalone lambda values', () {
    // These tests verify that lambda values stored in an OBJECT can be
    // retrieved and called from outside the object, with parameters binding
    // correctly (not referencing object members).

    test('Parenthesized param — simple value', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{accessor: (x) => x + 1}; obj.accessor(5)',
        ),
        6,
      );
    });

    test('Unparenthesized param — simple value', () async {
      expect(
        await Engine.execute(
          'obj := OBJECT{accessor: x => x + 1}; obj.accessor(5)',
        ),
        6,
      );
    });

    test('Parenthesized param — member access on parameter', () async {
      expect(
        await Engine.execute(
          'person := OBJECT{name: "Alice"}; '
          'meta := OBJECT{getName: (p) => p.name}; '
          'meta.getName(person)',
        ),
        'Alice',
      );
    });

    test('Unparenthesized param — member access on parameter', () async {
      expect(
        await Engine.execute(
          'person := OBJECT{name: "Alice"}; '
          'meta := OBJECT{getName: p => p.name}; '
          'meta.getName(person)',
        ),
        'Alice',
      );
    });

    test('Lambda calling another function with its parameter', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await Engine.execute(
        stdlibCode,
        runtime: runtime,
        constantsSet: constantsSet,
      );

      expect(
        await Engine.execute(
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

    test('Lambda stored in list of OBJECTs', () async {
      expect(
        await Engine.execute(
          'fields := [OBJECT{prop: "x", accessor: (v) => v + 10}]; '
          'fields[0].accessor(5)',
        ),
        15,
      );
    });

    test('Iterating OBJECT list and calling stored lambdas', () async {
      expect(
        await Engine.execute(
          'fields := ['
          '  OBJECT{prop: "a", accessor: (v) => v + 1},'
          '  OBJECT{prop: "b", accessor: (v) => v * 2}'
          ']; '
          'f0 := fields[0]; f1 := fields[1]; '
          'f0.accessor(10) + f1.accessor(10)',
        ),
        31, // (10+1) + (10*2) = 11 + 20 = 31
      );
    });

    test('TRIM strips whitespace', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await Engine.execute(stdlibCode, runtime: runtime, constantsSet: constantsSet);

      expect(
        await Engine.execute('TRIM("  hello  ")', runtime: runtime, constantsSet: constantsSet),
        'hello',
      );
    });

    test('IS_NULL_OR_WHITESPACE returns true for null', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await Engine.execute(stdlibCode, runtime: runtime, constantsSet: constantsSet);

      expect(
        await Engine.execute('IS_NULL_OR_WHITESPACE(null)', runtime: runtime, constantsSet: constantsSet),
        true,
      );
    });

    test('IS_NULL_OR_WHITESPACE returns true for whitespace-only', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await Engine.execute(stdlibCode, runtime: runtime, constantsSet: constantsSet);

      expect(
        await Engine.execute('IS_NULL_OR_WHITESPACE("   ")', runtime: runtime, constantsSet: constantsSet),
        true,
      );
    });

    test('IS_NULL_OR_WHITESPACE returns false for non-blank string', () async {
      var constantsSet = Runtime.prepareConstantsSet();
      var runtime = Runtime.prepareRuntime(constantsSet);
      final stdlibCode = await File('assets/stdlib.shql').readAsString();
      await Engine.execute(stdlibCode, runtime: runtime, constantsSet: constantsSet);

      expect(
        await Engine.execute('IS_NULL_OR_WHITESPACE("batman")', runtime: runtime, constantsSet: constantsSet),
        false,
      );
    });

    test('Parenthesised IF-THEN-ELSE as value in map literal', () async {
      // Regression: bare IF-THEN-ELSE inside {"key": IF...} caused ParseException
      // ("Expected THEN after IF condition") because the ELSE clause consumed the
      // trailing comma. Wrapping in () makes the ternary a self-contained tuple.
      expect(
        await Engine.execute(
          'x := 1; '
          'obj := {"label": (IF x = 1 THEN "one" ELSE "other"), "score": 42}; '
          'obj["label"]',
        ),
        'one',
      );
    });

    test('Parenthesised IF-THEN-ELSE as value in list of maps', () async {
      // Same regression in a list context: RETURN [{... "data": (IF...) ...}]
      expect(
        await Engine.execute(
          'q := "batman"; '
          r'''result := [{"type": "Text", "data": (IF q <> "" THEN "no match: " + q ELSE "No match")}]; '''
          'result[0]["data"]',
        ),
        'no match: batman',
      );
    });
  });

  // Regression tests: two sequential IF statements where the first IF's THEN
  // body is RETURN with a deeply nested JSON structure (like herodex.shql
  // GENERATE_SAVED_HEROES_CARDS). Caused "Expected THEN after IF condition".
  group('Two sequential IFs — first RETURN with nested JSON', () {
    test('Two simple IFs in BEGIN — baseline', () async {
      expect(
        await Engine.execute(
          'f() := BEGIN '
          '    IF 1 = 0 THEN RETURN "first"; '
          '    IF 1 = 1 THEN RETURN "second"; '
          '    RETURN "third"; '
          'END; '
          'f()',
        ),
        'second',
      );
    });

    test('First IF RETURN with one-level map, second IF fires', () async {
      expect(
        await Engine.execute(
          'heroes := []; '
          'f() := BEGIN '
          '    IF 1 = 0 THEN '
          '        RETURN [{"type": "A", "data": "empty"}]; '
          '    IF 1 = 1 THEN '
          '        RETURN [{"type": "B", "data": "match"}]; '
          '    RETURN []; '
          'END; '
          'f()',
        ),
        isA<List>(),
      );
    });

    test('First IF RETURN with two-level nesting, second IF parses', () async {
      expect(
        await Engine.execute(
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
        ),
        isA<List>(),
      );
    });

    test('First IF RETURN with three-level nesting, second IF parses', () async {
      expect(
        await Engine.execute(
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
        ),
        isA<List>(),
      );
    });

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
        await Engine.execute(code, runtime: runtime, constantsSet: constantsSet),
        isA<List>(),
      );
    });
  });

  group('IF condition ending with parenthesised sub-expression', () {
    // Regression: the implicit-multiplication check consumed THEN as an
    // identifier after a single-element tuple, e.g. `AND (expr) THEN` would
    // swallow THEN, causing "Expected THEN after IF condition".
    test('IF x AND (y) THEN evaluates correctly', () async {
      expect(await Engine.execute('IF 1 = 1 AND (2 = 2) THEN "yes" ELSE "no"'), 'yes');
    });

    test('IF x AND (y) THEN — false branch', () async {
      expect(await Engine.execute('IF 1 = 1 AND (2 = 3) THEN "yes" ELSE "no"'), 'no');
    });
  });

  group('Implicit multiplication with value-expression keywords', () {
    test('(3)IF FALSE THEN 2 ELSE 3 = 9', () async {
      expect(await Engine.execute('(3)IF FALSE THEN 2 ELSE 3'), 9);
    });

    test('(3)IF TRUE THEN 2 ELSE 0 = 6', () async {
      expect(await Engine.execute('(3)IF TRUE THEN 2 ELSE 0'), 6);
    });
  });

  group('(expr) followed by infix operator is NOT implicit multiplication', () {
    // (5)-3 must be subtraction (= 2), not 5 * (-3) = -15.
    // (5)+3 must be addition  (= 8), not 5 * (+3) =  15.
    test('(5)-3 = 2', () async {
      expect(await Engine.execute('(5)-3'), 2);
    });

    test('(5)+3 = 8', () async {
      expect(await Engine.execute('(5)+3'), 8);
    });
  });

  // Null-aware relational operators (>, <, >=, <=) return null when either
  // operand is null. Boolean operators (AND, OR, XOR) must treat null as
  // falsy — Dart's `null != 0` is `true`, but logically null means
  // "unknown / not applicable" and must not satisfy a condition.
  group('Null-aware relational operators return null', () {
    test('null > number returns null', () async {
      expect(await Engine.execute('x > 5', boundValues: {'x': null}), isNull);
    });

    test('null < number returns null', () async {
      expect(await Engine.execute('x < 5', boundValues: {'x': null}), isNull);
    });

    test('null >= number returns null', () async {
      expect(await Engine.execute('x >= 5', boundValues: {'x': null}), isNull);
    });

    test('null <= number returns null', () async {
      expect(await Engine.execute('x <= 5', boundValues: {'x': null}), isNull);
    });

    test('number > null returns null', () async {
      expect(await Engine.execute('5 > x', boundValues: {'x': null}), isNull);
    });
  });

  group('AND treats null as falsy', () {
    test('null AND true is false', () async {
      expect(await Engine.execute('x AND TRUE', boundValues: {'x': null}), false);
    });

    test('true AND null is false', () async {
      expect(await Engine.execute('TRUE AND x', boundValues: {'x': null}), false);
    });

    test('null AND false is false', () async {
      expect(await Engine.execute('x AND FALSE', boundValues: {'x': null}), false);
    });

    test('(null > 5) AND true is false', () async {
      expect(await Engine.execute('(x > 5) AND TRUE', boundValues: {'x': null}), false);
    });

    test('(null > 5) AND (3 > 0) is false', () async {
      expect(await Engine.execute('(x > 5) AND (3 > 0)', boundValues: {'x': null}), false);
    });
  });

  group('OR treats null as falsy', () {
    test('null OR true is true', () async {
      expect(await Engine.execute('x OR TRUE', boundValues: {'x': null}), true);
    });

    test('null OR false is false', () async {
      expect(await Engine.execute('x OR FALSE', boundValues: {'x': null}), false);
    });

    test('true OR null is true', () async {
      expect(await Engine.execute('TRUE OR x', boundValues: {'x': null}), true);
    });

    test('false OR null is false', () async {
      expect(await Engine.execute('FALSE OR x', boundValues: {'x': null}), false);
    });
  });

  group('NOT with null', () {
    test('NOT null returns null (null-aware unary)', () async {
      expect(await Engine.execute('NOT x', boundValues: {'x': null}), isNull);
    });
  });

  group('XOR treats null as falsy', () {
    test('null XOR true is true', () async {
      expect(await Engine.execute('x XOR TRUE', boundValues: {'x': null}), true);
    });

    test('null XOR false is false', () async {
      expect(await Engine.execute('x XOR FALSE', boundValues: {'x': null}), false);
    });

    test('true XOR null is true', () async {
      expect(await Engine.execute('TRUE XOR x', boundValues: {'x': null}), true);
    });
  });

  // The actual Giants bug: (null > avg + 2 * stdev) AND (stdev > 0)
  // should be false, not true.
  group('Giants predicate scenario — null height in boolean context', () {
    test('null height with positive stdev should not match', () async {
      expect(
        await Engine.execute(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': null, 'avg': 1.78, 'stdev': 0.2},
        ),
        false,
      );
    });

    test('tall height with positive stdev should match', () async {
      expect(
        await Engine.execute(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': 2.5, 'avg': 1.78, 'stdev': 0.2},
        ),
        true,
      );
    });

    test('short height with positive stdev should not match', () async {
      expect(
        await Engine.execute(
          '(height > avg + 2 * stdev) AND (stdev > 0)',
          boundValues: {'height': 1.7, 'avg': 1.78, 'stdev': 0.2},
        ),
        false,
      );
    });
  });
}
