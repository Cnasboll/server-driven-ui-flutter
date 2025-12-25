import 'package:flutter/material.dart';

import '../core/services/firebase_auth_service.dart';

/// Firebase Auth login/register screen.
/// Shown before the app is accessible.
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield, size: 80, color: Colors.white),
                const SizedBox(height: 16),
                const Text(
                  'HeroDex 3000',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Orbitron',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegistering ? 'Create Account' : 'Sign In',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(color: Colors.red[700], fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_isRegistering ? 'Register' : 'Sign In'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() {
                                    _isRegistering = !_isRegistering;
                                    _error = null;
                                  }),
                          child: Text(
                            _isRegistering
                                ? 'Already have an account? Sign in'
                                : "Don't have an account? Register",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
