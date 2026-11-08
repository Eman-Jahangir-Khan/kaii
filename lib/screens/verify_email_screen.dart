import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../widgets.dart';
import '../theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _timer;
  bool _sending = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Har 3 second baad check: verify hote hi AuthGate Home dikha dega
    _timer = Timer.periodic(
      const Duration(seconds: 3),
          (_) => authRepo.checkEmailVerified(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await authRepo.resendVerificationEmail();
      _showMessage('Verification email sent again.');
    } catch (e) {
      _showMessage(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final verified = await authRepo.checkEmailVerified();
      if (!verified) _showMessage('Email not verified yet.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = authRepo.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold500.withValues(alpha: 0.18),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 56,
                    color: AppColors.gold700,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brown900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n$email\nOpen it, then come back here.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.brown700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),
              PillButton(
                label: "I've verified",
                loading: _checking,
                onPressed: _checkNow,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed: _sending ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold700,
                    disabledForegroundColor:
                    AppColors.gold700.withValues(alpha: 0.5),
                    side: BorderSide(
                      color: _sending
                          ? AppColors.gold700.withValues(alpha: 0.4)
                          : AppColors.gold700,
                      width: 1.5,
                    ),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.gold700,
                    ),
                  )
                      : const Text('Resend email'),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: TextButton.icon(
                  onPressed: authRepo.logout,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brown700,
                  ),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text(
                    'Use a different account',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}