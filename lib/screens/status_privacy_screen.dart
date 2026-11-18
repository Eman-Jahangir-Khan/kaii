import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../status_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'status_create_screen.dart' show ContactPicker;

/// Status ki default visibility. Naya status banate waqt yehi pehle se chuni hoti hai
/// (har status ke liye badli bhi ja sakti hai).
class StatusPrivacyScreen extends StatefulWidget {
  const StatusPrivacyScreen({super.key});

  @override
  State<StatusPrivacyScreen> createState() => _StatusPrivacyScreenState();
}

class _StatusPrivacyScreenState extends State<StatusPrivacyScreen> {
  String _mode = 'contacts'; // 'contacts' | 'only' | 'except'
  Set<String> _picked = {};
  List<Map<String, String>> _contacts = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await statusRepo.getPrivacy();
      final uids = await statusRepo.contactUids();
      final users = await Future.wait(uids.map((u) async {
        final d = await chatRepo.getUser(u);
        return <String, String>{
          'uid': u,
          'username': (d?['username'] as String?) ?? 'user',
          'photoUrl': (d?['photoUrl'] as String?) ?? '',
        };
      }));
      users.sort((a, b) => a['username']!.compareTo(b['username']!));
      if (!mounted) return;
      setState(() {
        _mode = p.mode;
        // sirf wo log jo ab bhi contacts hain
        _picked = p.uids.toSet().intersection(uids.toSet());
        _contacts = users;
        _loading = false;
      });
    } catch (e) {
      debugPrint('load status privacy error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseContacts() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ContactPicker(
        contacts: _contacts,
        initial: _picked,
        title: _mode == 'only' ? 'Share with' : 'Hide from',
      ),
    );
    if (res != null && mounted) setState(() => _picked = res);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (_mode != 'contacts' && _picked.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Choose at least one contact.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await statusRepo.savePrivacy(
        _mode,
        _mode == 'contacts' ? <String>[] : _picked.toList(),
      );
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Status privacy saved')),
      );
    } catch (e) {
      debugPrint('save status privacy error: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tile(String mode, String title, String subtitle) {
    final selected = _mode == mode;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => setState(() => _mode = mode),
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? AppColors.gold700 : AppColors.brown700,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.brown900,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.brown700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedNames = [
      for (final c in _contacts)
        if (_picked.contains(c['uid'])) c['username']!,
    ];

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Status privacy', showBack: true),
          Expanded(
            child: _loading
                ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold700),
            )
                : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                const Text(
                  'Who can see my status updates',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This is the default for new statuses. You can still change it for each status.',
                  style: TextStyle(color: AppColors.brown700),
                ),
                const SizedBox(height: 12),
                _tile('contacts', 'My contacts',
                    'Everyone you have added'),
                _tile('only', 'Only share with...',
                    'Pick the contacts who can see it'),
                _tile('except', 'My contacts except...',
                    'Hide it from some contacts'),
                if (_mode != 'contacts') ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed:
                      _contacts.isEmpty ? null : _chooseContacts,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text(
                        _picked.isEmpty
                            ? 'Choose contacts'
                            : 'Choose contacts (${_picked.length})',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold700,
                        side:
                        const BorderSide(color: AppColors.gold700),
                      ),
                    ),
                  ),
                  if (selectedNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final n in selectedNames)
                            Chip(
                              label: Text(n),
                              backgroundColor: AppColors.gold200,
                              side: BorderSide.none,
                              labelStyle: const TextStyle(
                                color: AppColors.brown900,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                if (_contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'You have no contacts yet. Add someone from Chats first.',
                      style: TextStyle(color: AppColors.brown700),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Changes apply to new statuses only. Statuses you have already posted keep their old visibility.',
                  style: TextStyle(
                    color: AppColors.brown700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                PillButton(
                  label: 'Save',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}