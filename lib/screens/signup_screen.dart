import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_repository.dart';
import '../widgets.dart';
import '../theme.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _hidePassword = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
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

  String? _validateUsername(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Username is required';
    if (name.length < 3) return 'At least 3 characters';
    if (name.startsWith('.') || name.endsWith('.')) {
      return 'Username cannot start or end with a dot';
    }
    if (name.contains('..')) {
      return 'Username cannot have two dots in a row';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Use both letters and numbers';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _password.text) return 'Passwords do not match';
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

    Future<void> _submit() async {
      if (!_formKey.currentState!.validate()) return;
      FocusScope.of(context).unfocus();
      setState(() => _loading = true);

      try {
        final username = _username.text.trim().toLowerCase();

        if (!await authRepo.isUsernameAvailable(username)) {
          _showMessage('This username is already taken.');
          return;
        }

        await authRepo.signUp(
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
          username: username,
        );

        // AuthGate neeche verify screen dikha chuka hota hai, wahan wapas jao
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        _showMessage(authErrorMessage(e));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      return AuthShell(
        isLogin: false,
        showBack: true,
        title: 'Create\nAccount',
        subtitle: '',
        footerText: 'Already have an account? ',
        footerAction: 'Login',
        onSwitch: () =>
            Navigator.of(context)
                .pushReplacement(fadeRoute(const LoginScreen())),
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
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(254),
                      ],
                      validator: _validateEmail,
                    ),
                    CardField(
                      controller: _username,
                      label: 'Username',
                      icon: Icons.alternate_email,
                      helper: '3-20 characters: small letters, numbers, underscore, dot',
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-z0-9_.]')),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      validator: _validateUsername,
                    ),
                    CardField(
                      controller: _password,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: _hidePassword,
                      helper: '8+ characters with letters and numbers',
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
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
                    CardField(
                      controller: _confirm,
                      label: 'Confirm Password',
                      icon: Icons.lock_outline,
                      obscureText: _hidePassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      validator: _validateConfirm,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              stagger(
                1,
                PillButton(
                  label: 'Sign Up',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ),
              const SizedBox(height: 20),
              stagger(
                2,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const OrDivider(),
                    const SizedBox(height: 20),
                    GoogleButton(
                      label: 'Sign up with Google',
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