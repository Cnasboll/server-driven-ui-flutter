import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/services/firebase_auth_service.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/theme_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  final prefs = await SharedPreferences.getInstance();
  // Clean up stale data from previous runs
  for (final key in prefs.getKeys().toList()) {
    final v = prefs.get(key);
    if (v == 'null') await prefs.remove(key);
  }
  // Migrate string-typed booleans to real bools
  for (final key in ['is_dark_mode', 'onboarding_completed', 'analytics_enabled',
      'crashlytics_enabled', 'location_enabled']) {
    final v = prefs.get(key);
    if (v is String) {
      await prefs.setBool(key, v.toLowerCase() == 'true');
    }
  }
  final isDark = prefs.getBool('is_dark_mode') ?? false;
  final authService = await FirebaseAuthService.create(prefs);

  runApp(
    BlocProvider(
      create: (_) => ThemeCubit(isDark),
      child: HeroDexApp(prefs: prefs, authService: authService),
    ),
  );
}
