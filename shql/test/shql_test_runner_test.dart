import 'package:test/test.dart';
import 'package:shql/testing/shql_test_runner.dart';

void main() {
  late ShqlTestRunner r;

  setUp(() async {
    r = ShqlTestRunner.withExpect(expect);
    await r.setUp();
  });

  group('EXPECT', () {
    test('passes when value equals expected', () async {
      await r.test(r'''
        x := 42;
        EXPECT(x, 42)
      ''');
    });

    test('works with computed expressions', () async {
      await r.test(r'''
        a := 10;
        b := 20;
        EXPECT(a + b, 30)
      ''');
    });

    test('works with string values', () async {
      await r.test(r'''
        name := 'Batman';
        EXPECT(name, 'Batman')
      ''');
    });

    test('works with object member access', () async {
      await r.test(r'''
        hero := OBJECT{name: 'Superman', power: 100};
        EXPECT(hero.name, 'Superman');
        EXPECT(hero.power, 100)
      ''');
    });

    test('failed EXPECT contains source location info', () async {
      Object? caughtError;
      final failing = ShqlTestRunner(
        onExpect: (actual, expected, expr) {
          if (actual != expected) throw 'MISMATCH: actual=$actual expected=$expected ($expr)';
        },
      );
      await failing.setUp();
      try {
        await failing.test('x := 1; EXPECT(x, 99)');
      } catch (e) {
        caughtError = e;
      }
      expect(caughtError, isNotNull, reason: 'Should have thrown');
      final msg = caughtError.toString();
      // The RuntimeException wraps the error with source code snippet
      expect(msg, contains('EXPECT'), reason: 'Error should reference EXPECT');
      expect(msg, contains('99'), reason: 'Error should contain expected value');
    });
  });

  group('ASSERT', () {
    test('passes when condition is true', () async {
      await r.test(r'''
        x := 5;
        ASSERT(x > 3)
      ''');
    });

    test('works with boolean values', () async {
      await r.test(r'''
        flag := TRUE;
        ASSERT(flag)
      ''');
    });

    test('failed ASSERT contains source location info', () async {
      Object? caughtError;
      final failing = ShqlTestRunner(
        onExpect: (actual, expected, expr) {
          if (actual != expected) throw 'ASSERTION FAILED: $expr';
        },
      );
      await failing.setUp();
      try {
        await failing.test(r'''
          x := 5;
          ASSERT(x > 100)
        ''');
      } catch (e) {
        caughtError = e;
      }
      expect(caughtError, isNotNull, reason: 'Should have thrown');
      final msg = caughtError.toString();
      // RuntimeException wraps with source snippet containing the failing line
      expect(msg, contains('ASSERT'), reason: 'Error should reference ASSERT');
    });
  });

  group('ASSERT_FALSE', () {
    test('passes when condition is false', () async {
      await r.test(r'''
        x := 1;
        ASSERT_FALSE(x > 10)
      ''');
    });
  });

  group('ASSERT_TRUE', () {
    test('passes with true condition', () async {
      await r.test(r'''
        ASSERT_TRUE(5 > 3, 'five is greater than three')
      ''');
    });
  });

  group('ASSERT_CONTAINS', () {
    test('passes when list contains value', () async {
      await r.test(r'''
        items := ['a', 'b', 'c'];
        ASSERT_CONTAINS(items, 'b')
      ''');
    });

    test('ASSERT_NOT_CONTAINS passes when value absent', () async {
      await r.test(r'''
        items := ['a', 'b'];
        ASSERT_NOT_CONTAINS(items, 'z')
      ''');
    });
  });

  group('ASSERT_CONTAINS_IN_ORDER', () {
    test('passes when values appear in order', () async {
      await r.test(r'''
        log := ['start', 'a', 'x', 'b', 'end'];
        ASSERT_CONTAINS_IN_ORDER(log, ['a', 'b'])
      ''');
    });

    test('handles empty values list', () async {
      await r.test(r'''
        log := ['a', 'b'];
        ASSERT_CONTAINS_IN_ORDER(log, [])
      ''');
    });
  });

  group('ASSERT_CALLED', () {
    test('passes when mock was invoked', () async {
      r.mockUnary('MY_CALLBACK');
      await r.test(r'''
        MY_CALLBACK('hello');
        ASSERT_CALLED('MY_CALLBACK')
      ''');
    });

    test('tracks call log entries', () async {
      r.mockBinary('SAVE');
      await r.test("SAVE('key', 42)");
      expect(r.callLog, contains('SAVE(key, 42)'));
    });
  });

  group('ASSERT_NOT_CALLED', () {
    test('passes when mock was not invoked', () async {
      r.mockUnary('UNUSED_FN');
      await r.test(r'''
        ASSERT_NOT_CALLED('UNUSED_FN')
      ''');
    });
  });

  group('ASSERT_CALL_COUNT', () {
    test('tracks exact invocation count', () async {
      r.mockUnary('COUNTER');
      await r.test(r'''
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
      await r.test(r'''
        FN('a');
        CLEAR_CALL_LOG();
        ASSERT_NOT_CALLED('FN');
        ASSERT_CALL_COUNT('FN', 0)
      ''');
      expect(r.callLog, isEmpty);
    });
  });

  group('makeObject / readField', () {
    test('creates SHQL™ objects usable with EXPECT', () async {
      final hero = r.makeObject({'id': 'h1', 'name': 'Batman'});
      await r.test(r'''
        EXPECT(__h.NAME, 'Batman');
        EXPECT(__h.ID, 'h1')
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
      await r.test(r'''
        result := DOUBLE_IT(5);
        EXPECT(result, 10)
      ''');
    });

    test('mockBinary returns custom value', () async {
      r.mockBinary('ADD', (a, b) => a + b);
      await r.test(r'''
        result := ADD(3, 4);
        EXPECT(result, 7)
      ''');
    });

    test('mockTernary returns custom value', () async {
      r.mockTernary('CLAMP', (v, lo, hi) {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
      });
      await r.test(r'''
        EXPECT(CLAMP(50, 0, 100), 50);
        EXPECT(CLAMP(-5, 0, 100), 0);
        EXPECT(CLAMP(999, 0, 100), 100)
      ''');
    });
  });

  group('integration: multi-step test scenario', () {
    test('object + methods + assertions in one eval', () async {
      r.mockBinary('SAVE_STATE');
      await r.test(r'''
        Counter := OBJECT{
          value: 0,
          INCREMENT: () => BEGIN value := value + 1; SAVE_STATE('counter', value); END,
          RESET: () => BEGIN value := 0; END
        };

        Counter.INCREMENT();
        Counter.INCREMENT();
        Counter.INCREMENT();
        EXPECT(Counter.value, 3);
        ASSERT_CALL_COUNT('SAVE_STATE', 3);

        Counter.RESET();
        EXPECT(Counter.value, 0);
      ''');
    });
  });
}
