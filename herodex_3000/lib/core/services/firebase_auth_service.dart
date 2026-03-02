import 'package:shared_preferences/shared_preferences.dart';

/// Firebase Auth startup check.
///
/// auth.shql handles sign-in/sign-up/sign-out (pure SHQL™).
/// This class checks whether a stored auth session exists so the
/// app can decide whether to show the login screen before SHQL™ boots.
class FirebaseAuthService {
  FirebaseAuthService._(this._prefs);

  final SharedPreferences _prefs;

  static Future<FirebaseAuthService> create(SharedPreferences prefs) async {
    return FirebaseAuthService._(prefs);
  }

  /// Whether the user has a stored auth session.
  bool get isSignedIn => _prefs.getString('_auth_id_token') != null;
}
