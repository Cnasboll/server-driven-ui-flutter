import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';

/// Firebase Authentication via REST (Identity Toolkit API).
///
/// Persists the ID token and user email in SharedPreferences so the
/// user stays logged in across app restarts.
class FirebaseAuthService {
  FirebaseAuthService._(this._prefs);

  final SharedPreferences _prefs;

  static const _tokenKey = '_auth_id_token';
  static const _emailKey = '_auth_email';
  static const _uidKey = '_auth_uid';

  static const _baseUrl = 'https://identitytoolkit.googleapis.com/v1/accounts';

  static Future<FirebaseAuthService> create(SharedPreferences prefs) async {
    return FirebaseAuthService._(prefs);
  }

  /// Whether the user has a stored auth session.
  bool get isSignedIn => _prefs.getString(_tokenKey) != null;

  String? get email => _prefs.getString(_emailKey);
  String? get uid => _prefs.getString(_uidKey);

  /// Sign in with email + password.
  /// Returns null on success, or an error message on failure.
  Future<String?> signIn(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl:signInWithPassword?key=${DefaultFirebaseOptions.apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        await _persistSession(body);
        return null;
      }

      return _extractError(body);
    } catch (e) {
      debugPrint('Sign-in error: $e');
      return 'Network error. Please check your connection.';
    }
  }

  /// Create a new account with email + password.
  /// Returns null on success, or an error message on failure.
  Future<String?> signUp(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl:signUp?key=${DefaultFirebaseOptions.apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        await _persistSession(body);
        return null;
      }

      return _extractError(body);
    } catch (e) {
      debugPrint('Sign-up error: $e');
      return 'Network error. Please check your connection.';
    }
  }

  /// Sign out — clear stored session.
  Future<void> signOut() async {
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_uidKey);
  }

  Future<void> _persistSession(Map<String, dynamic> body) async {
    final idToken = body['idToken'] as String?;
    final email = body['email'] as String?;
    final uid = body['localId'] as String?;

    if (idToken != null) await _prefs.setString(_tokenKey, idToken);
    if (email != null) await _prefs.setString(_emailKey, email);
    if (uid != null) await _prefs.setString(_uidKey, uid);
  }

  String _extractError(Map<String, dynamic> body) {
    final error = body['error'] as Map<String, dynamic>?;
    final message = error?['message'] as String? ?? 'Unknown error';

    // Translate Firebase error codes to user-friendly messages
    switch (message) {
      case 'EMAIL_NOT_FOUND':
        return 'No account found with this email.';
      case 'INVALID_PASSWORD':
        return 'Incorrect password.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'EMAIL_EXISTS':
        return 'An account already exists with this email.';
      case 'WEAK_PASSWORD : Password should be at least 6 characters':
        return 'Password must be at least 6 characters.';
      case 'INVALID_EMAIL':
        return 'Please enter a valid email address.';
      case 'INVALID_LOGIN_CREDENTIALS':
        return 'Invalid email or password.';
      default:
        if (message.startsWith('WEAK_PASSWORD')) {
          return 'Password must be at least 6 characters.';
        }
        return message;
    }
  }
}
