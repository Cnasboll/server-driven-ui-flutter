import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../firebase_options.dart';

/// Syncs user preferences to Firestore via REST API.
///
/// Each device gets a stable document at `preferences/{deviceId}`.
/// Writes are fire-and-forget — local SharedPreferences remain the
/// primary store, so the app works offline without issue.
class FirestorePreferencesService {
  FirestorePreferencesService._(this._deviceId);

  final String _deviceId;

  /// Keys that should be synced to Firestore.
  static const syncedKeys = {
    'is_dark_mode',
    'api_key',
    'api_host',
    'onboarding_completed',
    'analytics_enabled',
    'crashlytics_enabled',
    'location_enabled',
    'filters',
  };

  /// Creates the service, generating a stable device ID on first run.
  static Future<FirestorePreferencesService> create(
    SharedPreferences prefs,
  ) async {
    var deviceId = prefs.getString('_device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('_device_id', deviceId);
    }
    return FirestorePreferencesService._(deviceId);
  }

  String get _docUrl =>
      'https://firestore.googleapis.com/v1/projects/${DefaultFirebaseOptions.projectId}'
      '/databases/(default)/documents/preferences/$_deviceId?key=${DefaultFirebaseOptions.apiKey}';

  /// Write a single preference to Firestore (fire-and-forget).
  void save(String key, dynamic value) {
    if (!syncedKeys.contains(key)) return;
    final fields = <String, dynamic>{
      key: _toFirestoreValue(value),
    };
    // PATCH with updateMask so only this field is touched
    final url = '$_docUrl&updateMask.fieldPaths=$key';
    http
        .patch(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fields': fields}),
        )
        .then((_) {})
        .catchError((e) {
          debugPrint('Firestore write failed for "$key": $e');
        });
  }

  /// Load all synced preferences from Firestore.
  /// Returns a map of key → value, or empty map on failure.
  Future<Map<String, dynamic>> loadAll() async {
    try {
      final response = await http.get(Uri.parse(_docUrl));
      if (response.statusCode == 200) {
        final doc = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};
        final result = <String, dynamic>{};
        for (final entry in fields.entries) {
          if (!syncedKeys.contains(entry.key)) continue;
          result[entry.key] = _fromFirestoreValue(entry.value);
        }
        return result;
      }
    } catch (e) {
      debugPrint('Firestore read failed: $e');
    }
    return {};
  }

  /// Convert a Dart value to Firestore REST API value format.
  static Map<String, dynamic> _toFirestoreValue(dynamic value) {
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    return {'stringValue': value.toString()};
  }

  /// Convert a Firestore REST API value back to a Dart value.
  static dynamic _fromFirestoreValue(dynamic value) {
    if (value is! Map<String, dynamic>) return value;
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) return int.tryParse('${value['integerValue']}');
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('stringValue')) return value['stringValue'];
    return value.values.first;
  }
}
