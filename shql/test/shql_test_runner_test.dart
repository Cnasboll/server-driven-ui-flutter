import 'package:test/test.dart';
import 'package:shql/testing/shql_test_runner.dart';

void main() {
  late ShqlTestRunner r;

  setUp(() async {
    r = ShqlTestRunner.withExpect(expect);
    await r.setUp();
  });

  group('EXPECT', () {
    test('passes when expression evaluates to expected value', () async {
      await r.eval(r'''
        x := 42;
        EXPECT("x", 42)
      ''');
    });

    test('works with computed expressions', () async {
      await r.eval(r'''
        a := 10;
        b := 20;
        EXPECT("a + b", 30)
      ''');
    });

    test('works with string values', () async {
      await r.eval(r'''
        name := 'Batman';
        EXPECT("name", 'Batman')
      ''');
    });

    test('works with object member access', () async {
      await r.eval(r'''
        hero := OBJECT{name: 'Superman', power: 100};
        EXPECT("hero.name", 'Superman');
        EXPECT("hero.power", 100)
      ''');
    });

    test('fails when values do not match', () async {
      var failedExpr = '';
      final failing = ShqlTestRunner(
        onExpect: (actual, expected, expr) {
          if (actual != expected) failedExpr = expr;
        },
      );
      await failing.setUp();
      await failing.eval('x := 1; EXPECT("x", 99)');
      expect(failedExpr, contains('EXPECT'));
      expect(failedExpr, contains('x'));
    });
  });

  group('ASSERT', () {
    test('passes when expression is true', () async {
      await r.eval(r'''
        x := 5;
        ASSERT("x > 3")
      ''');
    });

    test('works with boolean expressions', () async {
      await r.eval(r'''
        flag := TRUE;
        ASSERT("flag")
      ''');
    });
  });

  group('ASSERT_FALSE', () {
    test('passes when expression is false', () async {
      await r.eval(r'''
        x := 1;
        ASSERT_FALSE("x > 10")
      ''');
    });
  });

  group('EXPECT_EQ', () {
    test('passes with direct value comparison', () async {
      await r.eval(r'''
        total := 3 + 4;
        EXPECT_EQ(total, 7, 'addition result')
      ''');
    });
  });

  group('ASSERT_TRUE', () {
    test('passes with true condition', () async {
      await r.eval(r'''
        ASSERT_TRUE(5 > 3, 'five is greater than three')
      ''');
    });
  });

  group('ASSERT_CALLED', () {
    test('passes when mock was invoked', () async {
      r.mockUnary('MY_CALLBACK');
      await r.eval(r'''
        MY_CALLBACK('hello');
        ASSERT_CALLED('MY_CALLBACK')
      ''');
    });

    test('tracks call log entries', () async {
      r.mockBinary('SAVE');
      await r.eval("SAVE('key', 42)");
      expect(r.callLog, contains('SAVE(key, 42)'));
    });
  });

  group('ASSERT_NOT_CALLED', () {
    test('passes when mock was not invoked', () async {
      r.mockUnary('UNUSED_FN');
      await r.eval(r'''
        ASSERT_NOT_CALLED('UNUSED_FN')
      ''');
    });
  });

  group('ASSERT_CALL_COUNT', () {
    test('tracks exact invocation count', () async {
      r.mockUnary('COUNTER');
      await r.eval(r'''
        COUNTER(1);
        COUNTER(2);
        COUNTER(3);
        ASSERT_CALL_COUNT('COUNTER', 3)
      ''');
    });
  });

  group('CLEAR_CALL_LOG', () {
    test('resets call tracking', () async {
      r.mockUnary('FN');
      await r.eval(r'''
        FN('a');
        CLEAR_CALL_LOG();
        ASSERT_NOT_CALLED('FN');
        ASSERT_CALL_COUNT('FN', 0)
      ''');
      expect(r.callLog, isEmpty);
    });
  });

  group('makeObject / readField', () {
    test('creates SHQL objects usable with EXPECT', () async {
      final hero = r.makeObject({'id': 'h1', 'name': 'Batman'});
      // Use EXPECT_EQ for direct value assertions on bound objects
      await r.eval(r'''
        EXPECT_EQ(__h.NAME, 'Batman', '__h.NAME');
        EXPECT_EQ(__h.ID, 'h1', '__h.ID')
      ''', boundValues: {'__h': hero});
    });

    test('readField extracts values', () {
      final obj = r.makeObject({'score': 42});
      expect(r.readField(obj, 'score'), 42);
    });
  });

  group('mock with implementation', () {
    test('mockUnary returns custom value', () async {
      r.mockUnary('DOUBLE_IT', (x) => x * 2);
      await r.eval(r'''
        result := DOUBLE_IT(5);
        EXPECT("result", 10)
      ''');
    });

    test('mockBinary returns custom value', () async {
      r.mockBinary('ADD', (a, b) => a + b);
      await r.eval(r'''
        result := ADD(3, 4);
        EXPECT("result", 7)
      ''');
    });

    test('mockTernary returns custom value', () async {
      r.mockTernary('CLAMP', (v, lo, hi) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
      });
      await r.eval(r'''
        EXPECT("CLAMP(50, 0, 100)", 50);
        EXPECT("CLAMP(-5, 0, 100)", 0);
        EXPECT("CLAMP(999, 0, 100)", 100)
      ''');
    });
  });

  group('integration: multi-step test scenario', () {
    test('object + methods + assertions in one eval', () async {
      r.mockBinary('SAVE_STATE');
      await r.eval(r'''
        Counter := OBJECT{
          value: 0,
          INCREMENT: () => BEGIN value := value + 1; SAVE_STATE('counter', value); END,
          RESET: () => BEGIN value := 0; END
        };

        Counter.INCREMENT();
        Counter.INCREMENT();
        Counter.INCREMENT();
        EXPECT("Counter.value", 3);
        ASSERT_CALL_COUNT('SAVE_STATE', 3);

        Counter.RESET();
        EXPECT("Counter.value", 0);
      ''');
    });
  });
}
