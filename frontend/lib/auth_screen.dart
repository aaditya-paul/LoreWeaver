import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'palette.dart';
import 'projects_screen.dart';

const _baseUrl = 'http://127.0.0.1:8000';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  // null = not checked yet, true = existing user, false = new user
  bool? _userExists;
  bool _loading = false;
  bool _obscurePass = true;
  String _error = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ── Step 1: Email check ──────────────────────────────────────────────────
  Future<void> _checkEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/check-email'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(res.body);
      setState(() => _userExists = data['exists'] as bool);
      _passFocus.requestFocus();
    } catch (e) {
      setState(() => _error = 'Cannot reach backend. Is the server running?');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Step 2: Login or Register ────────────────────────────────────────────
  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final endpoint = _userExists! ? '/auth/login' : '/auth/register';
      final res = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': pass}),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                _AuthSuccess(token: data['access_token'], email: data['email']),
          ),
        );
      } else {
        final msg = jsonDecode(res.body)['detail'] ?? 'Authentication failed.';
        setState(() => _error = msg.toString());
      }
    } catch (e) {
      setState(() => _error = 'Cannot reach backend.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppPalette.redDim,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppPalette.red.withAlpha(130),
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_stories,
                        color: AppPalette.red,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'LoreWeaver',
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Narrative Engine',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 13,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 44),

                // Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _userExists == null
                            ? 'Sign in to continue'
                            : _userExists!
                            ? 'Welcome back'
                            : 'Create your account',
                        style: const TextStyle(
                          color: AppPalette.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userExists == null
                            ? 'Enter your email to continue'
                            : _userExists!
                            ? 'Enter your password to log in'
                            : 'Choose a password to get started',
                        style: const TextStyle(
                          color: AppPalette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Email field
                      _label('EMAIL'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        enabled: _userExists == null && !_loading,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: AppPalette.textPrimary,
                          fontSize: 14,
                        ),
                        cursorColor: AppPalette.red,
                        onSubmitted: (_) =>
                            _userExists == null ? _checkEmail() : null,
                        decoration: _inputDeco('you@example.com'),
                      ),
                      const SizedBox(height: 14),

                      // Password field (shown after email check)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: _userExists == null
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _label('PASSWORD'),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _passCtrl,
                                    focusNode: _passFocus,
                                    obscureText: _obscurePass,
                                    style: const TextStyle(
                                      color: AppPalette.textPrimary,
                                      fontSize: 14,
                                    ),
                                    cursorColor: AppPalette.red,
                                    onSubmitted: (_) => _submit(),
                                    decoration: _inputDeco('••••••••').copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          size: 18,
                                          color: AppPalette.textSecondary,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              ),
                      ),

                      // Error
                      if (_error.isNotEmpty) ...[
                        Text(
                          _error,
                          style: const TextStyle(
                            color: AppPalette.red,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Action button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading
                              ? null
                              : (_userExists == null ? _checkEmail : _submit),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppPalette.border,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 3,
                            shadowColor: AppPalette.redGlow,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _userExists == null
                                      ? 'CONTINUE'
                                      : _userExists!
                                      ? 'LOG IN'
                                      : 'CREATE ACCOUNT',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                        ),
                      ),

                      // Back to email link
                      if (_userExists != null) ...[
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: () => setState(() {
                            _userExists = null;
                            _passCtrl.clear();
                            _error = '';
                          }),
                          child: const Text(
                            'Use a different email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppPalette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: AppPalette.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
    ),
  );

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: AppPalette.card,
    hintStyle: const TextStyle(color: AppPalette.textMuted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.border, width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.red, width: 1.5),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppPalette.border, width: 1.0),
    ),
  );
}

// ─── Intermediate: forward token to ProjectsScreen ───────────────────────────
class _AuthSuccess extends StatelessWidget {
  final String token;
  final String email;
  const _AuthSuccess({required this.token, required this.email});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ProjectsScreen(token: token, email: email),
        ),
      );
    });
    return const Scaffold(
      backgroundColor: AppPalette.bg,
      body: Center(child: CircularProgressIndicator(color: AppPalette.red)),
    );
  }
}
