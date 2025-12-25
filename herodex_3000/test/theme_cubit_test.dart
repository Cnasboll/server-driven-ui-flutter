import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herodex_3000/core/theme/theme_cubit.dart';

void main() {
  group('ThemeCubit', () {
    test('initializes with light mode when isDark is false', () {
      final cubit = ThemeCubit(false);
      expect(cubit.state, ThemeMode.light);
      cubit.close();
    });

    test('initializes with dark mode when isDark is true', () {
      final cubit = ThemeCubit(true);
      expect(cubit.state, ThemeMode.dark);
      cubit.close();
    });

    test('toggle switches from light to dark', () {
      final cubit = ThemeCubit(false);
      cubit.toggle();
      expect(cubit.state, ThemeMode.dark);
      cubit.close();
    });

    test('toggle switches from dark to light', () {
      final cubit = ThemeCubit(true);
      cubit.toggle();
      expect(cubit.state, ThemeMode.light);
      cubit.close();
    });

    test('set changes to specified mode', () {
      final cubit = ThemeCubit(false);
      cubit.set(ThemeMode.dark);
      expect(cubit.state, ThemeMode.dark);
      cubit.set(ThemeMode.light);
      expect(cubit.state, ThemeMode.light);
      cubit.close();
    });
  });
}
