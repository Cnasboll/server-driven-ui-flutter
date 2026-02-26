import 'package:flutter/material.dart';
import 'package:server_driven_ui/server_driven_ui.dart';

import '../core/services/firebase_auth_service.dart';

/// Firebase Auth login/register screen.
/// Shown before the app is accessible.
///
/// Uses only basic registry types (no YAML templates) because this screen
/// renders before `_initServices()` has loaded any templates.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  final FirebaseAuthService authService;
  final VoidCallback onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isLoading = false;
  String? _error;

  Widget _b(Map<String, dynamic> node, String p) =>
      WidgetRegistry.buildStatic(context, node, 'login.$p');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final errorMsg = _isRegistering
        ? await widget.authService.signUp(email, password)
        : await widget.authService.signIn(email, password);

    if (!mounted) return;

    if (errorMsg == null) {
      widget.onAuthenticated();
    } else {
      setState(() {
        _isLoading = false;
        _error = errorMsg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formChildren = <dynamic>[
      {'type': 'TextField', 'props': {
        'controller': _emailController,
        'keyboardType': 'emailAddress',
        'textInputAction': 'next',
        'decoration': {'labelText': 'Email', 'prefixIcon': 'email', 'border': 'outline'},
      }},
      {'type': 'SizedBox', 'props': {'height': 16}},
      {'type': 'TextField', 'props': {
        'controller': _passwordController,
        'obscureText': true,
        'textInputAction': 'done',
        'dartOnSubmitted': (String _) => _submit(),
        'decoration': {'labelText': 'Password', 'prefixIcon': 'lock', 'border': 'outline'},
      }},
      if (_error != null) ...[
        {'type': 'SizedBox', 'props': {'height': 12}},
        {'type': 'Text', 'props': {'data': _error!, 'style': {'color': '0xFFD32F2F', 'fontSize': 13}}},
      ],
      {'type': 'SizedBox', 'props': {'height': 24}},
      {'type': 'FilledButton', 'props': {
        'onPressed': _isLoading ? null : _submit,
        'child': _isLoading
            ? {'type': 'SizedBox', 'props': {
                'height': 20, 'width': 20,
                'child': {'type': 'CircularProgressIndicator', 'props': {'strokeWidth': 2}},
              }}
            : {'type': 'Text', 'props': {'data': _isRegistering ? 'Register' : 'Sign In'}},
      }},
      {'type': 'SizedBox', 'props': {'height': 12}},
      {'type': 'TextButton', 'props': {
        'onPressed': _isLoading ? null : () => setState(() {
          _isRegistering = !_isRegistering;
          _error = null;
        }),
        'child': {'type': 'Text', 'props': {
          'data': _isRegistering
              ? 'Already have an account? Sign in'
              : "Don't have an account? Register",
        }},
      }},
    ];

    return _b({'type': 'Scaffold', 'props': {
      'backgroundColor': '0xFF1A237E',
      'body': {'type': 'Center', 'child': {
        'type': 'SingleChildScrollView', 'props': {
          'padding': 32,
          'child': {'type': 'ConstrainedBox', 'props': {
            'maxWidth': 400,
            'child': {'type': 'Column', 'props': {
              'mainAxisAlignment': 'center',
              'children': [
                {'type': 'Icon', 'props': {'icon': 'shield', 'size': 80, 'color': '0xFFFFFFFF'}},
                {'type': 'SizedBox', 'props': {'height': 16}},
                {'type': 'Text', 'props': {
                  'data': 'HeroDex 3000',
                  'style': {'fontSize': 28, 'fontWeight': 'bold', 'color': '0xFFFFFFFF', 'fontFamily': 'Orbitron'},
                }},
                {'type': 'SizedBox', 'props': {'height': 8}},
                {'type': 'Text', 'props': {
                  'data': _isRegistering ? 'Create Account' : 'Sign In',
                  'style': {'fontSize': 16, 'color': '0xB3FFFFFF'},
                }},
                {'type': 'SizedBox', 'props': {'height': 32}},
                {'type': 'Card', 'child': {
                  'type': 'Padding', 'props': {
                    'padding': 24,
                    'child': {'type': 'Column', 'props': {
                      'crossAxisAlignment': 'stretch',
                      'children': formChildren,
                    }},
                  },
                }},
              ],
            }},
          }},
        },
      }},
    }}, 'screen');
  }
}
