import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(bool isDark) : super(isDark ? ThemeMode.dark : ThemeMode.light);

  void toggle() => emit(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void set(ThemeMode mode) => emit(mode);
}
