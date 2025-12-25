import 'package:flutter/foundation.dart';

/// Firebase service — pure Dart, no native SDK.
///
/// Firestore sync is handled by [FirestorePreferencesService] via REST.
/// Analytics events are logged to the debug console.
/// Crashlytics is a no-op (no REST API available).
class FirebaseService {
  static bool _analyticsEnabled = false;

  static Future<void> initialize() async {
    debugPrint('FirebaseService initialized (REST mode).');
  }

  static Future<void> setAnalyticsEnabled(bool enabled) async {
    _analyticsEnabled = enabled;
  }

  static Future<void> setCrashlyticsEnabled(bool enabled) async {
    // Crashlytics has no REST API — no-op.
  }

  static Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!_analyticsEnabled) return;
    debugPrint('Analytics: $name ${parameters ?? ''}');
  }
}
