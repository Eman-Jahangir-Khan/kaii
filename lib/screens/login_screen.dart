import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../widgets.dart';
import '../theme.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _hidePassword = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim().toLowerCase() ?? '';
    if (email.isEmpty) return 'Email is required';
    final emailRegex = RegExp(
      r'^[a-z0-9]+@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$',
    );
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email like name123@example.com';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() => _googleLoading = true);
    try {
      final signedIn = await authRepo.signInWithGoogle();
      if (signedIn && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showMessage(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await authRepo.login(
        email: _email.text.trim().toLowerCase(),
        password: _password.text,
      );
      // AuthGate neeche sahi screen dikha deta hai, upar wali screens hata do
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _showMessage(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) {
      _showMessage('Enter your email first, then tap "Forgot Password?"');
      return;
    }
    try {
      await authRepo.sendPasswordReset(email);
      _showMessage('Password reset link sent. Check your email.');
    } catch (e) {
      _showMessage(authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      isLogin: true,
      title: 'Welcome\nBack',
      subtitle: '',
      footerText: "Don't have an account? ",
      footerAction: 'Sign up',
      onSwitch: () {
        final nav = Navigator.of(context);
        final route = fadeRoute(const SignupScreen());
        // root par ho to push, warna replace (stack lamba na ho)
        nav.canPop() ? nav.pushReplacement(route) : nav.push(route);
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            stagger(
              0,
              FieldGroup(
                children: [
                  CardField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  CardField(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscureText: _hidePassword,
                    suffix: IconButton(
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.brown700,
                      ),
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                    ),
                    validator: _validatePassword,
                  ),
                ],
              ),
            ),
            stagger(
              1,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brown700,
                    ),
                    onPressed: _forgotPassword,
                    child: const Text('Forgot Password?'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            stagger(
              2,
              PillButton(
                label: 'Sign In',
                loading: _loading,
                onPressed: _login,
              ),
            ),
            const SizedBox(height: 20),
            stagger(
              3,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OrDivider(),
                  const SizedBox(height: 20),
                  GoogleButton(
                    label: 'Continue with Google',
                    loading: _googleLoading,
                    onPressed: _loading ? null : _google,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}