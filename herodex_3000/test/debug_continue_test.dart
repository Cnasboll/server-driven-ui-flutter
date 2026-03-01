import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shql/engine/engine.dart';
import 'package:shql/execution/runtime/runtime.dart';
import 'package:shql/parser/constants_set.dart';

void main() {
  late ConstantsSet cs;
  late Runtime rt;

  setUp(() async {
    cs = Runtime.prepareConstantsSet();
    rt = Runtime.prepareRuntime(cs);
    final stdlibCode = await File('../shql/assets/stdlib.shql').readAsString();
    await Engine.execute(stdlibCode, runtime: rt, constantsSet: cs);
    rt.saveStateFunction = (key, value) async {};
    rt.loadStateFunction = (key, defaultValue) async => defaultValue;
    rt.navigateFunction = (route) async {};
    rt.notifyListeners = (name) {};
    rt.debugLogFunction = (msg) {};
  });

  test('CONTINUE in FOR loop with IF', () async {
    final r = await Engine.execute(r'''
      __test() := BEGIN
        __result := [];
        FOR __i := 0 TO 2 DO BEGIN
          IF __i = 1 THEN CONTINUE;
          __result := __result + [__i];
        END;
        RETURN __result;
      END;
      __test()
    ''', runtime: rt, constantsSet: cs);
    expect(r, [0, 2]);
  });

  test('CONTINUE in FOR loop with nested IF-ELSE IF', () async {
    final r = await Engine.execute(r'''
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
    ''', runtime: rt, constantsSet: cs);
    expect(r, ['zero', 'after', 'skip', 'two', 'after']);
  });

  test('CONTINUE inside nested IF inside outer IF-THEN-BEGIN-END', () async {
    final r = await Engine.execute(r'''
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
    ''', runtime: rt, constantsSet: cs);
    expect(r, [0, 'skip', 2]);
  });

  test('CONTINUE with search.shql pattern', () async {
    final r = await Engine.execute(r'''
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
    ''', runtime: rt, constantsSet: cs);
    expect(r, ['skipped', 'skipped', 'skipped']);
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('WHILE CONTINUE still works', () async {
    final r = await Engine.execute(
      "x := 0; y := 0; WHILE x < 10 DO BEGIN x := x + 1; IF x % 2 = 0 THEN CONTINUE; y := y + 1; END; y",
      runtime: rt, constantsSet: cs,
    );
    expect(r, 5);
  });

  test('FOR without CONTINUE still works', () async {
    final r = await Engine.execute(
      "sum := 0; FOR i := 1 TO 5 DO sum := sum + i; sum",
      runtime: rt, constantsSet: cs,
    );
    expect(r, 15);
  });
}
