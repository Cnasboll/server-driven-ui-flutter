import 'package:server_driven_ui/shql/engine/engine.dart';
import 'package:server_driven_ui/shql/execution/runtime/runtime.dart';
import 'package:server_driven_ui/shql/parser/constants_set.dart';
import 'package:server_driven_ui/shql/parser/lookahead_iterator.dart';
import 'package:server_driven_ui/shql/parser/parser.dart';
import 'package:server_driven_ui/shql/tokenizer/token.dart';
import 'package:server_driven_ui/shql/tokenizer/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(Runtime, ConstantsSet)> _loadStdLib() async {
  var constantsSet = Runtime.prepareConstantsSet();
  var runtime = Runtime.prepareRuntime(constantsSet);
  final stdlibCode = """
--- External unary fuctions
CLONE(a) := _EXTERN("CLONE", [a]);
MD5(a) := _EXTERN("MD5", [a]);
SIN(a) := _EXTERN("SIN", [a]);
COS(a) := _EXTERN("COS", [a]);
TAN(a) := _EXTERN("TAN", [a]);
ACOS(a) := _EXTERN("ACOS", [a]);
ASIN(a) := _EXTERN("ASIN", [a]);
ATAN(a) := _EXTERN("ATAN", [a]);
SQRT(a) := _EXTERN("SQRT", [a]);
EXP(a) := _EXTERN("EXP", [a]);
LOG(a) := _EXTERN("LOG", [a]);
LOWERCASE(a) := _EXTERN("LOWERCASE", [a]);
UPPERCASE(a) := _EXTERN("UPPERCASE", [a]);
INT(a) := _EXTERN("INT", [a]);
DOUBLE(a) := _EXTERN("DOUBLE", [a]);
STRING(a) := _EXTERN("STRING", [a]);
ROUND(a) := _EXTERN("ROUND", [a]);
LENGTH(a) := _EXTERN("LENGTH", [a]);
MD5(a) := _EXTERN("MD5", [a]);

-- External binary functions
MIN(a,b) := _EXTERN("MIN", [a,b]);
MAX(a,b) := _EXTERN("MAX", [a,b]);
ATAN2(a,b) := _EXTERN("ATAN2", [a,b]);
POW(a,b) := _EXTERN("POW", [a,b]);
DIM(a,b) := _EXTERN("DIM", [a,b]);

-- External ternary functions
SUBSTRING(a, b, c) := _EXTERN("SUBSTRING", [a, b, c]);

-- Plot a function
PLOT(f, x1, x2) := BEGIN
    x_vector := [];
    y_vector := [];
    range := DOUBLE(x2)-DOUBLE(x1)
    step := MAX(0.1, range / 100.0);
    start := DOUBLE(x1);
    FOR x := start to X2 STEP step DO BEGIN
        x_vector := x_vector + [x];
        y_vector := y_vector + [f(x)];
        if x > start then
            _DISPLAY_GRAPH(x_vector, y_vector);    
    END;
    PRINT("Type HIDE_GRAPH to hide graph again");
END;

""";
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
}
