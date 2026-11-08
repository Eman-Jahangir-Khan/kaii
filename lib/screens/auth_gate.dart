import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_repository.dart';
import 'choose_username_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';
import 'main_shell.dart';

/// Logged out -> Login, unverified -> Verify,
/// verified but no profile (Google) -> Choose username, else Home
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const _loading = Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authRepo.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loading;
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        if (!user.emailVerified) return const VerifyEmailScreen();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey(user.uid),
          stream: authRepo.profileStream(user.uid),
          builder: (context, p) {
            if (!p.hasData) return _loading;
            final doc = p.data!;
            // cache se "nahi hai" aaye to server ka jawab ka intezar karo
            if (!doc.exists && doc.metadata.isFromCache) return _loading;
            if (!doc.exists) return const ChooseUsernameScreen();
            return const MainShell();
          },
        );
      },
    );
  }
}