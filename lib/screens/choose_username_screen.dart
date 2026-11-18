import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_repository.dart';
import '../widgets.dart';

/// Keyboard ka auto-capital ("Eman") lowercase mein badal deta hai.
/// Pehle neeche wala allow-filter capital letter ko chupke se delete kar
/// deta tha, isi wajah se pehla letter ghaib ho jata tha.
class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key});

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Username is required';
    if (name.length < 6) return 'At least 6 characters';
    if (name.startsWith('.') || name.endsWith('.')) {
      return 'Username cannot start or end with a dot';
    }
    if (name.contains('..')) {
      return 'Username cannot have two dots in a row';
    }
    return null;
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
      // profile ban jate hi AuthGate khud Home dikha dega
      await authRepo.createProfile(username: username);
    } catch (e, st) {
      // asli error console mein dikhega (flutter run / Logcat)
      debugPrint('ChooseUsername error: $e\n$st');
      _showMessage(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      isLogin: false,
      title: 'Choose\nUsername',
      subtitle: '',
      footerText: 'Not you? ',
      footerAction: 'Log out',
      onSwitch: authRepo.logout,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 28),
            stagger(
              0,
              CardField(
                controller: _username,
                label: 'Username',
                icon: Icons.alternate_email,
                helper: '6-20 characters: small letters, numbers, underscore, dot',
                inputFormatters: [
                  _LowerCaseFormatter(), // sab se pehle lowercase, phir filter
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                validator: _validateUsername,
              ),
            ),
            const SizedBox(height: 28),
            stagger(
              1,
              PillButton(
                label: 'Continue',
                loading: _loading,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}